// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include "detailed_reorder.cuh"

#include <algorithm>
#include <boost/tokenizer.hpp>
#include <cstddef>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>
#include <cmath>
#include <omp.h>
#include <fstream>

#include "detailed_manager.h"
#include "infrastructure/architecture.h"
#include "infrastructure/detailed_segment.h"
#include "util/utility.h"
#include "utl/Logger.h"

using utl::DPL;

namespace dpl {

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
DetailedReorderer::DetailedReorderer(Architecture* arch, Network* network)
    : arch_(arch), network_(network)
{
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::run(DetailedMgr* mgrPtr, GpuData& db, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, db, args);
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void compute_reorder_instances(const GpuData& db,
                               const std::vector<std::vector<int>>& state_row2node_map,
                               const std::vector<std::vector<int>>& state_independent_rows,
                               std::vector<std::vector<KReorderInstance>>& state_reorder_instances,
                               int K) {
  state_reorder_instances.resize(state_independent_rows.size());

  for (unsigned int group_id = 0; group_id < state_independent_rows.size(); ++group_id) {
    auto const& independent_rows = state_independent_rows.at(group_id);
    auto& reorder_instances = state_reorder_instances.at(group_id);
    for (auto row_id : independent_rows) {
      auto const& row2nodes = state_row2node_map.at(row_id);
      int num_nodes_in_row = row2nodes.size();
      for (int sub_id = 0; sub_id < num_nodes_in_row; sub_id += K) {
        int idx_bgn = sub_id;
        int idx_end = std::min(sub_id + K, num_nodes_in_row);
        // stop at fixed cells and multi-row height cells
        for (int i = idx_bgn; i < idx_end; ++i) {
          int node_id = row2nodes.at(i);
          if (node_id >= db.num_movable_nodes || db.node_size_y[node_id] > db.row_height) {
            idx_end = i;
            break;
          }
        }
        if (idx_end - idx_bgn >= 2) {
          KReorderInstance inst;
          inst.group_id = group_id;
          inst.row_id = row_id;
          inst.idx_bgn = idx_bgn;
          inst.idx_end = idx_end;
          reorder_instances.push_back(inst);
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void compute_row_conflict_graph(const GpuData& db,
                                const std::vector<std::vector<int>>& state_row2node_map,
                                std::vector<unsigned char>& state_adjacency_matrix,
                                std::vector<std::vector<int>>& state_row_graph,
                                int num_threads) {
  // adjacency matrix
  state_adjacency_matrix.assign(db.num_sites_y * db.num_sites_y, 0);
#pragma omp parallel for num_threads(num_threads) schedule(dynamic, 1)
  for (int net_id = 0; net_id < db.num_nets; ++net_id) {
    if (db.net_mask[net_id]) {
      int net2pin_start = db.flat_net2pin_start_map[net_id];
      int net2pin_end = db.flat_net2pin_start_map[net_id + 1];
      for (int net2pin_id1 = net2pin_start; net2pin_id1 < net2pin_end; ++net2pin_id1) {
        int net_pin_id1 = db.flat_net2pin_map[net2pin_id1];
        int node_id1 = db.pin2node_map[net_pin_id1];
        if (node_id1 < db.num_movable_nodes) {
          int row_id1 = floorDiv(db.y[node_id1] - db.yl, db.row_height);
          row_id1 = std::min(std::max(row_id1, 0), db.num_sites_y - 1);
          for (int net2pin_id2 = net2pin_id1; net2pin_id2 < net2pin_end; ++net2pin_id2) {
            int net_pin_id2 = db.flat_net2pin_map[net2pin_id2];
            int node_id2 = db.pin2node_map[net_pin_id2];
            if (node_id2 < db.num_movable_nodes) {
              int row_id2 = floorDiv(db.y[node_id2] - db.yl, db.row_height);
              row_id2 = std::min(std::max(row_id2, 0), db.num_sites_y - 1);
              unsigned char& adjacency_matrix_element1 =
                    state_adjacency_matrix.at(row_id1 * db.num_sites_y + row_id2);
              unsigned char& adjacency_matrix_element2 =
                    state_adjacency_matrix.at(row_id2 * db.num_sites_y + row_id1);
              if (!adjacency_matrix_element1) {
#pragma omp atomic
                adjacency_matrix_element1 |= 1;
              }
              if (!adjacency_matrix_element2) {
#pragma omp atomic
                adjacency_matrix_element2 |= 1;
              }
            }
          }
        }
      }
    }
  }
  // adjacency list
  state_row_graph.assign(db.num_sites_y, std::vector<int>());
#pragma omp parallel for num_threads(num_threads)
  for (int row_id = 0; row_id < db.num_sites_y; ++row_id) {
    auto& adjacency_vec = state_row_graph[row_id];
    for (int other_row_id = 0; other_row_id < db.num_sites_y; ++other_row_id) {
      if (row_id != other_row_id && state_adjacency_matrix.at(row_id * db.num_sites_y + other_row_id)) {
        adjacency_vec.push_back(other_row_id);
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void compute_independent_rows(const GpuData& db,
                              const std::vector<std::vector<int>>& state_row_graph,
                              std::vector<std::vector<int>>& state_independent_rows) {
  // generate independent sets of rows
  std::vector<unsigned char> dependent_markers(db.num_sites_y, 0);
  std::vector<unsigned char> selected_markers(db.num_sites_y, 0);
  int num_selected = 0;
  while (num_selected < db.num_sites_y) {
    std::vector<int> independent_rows;
    for (int row_id = 0; row_id < db.num_sites_y; ++row_id) {
      if (!dependent_markers[row_id] && !selected_markers[row_id]) {
        independent_rows.push_back(row_id);
        dependent_markers[row_id] = 1;
        selected_markers[row_id] = 1;
        num_selected += 1;

        for (auto other_row_id : state_row_graph[row_id]) {
          dependent_markers[other_row_id] = 1;
        }
      }
    }
    // recover marker
    for (auto i : independent_rows) {
      for (auto other_row_id : state_row_graph[i]) {
        dependent_markers[other_row_id] = 0;
      }
    }
    state_independent_rows.push_back(independent_rows);
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void make_row2node_map(const GpuData& db,
                       const int* vx,
                       const int* vy,
                       std::vector<std::vector<int>>& row2node_map,
                       int num_threads) {
  // distribute cells to rows
  for (int i = 0; i < db.num_nodes; ++i) {
    int node_yl = vy[i];
    int node_yh = node_yl + db.node_size_y[i];

    int row_idxl = floorDiv(node_yl - db.yl, db.row_height);
    int row_idxh = ceilDiv(node_yh - db.yl, db.row_height);
    row_idxl = std::max(row_idxl, 0);
    row_idxh = std::min(row_idxh, db.num_sites_y);

    for (int row_id = row_idxl; row_id < row_idxh; ++row_id) {
      int row_yl = db.yl + row_id * db.row_height;
      int row_yh = row_yl + db.row_height;

      if (node_yl < row_yh && node_yh > row_yl)  // overlap with row
      {
        row2node_map[row_id].push_back(i);
      }
    }
  }

#pragma omp parallel for num_threads(num_threads) schedule(dynamic, 1)
  for (int i = 0; i < db.num_sites_y; ++i) {
    auto& row2nodes = row2node_map[i];
    // sort cells within rows according to left edges
    std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
      int x1 = vx[node_id1];
      int x2 = vx[node_id2];
      return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
    });
    // After sorting by left edge,
    // there is a special case for fixed cells where
    // one fixed cell is completely within another in a row.
    // This will cause failure to detect some overlaps.
    // We need to remove the "small" fixed cell that is inside another.
    if (!row2nodes.empty()) {
      for (int j = 1; j < row2nodes.size(); ++j) {
        int node_id1 = row2nodes.at(j - 1);
        int node_id2 = row2nodes.at(j);
        // two fixed cells
        if (node_id1 >= db.num_movable_nodes && node_id2 >= db.num_movable_nodes) {
          int xl1 = vx[node_id1];
          int xl2 = vx[node_id2];
          int width1 = db.node_size_x[node_id1];
          int width2 = db.node_size_x[node_id2];
          int xh1 = xl1 + width1;
          int xh2 = xl2 + width2;
          // only collect node_id2 if its right edge is righter than node_id1
          if (xh1 >= xh2 && !row2nodes.empty()) {
            row2nodes.erase(row2nodes.begin() + j);
            --j;
          }
        }
      }

      // sort according to center
      std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
        int x1 = vx[node_id1] + db.node_size_x[node_id1] / 2;
        int x2 = vx[node_id2] + db.node_size_x[node_id2] / 2;
        return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
      });
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
// std::vector<std::vector<int>> quick_perm(int N) {
//   std::vector<int> a(N), p(N, 0);
//   std::iota(a.begin(), a.end(), 0);
//   int total_num = 1;
//   for (int i = 1; i < N; ++i) {
//     total_num *= (i + 1);
//   }
//   std::vector<std::vector<int>> result;
//   result.reserve(total_num);
//   result.push_back(a);
  
//   int i = 1;
//   while (i < N) {
//     if (p[i] < i) {
//       std::swap(a[i % 2 * p[i]], a[i]);
//       result.push_back(a);
//       ++p[i];
//       i = 1;
//     } else {
//       p[i++] = 0;
//     }
//   }

//   return result;
// }

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
inline __device__ void compute_position(const GpuData& db,
                                        const KReorderState& state,
                                        const KReorderInstance& inst,
                                        int permute_id,
                                        int target_x[],
                                        int target_sizes[]) {
  auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
  auto permutation = state.permutations + permute_id * state.K;
  int K = inst.idx_end - inst.idx_bgn;
  // find left boundary
  if (K) {
    int node_id = row2nodes[0];
    target_x[0] = db.x[node_id];
  }
  // record sizes, and pack to left
  for (int i = 0; i < K; ++i) {
    int node_id = row2nodes[i];
    assert(node_id < db.num_movable_nodes);
    target_sizes[permutation[i]] = state.node_space_x[node_id];
  }
  for (int i = 1; i < K; ++i) {
    target_x[i] = target_x[i - 1] + target_sizes[i - 1];
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void compute_instance_net_boxes(GpuData db, KReorderState state, int group_id, int offset) {
  __shared__ int group_size;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
  }
  __syncthreads();

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size; i += blockDim.x * gridDim.x) {
    int inst_id = i;
    // this is a copy
    auto inst = state.reorder_instances(group_id, inst_id);
    inst.idx_bgn += offset;
    inst.idx_end = min(inst.idx_end + offset, state.row2node_map.size(inst.row_id));
    auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
    int K = inst.idx_end - inst.idx_bgn;

    // after adding offset
    for (int idx = 0; idx < K; ++idx) {
      int node_id = row2nodes[idx];
      if (node_id >= db.num_movable_nodes || db.node_size_y[node_id] > db.row_height) {
        inst.idx_end = inst.idx_bgn + idx;
        K = idx;
        break;
      }
    }

    if (K > 0) {
      int segment_xl = db.x[row2nodes[0]];
      int segment_xh = db.x[row2nodes[K - 1]];
      int row_yl = db.yl + inst.row_id * db.row_height;
      auto instance_nets = state.instance_nets + inst_id * MAX_NUM_NETS_PER_INSTANCE;
      auto instance_nets_size = state.instance_nets_size[inst_id];
      for (int idx = 0; idx < instance_nets_size; ++idx) {
        auto& instance_net = instance_nets[idx];
        instance_net.bxl = db.xh;
        instance_net.bxh = db.xl;

        int net2pin_id = db.flat_net2pin_start_map[instance_net.net_id];
        const int net2pin_id_end = db.flat_net2pin_start_map[instance_net.net_id + 1];
        for (; net2pin_id < net2pin_id_end; ++net2pin_id) {
          int net_pin_id = db.flat_net2pin_map[net2pin_id];
          int other_node_id = db.pin2node_map[net_pin_id];
          if (other_node_id < db.num_nodes)  // other_node_id may exceed
                                                // db.num_nodes like IO pins
          {
            int other_node_found = (state.node2inst_map[other_node_id] == inst_id);
            if (!other_node_found)  // not found
            {
              int other_node_xl = db.x[other_node_id];
              auto pin_offset_x = db.pin_offset_x[net_pin_id];
              if (::abs(db.y[other_node_id] - row_yl) < db.row_height)  // in the same row
              {
                if (other_node_xl < segment_xl)  // left of the segment
                {
                  other_node_xl = db.xl;
                } else if (other_node_xl > segment_xh)  // right of the segment
                {
                  other_node_xl = db.xh;
                }
              }
              other_node_xl += pin_offset_x;
              instance_net.bxl = min(instance_net.bxl, other_node_xl);
              instance_net.bxh = max(instance_net.bxh, other_node_xl);
            }
          }
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void compute_reorder_hpwl(GpuData db, KReorderState state, int group_id, int offset) {
  __shared__ int group_size;
  __shared__ int group_size_with_permutation;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
    group_size_with_permutation = group_size * state.num_permutations;
  }
  __syncthreads();

  int target_x[MAX_K];
  int target_sizes[MAX_K];
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size_with_permutation; i += blockDim.x * gridDim.x) {
    int inst_id = i / state.num_permutations;
    int permute_id = i - inst_id * state.num_permutations;
    // this is a copy
    auto inst = state.reorder_instances(group_id, inst_id);
    inst.idx_bgn += offset;
    inst.idx_end = min(inst.idx_end + offset, state.row2node_map.size(inst.row_id));
    auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
    auto permutation = state.permutations + permute_id * state.K;
    int K = inst.idx_end - inst.idx_bgn;

    // after adding offset
    for (int idx = 0; idx < K; ++idx) {
      int node_id = row2nodes[idx];
      if (node_id >= db.num_movable_nodes || db.node_size_y[node_id] > db.row_height) {
        inst.idx_end = inst.idx_bgn + idx;
        K = idx;
        break;
      }
    }

    int valid_flag = (K > 0);
    for (int idx = 0; idx < K; ++idx) {
      if (permutation[idx] >= K) {
        valid_flag = 0;
        break; 
      }
    }

    if (valid_flag) {
      compute_position(db, state, inst, permute_id, target_x, target_sizes);

      int cost = 0;
      // consider FENCE region
      if (db.num_regions) {
        for (int idx = 0; idx < K; ++idx) {
          int node_id = row2nodes[idx];
          int permuted_offset = permutation[idx];
          int node_xl = target_x[permuted_offset];
          int node_yl = db.y[node_id];
          if (!db.inside_fence(node_id, node_xl, node_yl)) {
            cost = cuda::numeric_limits<int>::max();
            break;
          }
        }
      }
      if (cost == 0) {
        auto instance_nets = state.instance_nets + inst_id * MAX_NUM_NETS_PER_INSTANCE;
        auto const& instance_nets_size = state.instance_nets_size[inst_id];
        for (int idx = 0; idx < instance_nets_size; ++idx) {
          auto& instance_net = instance_nets[idx];
          int bxl = instance_net.bxl;
          int bxh = instance_net.bxh;

          for (int j = 0; j < K; ++j) {
            int flag = (1 << j);
            if ((instance_net.node_marker & flag)) {
              int permuted_offset = permutation[j];
              int other_node_xl = target_x[permuted_offset] + target_sizes[permuted_offset] / 2;
              other_node_xl += instance_net.pin_offset_x[j];
              bxl = min(bxl, other_node_xl);
              bxh = max(bxh, other_node_xl);
            }
          }
          cost += bxh - bxl;
        }
      }
      state.costs[i] = cost;
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
template <int ThreadsPerBlock = 32>
__global__ void reduce_min_2d_cub(const int* __restrict__ costs, int* best_permute_id, int m, int n) {
  typedef cub::BlockReduce<ItemWithIndex, ThreadsPerBlock> BlockReduce;

  __shared__ typename BlockReduce::TempStorage temp_storage;

  auto inst_costs = costs + blockIdx.x * n;
  auto inst_best_permute_id = best_permute_id + blockIdx.x;

  ItemWithIndex thread_data;

  thread_data.value = cuda::numeric_limits<int>::max();
  thread_data.index = 0;
  for (int col = threadIdx.x; col < n; col += ThreadsPerBlock) {
    int cost = inst_costs[col];
    if (cost < thread_data.value) {
      thread_data.value = cost; 
      thread_data.index = col;
    }
  }

  __syncthreads();

  // Compute the block-wide max for thread0
  ItemWithIndex aggregate = BlockReduce(temp_storage).Reduce(thread_data, ReduceMinOP(), n);

  __syncthreads();

  if (threadIdx.x == 0) {
    *inst_best_permute_id = aggregate.index;
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void apply_reorder(GpuData db, KReorderState state, int group_id, int offset) {
  __shared__ int group_size;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
  }
  __syncthreads();

  int target_x[MAX_K];
  int target_sizes[MAX_K];
  int target_nodes[MAX_K];

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size; i += blockDim.x * gridDim.x) {
    int inst_id = i;
    int permute_id = state.best_permute_id[i];
    // this is a copy for adding offset
    auto inst = state.reorder_instances(group_id, inst_id);
    inst.idx_bgn += offset;
    inst.idx_end = min(inst.idx_end + offset, state.row2node_map.size(inst.row_id));
    auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
    auto permutation = state.permutations + permute_id * state.K;
    int K = inst.idx_end - inst.idx_bgn;

    // after adding offset
    for (int idx = 0; idx < K; ++idx) {
      int node_id = row2nodes[idx];
      if (node_id >= db.num_movable_nodes || db.node_size_y[node_id] > db.row_height) {
        inst.idx_end = inst.idx_bgn + idx;
        K = idx;
        break;
      }
    }

    if (K > 0) {
      compute_position(db, state, inst, permute_id, target_x, target_sizes);

      for (int i = 0; i < K; ++i) {
        int node_id = row2nodes[i];
        target_nodes[i] = node_id;
      }

      for (int i = 0; i < K; ++i) {
        int node_id = row2nodes[i];
        int xx = target_x[permutation[i]];
        if (db.x[node_id] != xx) {
          atomicAdd(state.device_num_moved, 1);
        }
        db.x[node_id] = xx;
      }

      for (int i = 0; i < K; ++i) {
        row2nodes[permutation[i]] = target_nodes[i];
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
// Every time, we solve one group with all independent instances in the group.
// For sliding window, offset can be different during iterations,
// so node2inst_map and node_markers need to be recomputed.
__global__ void compute_node2inst_map(GpuData db, KReorderState state, int group_id, int offset) {
  __shared__ int group_size;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
  }
  __syncthreads();

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size; i += blockDim.x * gridDim.x) {
    int inst_id = i;
    // this is a copy
    auto inst = state.reorder_instances(group_id, inst_id);
    inst.idx_bgn += offset;
    inst.idx_end = min(inst.idx_end + offset, state.row2node_map.size(inst.row_id));
    auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
    int K = inst.idx_end - inst.idx_bgn;

    for (int j = 0; j < K; ++j) {
      int node_id = row2nodes[j];
      // do not update for fixed cells
      if (node_id < db.num_movable_nodes) {
        state.node2inst_map[node_id] = inst_id;
        state.node_markers[node_id] = j;
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void compute_net_markers(GpuData db, KReorderState state) {
  for (int node_id = blockIdx.x * blockDim.x + threadIdx.x; node_id < db.num_movable_nodes;
        node_id += blockDim.x * gridDim.x) {
    if (state.node2inst_map[node_id] < cuda::numeric_limits<int>::max()) {
      int node2pin_id = db.flat_node2pin_start_map[node_id];
      const int node2pin_id_end = db.flat_node2pin_start_map[node_id + 1];
      for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
        int node_pin_id = db.flat_node2pin_map[node2pin_id];
        int net_id = db.pin2net_map[node_pin_id];
        int flag = db.net_mask[net_id];
        atomicOr(state.net_markers + net_id, flag);
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_net_markers(GpuData db, KReorderState state) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    for (int i = 0; i < db.num_nets; ++i) {
      printf("[INFO GPU-DPO] net_markers[%d] = %d\n", i, state.net_markers[i]);
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
// The net order is deterministic.
__global__ void compute_instance_nets(GpuData db, KReorderState state, int group_id, int offset) {
  __shared__ int group_size;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
  }
  __syncthreads();

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size; i += blockDim.x * gridDim.x) {
    int inst_id = i;
    // this is a copy
    auto inst = state.reorder_instances(group_id, inst_id);
    inst.idx_bgn += offset;
    inst.idx_end = min(inst.idx_end + offset, state.row2node_map.size(inst.row_id));
    const auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
    int K = inst.idx_end - inst.idx_bgn;
    auto& instance_nets_size = state.instance_nets_size[inst_id];
    auto instance_nets = state.instance_nets + inst_id * MAX_NUM_NETS_PER_INSTANCE;
    instance_nets_size = 0;

    // after adding offset
    for (int idx = 0; idx < K; ++idx) {
      int node_id = row2nodes[idx];
      if (node_id >= db.num_movable_nodes || db.node_size_y[node_id] > db.row_height) {
        inst.idx_end = inst.idx_bgn + idx;
        K = idx;
        break;
      }
    }

    for (int j = 0; j < K; ++j) {
      int node_id = row2nodes[j];
      int node2pin_id = db.flat_node2pin_start_map[node_id];
      int node2pin_id_end = db.flat_node2pin_start_map[node_id + 1];
      for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
        int node_pin_id = db.flat_node2pin_map[node2pin_id];
        int net_id = db.pin2net_map[node_pin_id];
        if (state.net_markers[net_id]) {
          if (instance_nets_size < MAX_NUM_NETS_PER_INSTANCE) {
            auto& instance_net = instance_nets[instance_nets_size];

            instance_net.net_id = net_id;
            instance_net.node_marker = (1 << state.node_markers[node_id]);
            instance_net.pin_offset_x[state.node_markers[node_id]] = db.pin_offset_x[node_pin_id];
            instance_nets_size += 1;
          }
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void unique_instance_nets(GpuData db, KReorderState state, int group_id) {
  __shared__ int group_size;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
  }
  __syncthreads();

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size; i += blockDim.x * gridDim.x) {
    int inst_id = i;
    auto inst = state.reorder_instances(group_id, inst_id);
    auto instance_nets = state.instance_nets + inst_id * MAX_NUM_NETS_PER_INSTANCE;
    auto& instance_nets_size = state.instance_nets_size[inst_id];

    for (int j = 0; j < instance_nets_size; ++j) {
      for (int k = j + 1; k < instance_nets_size;) {
        if (instance_nets[j].net_id == instance_nets[k].net_id) {
          // copy marker and pin offset
          instance_nets[j].node_marker |= instance_nets[k].node_marker;
          for (int l = 0; l < state.K; ++l) {
            if ((instance_nets[k].node_marker & (1 << l))) {
              instance_nets[j].pin_offset_x[l] = instance_nets[k].pin_offset_x[l];
            }
          }
          --instance_nets_size;
          device_swap(instance_nets[k], instance_nets[instance_nets_size]);
        } else {
          ++k;
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_costs(KReorderState state, int group_id, int offset) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    printf("[INFO GPU-DPO] group_id %d, offset %d, %s\n", group_id, offset, __func__);
    for (int i = 0; i < state.reorder_instances.size(group_id); ++i) {
      printf("[INFO GPU-DPO] inst[%d][%d] costs: ", i, state.num_permutations);
      for (int j = 0; j < state.num_permutations; ++j) {
        printf("%d ", state.costs[i * state.num_permutations + j]);
      }
      printf("\n");
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_best_permute_id(KReorderState state, int group_id, int offset) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    printf("[INFO GPU-DPO] group_id %d, offset %d, %s\n", group_id, offset, __func__);
    for (int i = 0; i < state.reorder_instances.size(group_id); ++i) {
      printf("[INFO GPU-DPO] [%d] = %d\n", i, state.best_permute_id[i]);
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_instance_nets(KReorderState state, int group_id, int offset) {
  assert(blockDim.x == 1 && gridDim.x == 1);
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    printf("[INFO GPU-DPO] group_id %d, offset %d, %s\n", group_id, offset, __func__);
    int size = state.reorder_instances.size(group_id);
    assert(size >= 0 && size < state.reorder_instances.size2);
    for (int i = 0; i < size; ++i) {
      int instance_nets_size = state.instance_nets_size[i];
      printf("[INFO GPU-DPO] inst[%d][%d] nets: ", i, instance_nets_size);
      assert(instance_nets_size >= 0 && instance_nets_size < MAX_NUM_NETS_PER_INSTANCE);
      for (int j = 0; j < instance_nets_size; ++j) {
        int index = i * MAX_NUM_NETS_PER_INSTANCE + j;
        assert(index >= 0 && index < state.reorder_instances.size2 * MAX_NUM_NETS_PER_INSTANCE);
        printf("%d (%d) ", state.instance_nets[index].net_id, state.instance_nets[index].node_marker);
      }
      printf("\n");
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_instance_net_bboxes(KReorderState state, int group_id, int offset) {
  assert(blockDim.x == 1 && gridDim.x == 1);
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    printf("[INFO GPU-DPO] group_id %d, offset %d, %s\n", group_id, offset, __func__);
    int size = state.reorder_instances.size(group_id);
    assert(size >= 0 && size < state.reorder_instances.size2);
    for (int i = 0; i < size; ++i) {
      int instance_nets_size = state.instance_nets_size[i];
      printf("[INFO GPU-DPO] inst[%d][%d] nets: ", i, instance_nets_size);
      assert(instance_nets_size >= 0 && instance_nets_size < MAX_NUM_NETS_PER_INSTANCE);
      for (int j = 0; j < instance_nets_size; ++j) {
        int index = i * MAX_NUM_NETS_PER_INSTANCE + j;
        assert(index >= 0 && index < state.reorder_instances.size2 * MAX_NUM_NETS_PER_INSTANCE);
        printf("%d/%d:%d/%d ", index, j, state.instance_nets[index].bxl, state.instance_nets[index].bxh);
      }
      printf("\n");
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void check_instance_nets(GpuData db, KReorderState state, int group_id) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    for (int i = 0; i < state.reorder_instances.size(group_id); ++i) {
      auto const& inst = state.reorder_instances(group_id, i);
      auto row2nodes = state.row2node_map(inst.row_id) + inst.idx_bgn;
      int K = inst.idx_end - inst.idx_bgn;
      for (int j = 0; j < K; ++j) {
        int node_id = row2nodes[j];
        int node2pin_id = db.flat_node2pin_start_map[node_id];
        const int node2pin_id_end = db.flat_node2pin_start_map[node_id + 1];
        for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
          int node_pin_id = db.flat_node2pin_map[node2pin_id];
          int net_id = db.pin2net_map[node_pin_id];

          if (db.net_mask[net_id]) {
            bool found = false;
            for (int k = 0; k < state.instance_nets_size[i]; ++k) {
              auto const& instance_net = state.instance_nets[i * MAX_NUM_NETS_PER_INSTANCE + k];
              if (instance_net.net_id == net_id) {
                found = true;
                assert((instance_net.node_marker & (1 << j)));
                assert(instance_net.pin_offset_x[j] == db.pin_offset_x[node_pin_id]);
                break;
              }
            }
          }
        }
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void print_pos(GpuData db, int group_id, int offset) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    printf("[INFO GPU-DPO] group_id %d, offset %d, pos[%d]\n", group_id, offset, db.num_movable_nodes);
    for (int i = 0; i < db.num_movable_nodes; ++i) {
      printf("[INFO GPU-DPO] [%d] = %d, %d\n", i, db.x[i], db.y[i]);
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void reset_state(GpuData db, KReorderState state, int group_id) {
    __shared__ int group_size;
    __shared__ int group_size_with_permutation;
  if (threadIdx.x == 0) {
    group_size = state.reorder_instances.size(group_id);
    group_size_with_permutation = group_size * state.num_permutations;
  }
  __syncthreads();

  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < group_size_with_permutation; i += blockDim.x * gridDim.x) {
    state.costs[i] = cuda::numeric_limits<int>::max();
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < state.reorder_instances.size2;
        i += blockDim.x * gridDim.x) {
    state.instance_nets_size[i] = 0;
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_nodes; i += blockDim.x * gridDim.x) {
    state.node_markers[i] = 0;
    state.node2inst_map[i] = cuda::numeric_limits<int>::max();
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_nets; i += blockDim.x * gridDim.x) {
    state.net_markers[i] = 0;
  }
  int instance_nets_size = state.reorder_instances.size2 * MAX_NUM_NETS_PER_INSTANCE;
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < instance_nets_size; i += blockDim.x * gridDim.x) {
    auto& instance_net = state.instance_nets[i];
    instance_net.net_id = cuda::numeric_limits<int>::max();
    instance_net.node_marker = 0;
    instance_net.bxl = db.xh;
    instance_net.bxh = db.xl;
    for (int j = 0; j < MAX_K; ++j) {
      instance_net.pin_offset_x[j] = 0;
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void k_reorder(GpuData& db,
               KReorderState& state,
               const std::vector<std::vector<KReorderInstance>>& host_reorder_instances) {
  for (int group_id = 0; group_id < state.reorder_instances.size1; ++group_id) {
    assert(state.reorder_instances.size1 == host_reorder_instances.size());
    int group_size = host_reorder_instances[group_id].size();
    if (group_size) {
      for (int offset = 0; offset < state.K; offset += 1) {
        reset_state<<<64, 512>>>(db, state, group_id);
        compute_node2inst_map<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id, offset);
        compute_net_markers<<<ceilDiv(db.num_movable_nodes, 256), 256>>>(db, state);
        // print_net_markers<<<1, 1>>>(db, state);
        compute_instance_nets<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id, offset);
        // print_instance_nets<<<1, 1>>>(state, group_id);
        unique_instance_nets<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id);
        // print_instance_nets<<<1, 1>>>(state, group_id, offset);
        // check_instance_nets<<<1, 1>>>(db, state, group_id);
        compute_instance_net_boxes<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id, offset);
        // print_instance_net_bboxes<<<1, 1>>>(state, group_id, offset);
        compute_reorder_hpwl<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id, offset);

        // print_costs<<<1, 1>>>(state, group_id, offset);
        reduce_min_2d_cub<32><<<group_size, 32>>>(state.costs, state.best_permute_id, group_size, state.num_permutations);
        // print_best_permute_id<<<1, 1>>>(state, group_id, offset);
        apply_reorder<<<ceilDiv(group_size, 256), 256>>>(db, state, group_id, offset);
        // print_pos<<<1, 1>>>(db, group_id, offset);
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void apply_best_reorder(GpuData db, ReorderState state, int group_id) {
  // Attempts to apply the best permutation
  // as long as the legality checks are met
  int inst_offset = state.group_offsets[group_id];
  int inst_count = state.group_counts[group_id];
  int inst_id = blockIdx.x * blockDim.x + threadIdx.x;

  if (inst_id >= inst_count) return;

  int global_inst_id = inst_offset + inst_id;
  ReorderInstance inst = state.instances[global_inst_id];
  int perm_id = state.best_permute_id[global_inst_id];

  // Read permutation
  int perm[MAX_K];
  for (int i = 0; i < inst.num_cells; ++i) {
    perm[i] = state.permutations[perm_id * MAX_K + i];
  }

  // Apply permutation
  int x_cursor = db.x[inst.node_ids[0]];  // Start from leftmost node's x
  for (int i = 0; i < inst.num_cells; ++i) {
    int node_id = inst.node_ids[perm[i]];

    // Align to site
    int site_width = db.site_width;
    int aligned_x = ((x_cursor + site_width - 1) / site_width) * site_width;
    x_cursor = aligned_x;

    // Check displacement constraint
    int orig_x = db.init_x[node_id];
    int max_disp = db.max_displacement_x;
    if (::abs(aligned_x - orig_x) > max_disp) return;

    // Check fence region constraint
    if (db.num_regions) {
      int y = db.y[node_id];
      if (!db.inside_fence(node_id, aligned_x, y)) return;
    }
    db.x[node_id] = aligned_x;
    x_cursor += db.node_size_x[node_id];
  }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
__global__ void compute_reorder_costs(GpuData db, ReorderState state, int group_id) {
  int total_perms = state.num_permutations;
  int inst_offset = state.group_offsets[group_id];
  int inst_count = state.group_counts[group_id];

  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  int global_perm_id = tid % total_perms;
  int local_inst_id = tid / total_perms;

  if (local_inst_id >= inst_count) return;

  int inst_id = inst_offset + local_inst_id;
  ReorderInstance inst = state.instances[inst_id];

  int node_ids[MAX_K];
  for (int i = 0; i < inst.num_cells; ++i) {
    node_ids[i] = inst.node_ids[i];
  }

  int perm[MAX_K];
  for (int i = 0; i < inst.num_cells; ++i) {
    perm[i] = state.permutations[global_perm_id * MAX_K + i];
  }

  // Step 1: collect all nets touched by the window
  const int max_nets = 256;
  int net_ids[max_nets];
  int net_count = 0;

  for (int i = 0; i < inst.num_cells; ++i) {
    int node_id = node_ids[perm[i]];
    for (int j = db.flat_node2pin_start_map[node_id]; j < db.flat_node2pin_start_map[node_id + 1]; ++j) {
      int pin_id = db.flat_node2pin_map[j];
      int net_id = db.pin2net_map[pin_id];
      if (db.net_mask[net_id] == 0) continue;

      bool found = false;
      for (int k = 0; k < net_count; ++k) {
        if (net_ids[k] == net_id) {
          found = true;
          break;
        }
      }
      if (!found && net_count < max_nets) {
        net_ids[net_count++] = net_id;
      }
    }
  }

  // Step 2: compute HPWL for each collected net
  int cost = 0;
  for (int i = 0; i < net_count; ++i) {
    int net_id = net_ids[i];
    int net_bxl = INT_MAX, net_bxh = INT_MIN;
    for (int k = db.flat_net2pin_start_map[net_id]; k < db.flat_net2pin_start_map[net_id + 1]; ++k) {
      int pin_id = db.flat_net2pin_map[k];
      int node_id = db.pin2node_map[pin_id];
      int px = (db.x[node_id] + db.node_size_x[node_id]) / 2 + db.pin_offset_x[pin_id];
      net_bxl = min(net_bxl, px);
      net_bxh = max(net_bxh, px);
    }
    cost += (net_bxh - net_bxl);
  }

  state.costs[inst_id * total_perms + global_perm_id] = cost;
}

__global__ void reduce_min_costs_cub(ReorderState state, int group_id) {
  typedef cub::BlockReduce<ItemWithIndex, 256> BlockReduce;
  __shared__ typename BlockReduce::TempStorage temp_storage;

  int total_perms = state.num_permutations;
  int inst_offset = state.group_offsets[group_id];
  int inst_count = state.group_counts[group_id];
  int inst_id = blockIdx.x;
  if (inst_id >= inst_count) return;
  int global_inst_id = inst_offset + inst_id;

  auto inst_costs = state.costs + global_inst_id * total_perms;
  auto inst_best_permute_id = state.best_permute_id + global_inst_id;

  ItemWithIndex thread_data = {INT_MAX, 0};
  for (int i = threadIdx.x; i < total_perms; i += blockDim.x) {
    int cost = inst_costs[i];
    if (cost < thread_data.value) {
      thread_data.value = cost;
      thread_data.index = i;
    }
  }

  __syncthreads();

  ItemWithIndex aggregate = BlockReduce(temp_storage).Reduce(thread_data, ReduceMinOP());
  
  __syncthreads();

  if (threadIdx.x == 0) *inst_best_permute_id = aggregate.index;
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
bool does_window_fit(const std::vector<Node*>& nodes,
                     int istrt, int istop,
                     int leftLimit, int rightLimit,
                     Architecture* arch) {
  const int size = istop - istrt + 1;
  if (size <= 0) {
    return false;
  }

  std::vector<int> left(size, 0);
  std::vector<int> right(size, 0);
  std::vector<int> width(size, 0);

  int totalPadding = 0;
  int totalWidth = 0;

  for (int i = 0; i < size; i++) {
    const Node* ndi = nodes[istrt + i];
    arch->getCellPadding(ndi, left[i], right[i]);
    width[i] = ndi->getWidth().v;
    totalPadding += left[i] + right[i];
    totalWidth += width[i];
  }

  const int availableSpace = rightLimit - leftLimit;
  if (availableSpace < totalWidth + totalPadding) {
    return false;   // not enough space for default spacing
  }

  // Try to spread remaining space evenly as extra padding
  const int excessSpace = availableSpace - (totalWidth + totalPadding);
  const int siteWidth = arch->getRow(0)->getSiteWidth().v;
  const int sitePerCellTotal = excessSpace / siteWidth / size;
  const int sitePerCellRight = sitePerCellTotal / 2;
  const int sitePerCellLeft = sitePerCellTotal - sitePerCellRight;

  int adjustedPadding = totalPadding + (sitePerCellRight + sitePerCellLeft) * siteWidth * size;
  if (totalWidth + adjustedPadding > availableSpace) {
    return false;  // even with spreading, we don't fit
  }

  return true; 
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
std::vector<std::vector<int>> quick_perm(int n) {
  std::vector<int> a(n), p(n, 0);
  std::iota(a.begin(), a.end(), 0);
  std::vector<std::vector<int>> result;
  result.push_back(a);  // first permutation is identity

  int i = 1;
  while (i < n) {
    if (p[i] < i) {
      int j = (i % 2 == 1) ? p[i] : 0;
      std::swap(a[i], a[j]);
      result.push_back(a);
      ++p[i];
      i = 1;
    } else {
      p[i] = 0;
      ++i;
    }
  }
  return result;
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void reorder(GpuData& db, ReorderState state) {
  for (int group_id = 0; group_id < state.num_groups; ++group_id) {

    int group_size = state.h_group_counts[group_id];
    if (group_size == 0) continue;

    int total_threads = group_size * state.num_permutations;
    int cost_blocks = (total_threads + 255) / 256;
    int reduce_blocks = group_size;
    int apply_blocks = (group_size + 255) / 256;

    compute_reorder_costs<<<cost_blocks, 256>>>(db, state, group_id);
    reduce_min_costs_cub<<<reduce_blocks, 256>>>(state, group_id);
    apply_best_reorder<<<apply_blocks, 256>>>(db, state, group_id);
  }
}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void compute_instances(GpuData& db,
                       Architecture* arch,
                       DetailedMgr* mgrPtr,
                       Network* network,
                       int windowSize,
                       ReorderState& state,
                       std::vector<std::vector<int>> segment_groups) {
  std::vector<ReorderInstance> all_instances;
  std::vector<int> group_offsets;
  std::vector<int> group_counts;

  int offset = 0;
  for (const auto& group : segment_groups) {
    int count_before = all_instances.size();
    for (int seg_id : group) {
      DetailedSeg* seg = mgrPtr->getSegment(seg_id);
      int row_id = seg->getRowId();
      const auto& nodes = mgrPtr->getCellsInSeg(seg_id);
      if ((int)nodes.size() < 2) {
        continue;
      }
      
      int j = 0;
      while (j < (int)nodes.size()) {
        while (j < (int)nodes.size() && arch->isMultiHeightCell(nodes[j])) {
          j++;
        }
        int jstrt = j;
        while (j < (int)nodes.size() && arch->isSingleHeightCell(nodes[j])) {
          j++;
        }
        int jstop = j - 1;

        for (int i = jstrt; i + windowSize <= jstop + 1; i += windowSize) {
          int istrt = i;
          int istop = std::min(jstop, istrt + windowSize - 1);
          if (istop == jstop) {
            istrt = std::max(jstrt, istop - windowSize + 1);
          }
          const Node* next = (istop != (int)nodes.size() - 1) ? nodes[istop + 1] : nullptr;
          const Node* prev = (istrt != 0) ? nodes[istrt - 1] : nullptr;

          int rightLimit = seg->getMaxX().v;
          if (next) {
            int lp, rp;
            arch->getCellPadding(next, lp, rp);
            rightLimit = std::min(rightLimit, next->getLeft().v - lp);
          }
          int leftLimit = seg->getMinX().v;
          if (prev) {
            int lp, rp;
            arch->getCellPadding(prev, lp, rp);
            leftLimit = std::max(leftLimit, prev->getRight().v + rp);
          }

          if (does_window_fit(nodes, istrt, istop, leftLimit, rightLimit, arch)) {
            std::vector<int> node_ids;
            for (int k = 0; k < (istop - istrt + 1); ++k) {
              int nid = nodes[istrt + k]->getId();
              node_ids.push_back(nid);
            }

            ReorderInstance inst;
            inst.num_cells = istop - istrt + 1;
            inst.seg_id = seg_id;
            inst.row_id = row_id;
            inst.jstrt = jstrt;
            inst.jstop = jstop;
            inst.left_limit = leftLimit;
            inst.right_limit = rightLimit;
            for (int k = 0; k < inst.num_cells; k++) {
              inst.node_ids[k] = node_ids[k];
            }
            all_instances.push_back(inst);
          }
        }
      }
      int count_after = all_instances.size();
      group_offsets.push_back(offset);
      group_counts.push_back(count_after - count_before);
      offset = count_after;
    }
  }
  
  if (all_instances.empty()) return;

  std::vector<std::vector<int>> permutations = quick_perm(windowSize);

  const int num_instances = all_instances.size();
  const int num_perms = permutations.size();

  std::vector<int> flat_perms(num_perms * MAX_K, -1);
  for (int i = 0; i < num_perms; i++) {
    for (int j = 0; j < windowSize; j++) {
      flat_perms[i * MAX_K + j] = permutations[i][j];
    }
  }

  allocateCopyCuda(state.instances, all_instances.data(), num_instances);
  allocateCopyCuda(state.permutations, flat_perms.data(), num_perms * MAX_K);
  allocateCopyCuda(state.group_offsets, group_offsets.data(), group_offsets.size());
  allocateCopyCuda(state.group_counts, group_counts.data(), group_counts.size());

  state.num_groups = group_counts.size();
  state.num_instances = num_instances;
  state.num_permutations = num_perms;
  state.K = windowSize;
  state.allocate(num_instances, num_perms);

  state.h_group_counts = group_counts.data();
  state.h_group_offsets = group_offsets.data();
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
std::vector<std::vector<int>> group_independent_segments(DetailedMgr* mgrPtr,
                                                         int num_threads = 1) {
  // Here we group the independent segments instead of independent rows 
  // We only want to consider placeable regions so we don't need the entire row
  // Segments in the same group do not share any nets
  int num_segments = mgrPtr->getNumSegments();
  std::vector<std::vector<int>> seg_graph(num_segments);
  std::vector<std::set<int>> seg2nets(num_segments);

#pragma omp parallel for num_threads(num_threads)
  for (int s = 0; s < num_segments; ++s) {
    DetailedSeg* seg = mgrPtr->getSegment(s);
    const std::vector<Node*>& nodes = mgrPtr->getCellsInSeg(s);
    for (Node* node : nodes) {
      for (int p = 0; p < node->getNumPins(); ++p) {
        const Pin* pin = node->getPins()[p];
        const Edge* edge = pin->getEdge();
        if (edge) {
          seg2nets[s].insert(edge->getId());
        }
      }
    }
  }

  std::vector<std::vector<unsigned char>> adjacency_matrix(num_segments, std::vector<unsigned char>(num_segments, 0));
#pragma omp parallel for num_threads(num_threads)
  for (int i = 0; i < num_segments; ++i) {
    for (int j = i + 1; j < num_segments; ++j) {
      for (int net : seg2nets[j]) {
        if (seg2nets[i].count(net)) {
          adjacency_matrix[i][j] = adjacency_matrix[j][i] = 1;
          break;
        }
      }
    }
  }

#pragma omp parallel for num_threads(num_threads)
  for (int i = 0; i < num_segments; ++i) {
    for (int j = 0; j < num_segments; ++j) {
      if (i != j && adjacency_matrix[i][j]) {
#pragma omp critical
        seg_graph[i].push_back(j);
      }
    }
  }

  std::vector<std::vector<int>> groups;
  std::vector<unsigned char> dependent(num_segments, 0);
  std::vector<unsigned char> selected(num_segments, 0);
  int num_selected = 0;

  while (num_selected < num_segments) {
    std::vector<int> group;
    std::vector<unsigned char> this_iter_selected(num_segments, 0);
    for (int i = 0; i < num_segments; ++i) {
      if (!dependent[i] && !selected[i]) {
        group.push_back(i);
        this_iter_selected[i] = 1;
        selected[i] = 1;
        num_selected++;
        for (int nbr : seg_graph[i]) {
          dependent[nbr] = 1;
        }
      }
    }
    std::fill(dependent.begin(), dependent.end(), 0);
    groups.push_back(group);
  }

  printf("[INFO GPU-DPO] Found %d independent segment groups across %d segments.\n", (int)groups.size(), num_segments);

  // Verify independence of all groups
  for (size_t g = 0; g < groups.size(); ++g) {
    const auto& group = groups[g];
    std::set<int> nets_in_group;
    for (int seg_id : group) {
      for (int net : seg2nets[seg_id]) {
        if (nets_in_group.count(net)) {
          printf("[ERROR GPU-DPO] Group %d has net overlap on net %d.\n", (int)g, (int)net);
        }
        nets_in_group.insert(net);
      }
    }
  }

  return groups;
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::run(DetailedMgr* mgrPtr, GpuData& db_,
                            const std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgrPtr_ = mgrPtr;
  windowSize_ = 3;

  int passes = 1;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-w" && i + 1 < args.size()) {
      windowSize_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    } else if (args[i] == "-binX" && i + 1 < args.size()) {
      numBinsX_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "-binY" && i + 1 < args.size()) {
      numBinsY_ = std::atoi(args[++i].c_str());
    }
  }
  windowSize_ = std::min(4, std::max(2, windowSize_));
  tol = std::max(tol, 0.01);

  db_.set_num_bins(numBinsX_, numBinsY_); // may not need this for reordering
  // KReorderState state;
  // GpuData cpu_db;
  // state.K = windowSize_;

  // // distribute cells to rows on host
  // // copy cell locations from device to host
  // std::vector<std::vector<int>> host_row2node_map(db_.num_sites_y);
  // std::vector<int> host_node_space_x(db_.num_movable_nodes);
  // std::vector<std::vector<int>> host_permutations = quick_perm(windowSize_);
  // std::vector<unsigned char> host_adjacency_matrix;
  // std::vector<std::vector<int>> host_row_graph;
  // std::vector<std::vector<int>> host_independent_rows;
  // std::vector<std::vector<KReorderInstance>> host_reorder_instances;
  // printf("[INFO GPU-DPO] %d permutations\n", host_permutations.size());

  // // initialize cpu db from db
  // {
  //   cpu_db.xl = db_.xl;
  //   cpu_db.yl = db_.yl;
  //   cpu_db.xh = db_.xh;
  //   cpu_db.yh = db_.yh;
  //   cpu_db.site_width = db_.site_width;
  //   cpu_db.row_height = db_.row_height;
  //   cpu_db.bin_size_x = db_.bin_size_x;
  //   cpu_db.bin_size_y = db_.bin_size_y;
  //   cpu_db.num_bins_x = db_.num_bins_x;
  //   cpu_db.num_bins_y = db_.num_bins_y;
  //   cpu_db.num_sites_x = db_.num_sites_x;
  //   cpu_db.num_sites_y = db_.num_sites_y;
  //   cpu_db.num_nodes = db_.num_nodes;
  //   cpu_db.num_movable_nodes = db_.num_movable_nodes;
  //   cpu_db.num_nets = db_.num_nets;
  //   cpu_db.num_pins = db_.num_pins;

  //   allocateCopyCpu(cpu_db.net_mask, db_.net_mask, db_.num_nets, int);
  //   allocateCopyCpu(cpu_db.flat_net2pin_start_map, db_.flat_net2pin_start_map, db_.num_nets + 1, int);
  //   allocateCopyCpu(cpu_db.flat_net2pin_map, db_.flat_net2pin_map, db_.num_pins, int);
  //   allocateCopyCpu(cpu_db.pin2node_map, db_.pin2node_map, db_.num_pins, int);
  //   allocateCopyCpu(cpu_db.x, db_.x, db_.num_nodes, int);
  //   allocateCopyCpu(cpu_db.y, db_.y, db_.num_nodes, int);
  //   allocateCopyCpu(cpu_db.node_size_x, db_.node_size_x, db_.num_nodes, int);
  //   allocateCopyCpu(cpu_db.node_size_y, db_.node_size_y, db_.num_nodes, int);

  //   make_row2node_map(cpu_db, cpu_db.x, cpu_db.y, host_row2node_map, db_.num_threads);
  //   std::vector<std::vector<int>> host_row2node_map_left = db_.reorder_row_map(cpu_db.x, cpu_db.y, cpu_db.node_size_x, cpu_db.node_size_y, host_row2node_map, 1);
  //   host_node_space_x.resize(cpu_db.num_movable_nodes);
  //   for (int i = 0; i < cpu_db.num_sites_y; ++i) {
  //     for (unsigned int j = 0; j < host_row2node_map_left.at(i).size(); ++j) {
  //       int node_id = host_row2node_map_left[i][j];
  //       if (node_id < db_.num_movable_nodes) {
  //         auto& space = host_node_space_x[node_id];
  //         int space_xl = cpu_db.x[node_id];
  //         int space_xh = cpu_db.xh;
  //         if (j + 1 < host_row2node_map_left[i].size()) {
  //           int right_node_id = host_row2node_map_left[i][j + 1];
  //           space_xh = min(space_xh, cpu_db.x[right_node_id]);
  //         }
  //         space = space_xh - space_xl;
  //         // align space to sites, as I assume space_xl aligns to sites
  //         // I also assume node width should be integral numbers of sites
  //         space = floorDiv(space, db_.site_width) * db_.site_width;
  //         int node_size_x = cpu_db.node_size_x[node_id];
  //         if (!(space >= node_size_x)) {
  //           printf("[INFO GPU-DPO] Assertion failed: space >= node_size_x — space %d, node_size_x[%d] %d, original space (%d, %d), site_width %d\n", space, node_id, node_size_x, space_xl, space_xh, db_.site_width);
  //         }
  //       }
  //     }
  //   }
  //   compute_row_conflict_graph(cpu_db, host_row2node_map, host_adjacency_matrix, host_row_graph, db_.num_threads);
  //   compute_independent_rows(cpu_db, host_row_graph, host_independent_rows);
  //   compute_reorder_instances(cpu_db, host_row2node_map, host_independent_rows, host_reorder_instances, state.K);
  // }
  // // initialize cuda state
  // {
  //   allocateCopyCuda(state.node_space_x, host_node_space_x.data(), db_.num_movable_nodes);

  //   std::vector<int> host_permutations_flat(host_permutations.size() * windowSize_);
  //   for (unsigned int i = 0; i < host_permutations.size(); ++i) {
  //     std::copy(host_permutations[i].begin(), host_permutations[i].end(), host_permutations_flat.begin() + i * windowSize_);
  //   }
  //   state.num_permutations = host_permutations.size();
  //   allocateCopyCuda(state.permutations, host_permutations_flat.data(), state.num_permutations * state.K);

  //   state.row2node_map.initialize(host_row2node_map);
  //   state.reorder_instances.initialize(host_reorder_instances);

  //   allocateCuda(state.costs, state.reorder_instances.size2 * state.num_permutations, int);
  //   allocateCuda(state.best_permute_id, state.reorder_instances.size2, int);
  //   allocateCuda(state.instance_nets, state.reorder_instances.size2 * MAX_NUM_NETS_PER_INSTANCE, InstanceNet);
  //   allocateCuda(state.instance_nets_size, state.reorder_instances.size2, int);
  //   allocateCuda(state.node2inst_map, db_.num_nodes, int);
  //   allocateCuda(state.net_markers, db_.num_nets, int);
  //   allocateCuda(state.node_markers, db_.num_nodes, unsigned char);
  //   allocateCuda(state.device_num_moved, 1, int);
  //   allocateCuda(state.net_hpwls, db_.num_nets, int);
  // }

  ReorderState state;

  allocateCuda(state.net_hpwls, db_.num_nets, int);

  int64_t curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);
  const int64_t init_hpwl = curr_hpwl;
  if (init_hpwl == 0) return;

  // Extract independent row groups once
  auto segment_groups = group_independent_segments(mgrPtr_, db_.num_threads);
  compute_instances(db_, arch_, mgrPtr_, network_, windowSize_, state, segment_groups);

  for (int p = 1; p <= passes; p++) {
    const int64_t last_hpwl = curr_hpwl;
    reorder(db_, state);
    //k_reorder(db_, state, host_reorder_instances);
    checkCuda(cudaDeviceSynchronize());

    curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);

    printf("[INFO GPU-DPO] Pass %d of reordering; objective is %d.\n", p, (int) curr_hpwl);

    if (std::abs(curr_hpwl - last_hpwl) / (double) last_hpwl <= tol) {
      break;
    }
  }

  const double curr_imp
      = (((init_hpwl - curr_hpwl) / (double) init_hpwl) * 100.);
  printf("[INFO GPU-DPO] End of reordering; objective is %d, improvement is %f percent.\n",
          (int) curr_hpwl,
          curr_imp);

  checkCuda(cudaDeviceSynchronize());

  state.destroy();

  // // destroy cuda state
  // {
  //   cudaFree(state.node_space_x);
  //   cudaFree(state.permutations);
  //   state.row2node_map.destroy();
  //   state.reorder_instances.destroy();
  //   cudaFree(state.costs);
  //   cudaFree(state.best_permute_id);
  //   cudaFree(state.instance_nets);
  //   cudaFree(state.instance_nets_size);
  //   cudaFree(state.node2inst_map);
  //   cudaFree(state.net_markers);
  //   cudaFree(state.node_markers);
  //   cudaFree(state.device_num_moved);
  //   cudaFree(state.net_hpwls);
  // }

  // // destroy cpu db
  // {
  //   free((void*)cpu_db.net_mask);
  //   free((void*)cpu_db.flat_net2pin_start_map);
  //   free((void*)cpu_db.flat_net2pin_map);
  //   free((void*)cpu_db.pin2node_map);
  //   free((void*)cpu_db.x);
  //   free((void*)cpu_db.y);
  //   free((void*)cpu_db.node_size_x);
  //   free((void*)cpu_db.node_size_y);
  // }
}

}  // namespace dpl
