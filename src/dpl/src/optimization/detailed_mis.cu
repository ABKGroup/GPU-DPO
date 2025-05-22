// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

////////////////////////////////////////////////////////////////////////////////
// Description:
// An implementation of maximum independent set matching to reduce either
// wirelength of displacement.
//
// The idea is to color the nodes (for wirelength).  Then, one can solve
// a matching problem to optimize for wirelength.  Nodes with the same
// color do not share nets so they can be repositioned without worsening
// wirelength.  Note that for displacement optimization, colors are not
// needed.
//
// There are likely many improvements which can be made to this code
// regarding the selection of nodes, etc.

#include "detailed_mis.cuh"

#include <algorithm>
#include <boost/tokenizer.hpp>
#include <cmath>
#include <cstddef>
#include <limits>
#include <map>
#include <queue>
#include <string>
#include <utility>
#include <vector>
#include <cstdio>
#include <curand.h>
#include <curand_kernel.h>
#include <omp.h>

#include "detailed_manager.h"
#include "infrastructure/architecture.h"
#include "infrastructure/detailed_segment.h"

#include "infrastructure/network.h"
#include "utl/Logger.h"

#include "util/apply_solution.cuh"
#include "util/auction.cuh"
#include "util/collect_independent_sets.cuh"
#include "util/cost_matrix_construction.cuh"
#include "util/cpu_state.cuh"
#include "util/maximal_independent_set.cuh"
#include "util/shuffle.cuh"

using utl::DPL;

namespace dpl {

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedMis::DetailedMis(Architecture* arch,
                         Network* network)
    : arch_(arch), network_(network)
{
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::run(DetailedMgr* mgrPtr, GpuData& db_, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, db_, args);
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
template <typename T>
__global__ void iota(T* a, int n) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x) {
    a[i] = i;
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
__global__ void cost_matrix_init(int* cost_matrix, int set_size) {
  for (int i = blockIdx.x; i < set_size; i += gridDim.x) {
    for (int j = threadIdx.x; j < set_size; j += blockDim.x) {
      cost_matrix[i * set_size + j] = (i == j) ? 0 : cuda::numeric_limits<int>::max();
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
template <typename T>
__global__ void print_global(T* a, int n) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    printf("[%d]\n", n);
    for (int i = 0; i < n; ++i) {
      printf("%g ", (double)a[i]);
    }
    printf("\n");
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
template <typename T>
__global__ void print_cost_matrix(const T* cost_matrix, int set_size, bool major) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    printf("[%dx%d]\n", set_size, set_size);
    for (int r = 0; r < set_size; ++r) {
      for (int c = 0; c < set_size; ++c) {
        if (major)  // column major
        {
          printf("%g ", (double)cost_matrix[c * set_size + r]);
        } else {
          printf("%g ", (double)cost_matrix[r * set_size + c]);
        }
      }
      printf("\n");
    }
    printf("\n");
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
template <typename T>
__global__ void print_solution(const T* solution, int n) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    printf("[%d]\n", n);
    for (int i = 0; i < n; ++i) {
      printf("%g ", (double)solution[i]);
    }
    printf("\n");
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void construct_spaces(GpuData& db,
                      const int* host_x,
                      const int* host_y,
                      const int* host_node_size_x,
                      const int* host_node_size_y,
                      std::vector<Space>& host_spaces,
                      int num_threads) {
  std::vector<std::vector<int>> row2node_map(db.num_sites_y);
  db.make_row2node_map(host_x, host_y, host_node_size_x, host_node_size_y, db.num_nodes, row2node_map);
  // construct spaces
  host_spaces.resize(db.num_nodes);
  for (int i = 0; i < db.num_sites_y; ++i) {
    for (unsigned int j = 0; j < row2node_map[i].size(); ++j) {
      auto const& row2nodes = row2node_map[i];
      int node_id = row2nodes[j];
      auto& space = host_spaces[node_id]; // this line is an error
      if (node_id < db.num_movable_nodes) {
        auto left_bound = db.xl;
        if (j) {
          left_bound = host_x[node_id];
        }
        space.xl = ceilDiv(left_bound - db.xl, db.site_width) * db.site_width + db.xl;

        auto right_bound = db.xh;
        if (j + 1 < row2nodes.size()) {
          int right_node_id = row2nodes[j + 1];
          right_bound = min(right_bound, host_x[right_node_id]);
        }
        space.xh = std::floor(right_bound);
        space.xh = floorDiv(space.xh - db.xl, db.site_width) * db.site_width + db.xl; 
      }
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::run(DetailedMgr* mgrPtr, GpuData& db_, std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgrPtr_ = mgrPtr;
  // db_ = mgrPtr_->getGpuData();

  int passes = 30;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    } /*else if (args[i] == "-d") {
      obj_ = DetailedMis::Disp;
    }*/ else if (args[i] == "-batch" && i + 1 < args.size()) {
      batchSize_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "-binX" && i + 1 < args.size()) {
      numBinsX_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "-binY" && i + 1 < args.size()) {
      numBinsY_ = std::atoi(args[++i].c_str());
    }
  }
  tol = std::max(tol, 0.01);
  passes = std::max(passes, 1);

  db_.set_num_bins(numBinsX_, numBinsY_);
  IndependentSetMatchingState state;

  // initialize host database
  CpuData host_db;
  init_cpu_db(db_, host_db);

  state.batch_size = batchSize_;
  state.set_size = setSize_;
  state.cost_matrix_size = state.set_size * state.set_size;
  state.num_bins = db_.num_bins_x * db_.num_bins_y;
  state.num_moved = 0;
  state.large_number = ((db_.xh - db_.xl) + (db_.yh - db_.yl)) * setSize_;
  state.skip_threshold = ((db_.xh - db_.xl) + (db_.yh - db_.yl)) * 0.01;
  state.auction_max_eps = 10.0;
  state.auction_min_eps = 1.0;
  state.auction_factor = 0.1;
  state.auction_max_iterations = 9999;

  checkCuda(cudaMemcpy(host_db.x.data(), db_.x, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(cudaMemcpy(host_db.y.data(), db_.y, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));
  std::vector<Space> host_spaces(db_.num_nodes);
  construct_spaces(db_,
                    host_db.x.data(),
                    host_db.y.data(),
                    host_db.node_size_x.data(),
                    host_db.node_size_y.data(),
                    host_spaces,
                    db_.num_threads);

  // initialize cuda state

  allocateCopyCuda(state.spaces, host_spaces.data(), db_.num_nodes);
  allocateCuda(state.ordered_nodes, db_.num_movable_nodes, int);
  iota<<<ceilDiv(db_.num_movable_nodes, 512), 512>>>(state.ordered_nodes, db_.num_movable_nodes);
  allocateCuda(state.independent_sets, state.batch_size * state.set_size, int);
  allocateCuda(state.independent_set_sizes, state.batch_size, int);
  allocateCuda(state.selected_maximal_independent_set, db_.num_movable_nodes, int);
  allocateCuda(state.select_scratch, db_.num_movable_nodes, int);
  allocateCuda(state.device_num_selected, 1, int);
  allocateCuda(state.orig_x, state.batch_size * state.set_size, int);
  allocateCuda(state.orig_y, state.batch_size * state.set_size, int);
  allocateCuda(state.orig_seg, state.batch_size * state.set_size, int);
  allocateCuda(state.orig_spaces, state.batch_size * state.set_size, Space);
  allocateCuda(state.selected_markers, db_.num_nodes, int);
  allocateCuda(state.dependent_markers, db_.num_nodes, unsigned char);
  allocateCuda(state.independent_set_empty_flag, 1, int);
  allocateCuda(state.cost_matrices,
                state.batch_size * state.set_size * state.set_size,
                int);
  allocateCuda(state.cost_matrices_copy,
                state.batch_size * state.set_size * state.set_size,
                int);
  allocateCuda(state.solutions, state.batch_size * state.set_size, int);
  allocateCuda(
      state.orig_costs, state.batch_size * state.set_size, int);
  allocateCuda(state.solution_costs,
                state.batch_size * state.set_size,
                int);
  allocateCuda(state.net_hpwls, db_.num_nets, int);
  allocateCopyCuda(state.device_num_moved, &state.num_moved, 1);

  init_auction<float>(state.batch_size, state.set_size, state.auction_scratch, state.stop_flags);

  Shuffler<int, unsigned int> shuffler(2023ULL, state.ordered_nodes, db_.num_movable_nodes);

  // initialize host state
  IndependentSetMatchingCPUState host_state;
  init_cpu_state(db_, state, host_state);

  // initialize kmeans state
  KMeansState<int> kmeans_state;
  init_kmeans(db_, state, kmeans_state);

  int64_t curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);
  const int64_t init_hpwl = curr_hpwl;

  // double tot_disp, max_disp, avg_disp;
  // double curr_disp = Utility::disp_l1(network_, tot_disp, max_disp, avg_disp);
  // const double init_disp = curr_disp;

  for (int p = 1; p <= passes; p++) {
    // const double curr_obj = (obj_ == DetailedMis::Hpwl) ? curr_hpwl : curr_disp;

    printf("[INFO GPU-DPO] Pass %d of matching; objective is %d.\n", p, curr_hpwl);

    shuffler();
    checkCuda(cudaDeviceSynchronize());

    maximal_independent_set(db_, state);
    checkCuda(cudaDeviceSynchronize());

    collect_independent_sets(db_, state, kmeans_state, host_db, host_state);
    checkCuda(cudaDeviceSynchronize());

    cost_matrix_construction(db_, state);
    checkCuda(cudaDeviceSynchronize());

    // solve independent sets
    // print_cost_matrix<<<1, 1>>>(state.cost_matrices + state.cost_matrix_size*3, state.set_size, 0);
    linear_assignment_auction(state.cost_matrices,
                              state.solutions,
                              state.num_independent_sets,
                              state.set_size,
                              state.auction_scratch,
                              state.stop_flags,
                              state.auction_max_eps,
                              state.auction_min_eps,
                              state.auction_factor,
                              state.auction_max_iterations);
    checkCuda(cudaDeviceSynchronize());
    // print_solution<<<1, 1>>>(state.solutions + state.set_size*3, state.set_size);

    // apply solutions
    apply_solution(db_, state);
    checkCuda(cudaDeviceSynchronize());

    const int64_t last_hpwl = curr_hpwl;
    curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);
    // if (/*obj_ == DetailedMis::Hpwl
    //     &&*/ std::abs(curr_hpwl - last_hpwl) / (double) last_hpwl <= tol) {
    //   break;
    // }
    // const double last_disp = curr_disp;
    // curr_disp = Utility::disp_l1(network_, tot_disp, max_disp, avg_disp);
    // if (obj_ == DetailedMis::Disp
    //     && std::fabs(curr_disp - last_disp) / last_disp <= tol) {
    //   break;
    // }
  }

  double hpwl_imp = (((init_hpwl - curr_hpwl) / (double) init_hpwl) * 100.);
  // } else {
  //   const double disp_imp = (((init_disp - curr_disp) / init_disp) * 100.);
  //   curr_imp = disp_imp;
  //   curr_obj = curr_disp;
  // }
  printf("[INFO GPU-DPO] End of matching; objective is %d, improvement is %f percent.\n", curr_hpwl,
      hpwl_imp);

  // destroy state
  cudaFree(state.spaces);
  cudaFree(state.ordered_nodes);
  cudaFree(state.independent_sets);
  cudaFree(state.independent_set_sizes);
  cudaFree(state.selected_maximal_independent_set);
  cudaFree(state.select_scratch);
  cudaFree(state.device_num_selected);
  cudaFree(state.net_hpwls);
  cudaFree(state.cost_matrices);
  cudaFree(state.cost_matrices_copy);
  cudaFree(state.solutions);
  cudaFree(state.orig_costs);
  cudaFree(state.solution_costs);
  cudaFree(state.orig_x);
  cudaFree(state.orig_y);
  cudaFree(state.orig_seg);
  cudaFree(state.orig_spaces);
  cudaFree(state.selected_markers);
  cudaFree(state.dependent_markers);
  cudaFree(state.independent_set_empty_flag);
  cudaFree(state.device_num_moved);
  destroy_auction(state.auction_scratch, state.stop_flags);
  destroy_kmeans(kmeans_state);
}

}  // namespace dpl
