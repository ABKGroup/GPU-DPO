#pragma once

#include "infrastructure/GpuData.cuh"
#include "diamond_search.h"
#include "optimization/detailed_mis.cuh"

namespace dpl {

struct CpuData {
  int num_movable_nodes;
  int num_bins_x;
  int num_bins_y;
  float bin_size_x;
  float bin_size_y;
  int xl, yl, xh, yh;
  std::vector<int> node_size_x;
  std::vector<int> node_size_y;
  std::vector<int> x;
  std::vector<int> y;
};

struct IndependentSetMatchingCPUState {
  int batch_size;
  int set_size;
  int grid_size;
  int max_diamond_search_sequence;
  int num_independent_sets;
  std::vector<std::vector<int>> independent_sets;
  std::vector<int> flat_independent_sets;  ///< flat version of storage
  std::vector<int> independent_set_sizes;  ///< size of each set
  std::vector<int> selected_nodes;
  std::vector<unsigned char> selected_markers;
  std::vector<int> ordered_nodes;
  std::vector<BinMapIndex> node2bin_map;
  std::vector<std::vector<int>>
      bin2node_map;  ///< the first dimension is size, all the cells are categorized by width
  std::vector<GridIndex<int>> search_grids;
};

inline int ceil_power2(int v) { return (1 << (int)ceil(log2((float)v))); }

void init_cpu_db(const GpuData& db, CpuData& host_db) {
  host_db.num_movable_nodes = db.num_movable_nodes;
  host_db.num_bins_x = db.num_bins_x;
  host_db.num_bins_y = db.num_bins_y;
  host_db.bin_size_x = db.bin_size_x;
  host_db.bin_size_y = db.bin_size_y;
  host_db.xl = db.xl;
  host_db.yl = db.yl;
  host_db.xh = db.xh;
  host_db.yh = db.yh;
  host_db.node_size_x.resize(db.num_nodes);
  checkCuda(cudaMemcpy(host_db.node_size_x.data(),
                        db.node_size_x,
                        sizeof(int) * db.num_nodes,
                        cudaMemcpyDeviceToHost));
  host_db.node_size_y.resize(db.num_nodes);
  checkCuda(cudaMemcpy(host_db.node_size_y.data(),
                        db.node_size_y,
                        sizeof(int) * db.num_nodes,
                        cudaMemcpyDeviceToHost));
  host_db.x.resize(db.num_nodes);
  host_db.y.resize(db.num_nodes);
}

void init_cpu_state(const GpuData& db,
                    const IndependentSetMatchingState& state,
                    IndependentSetMatchingCPUState& host_state) {
  host_state.batch_size = state.batch_size;
  host_state.set_size = state.set_size;
  host_state.grid_size = ceil_power2(std::max(db.num_bins_x, db.num_bins_y) / 8);
  host_state.max_diamond_search_sequence = host_state.grid_size * host_state.grid_size / 2;
  printf("[INFO GPU-DPO] diamond search grid size %d, sequence length %d\n",
              host_state.grid_size,
              host_state.max_diamond_search_sequence);
  host_state.selected_nodes.reserve(db.num_movable_nodes);
  host_state.selected_markers.assign(db.num_movable_nodes, 1);
  host_state.ordered_nodes.resize(db.num_movable_nodes);
  host_state.search_grids = diamond_search_sequence(host_state.grid_size, host_state.grid_size);
  host_state.independent_sets.resize(state.batch_size, std::vector<int>(state.set_size));
  host_state.flat_independent_sets.resize(state.batch_size * state.set_size);
  host_state.independent_set_sizes.resize(state.batch_size);
  host_state.node2bin_map.resize(db.num_movable_nodes);
  host_state.bin2node_map.resize(db.num_bins_x * db.num_bins_y);
}

}  // namespace dpo