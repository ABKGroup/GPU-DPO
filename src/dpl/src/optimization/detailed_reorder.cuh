// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <string>
#include <vector>

#define MAX_K 4     // Maximum number of cells in a reorder window
#define MAX_NUM_NETS_PER_NODE 20
#define MAX_NUM_NETS_PER_INSTANCE (MAX_NUM_NETS_PER_NODE * MAX_K)

#include "infrastructure/Coordinates.h"
#include "infrastructure/GpuData.cuh"
namespace dpl {
class Node;
class Architecture;
class DetailedMgr;
class Network;

// Instance definition: describes one reorder window
struct ReorderInstance {
  int num_cells;          // how many cells in this window
  int node_ids[MAX_K];    // node IDs
  int seg_id;             // segment ID in which this reorder is applied
  int row_id;             // physical row ID
  int jstrt, jstop;       // [start, stop] indices in the segment
  int left_limit;         // left boundary of legal space
  int right_limit;        // right boundary of legal space
};

// GPU-resident reorder state including permutations, costs, etc.
struct ReorderState {
  ReorderInstance* instances;   // [num_instances]
  int* permutations;            // [num_permutations * MAX_K]
  int* costs;                   // [num_instances * num_permutations]
  int* group_offsets;           // [num_groups]
  int* group_counts;            // [num_groups]
  int* best_permute_id;         // [num_instances]
  int* net_hpwls;

  int* h_group_counts;
  int* h_group_offsets;

  int num_groups = 0;
  int num_instances = 0;
  int num_permutations = 0;
  int K;

  void allocate(int n_instances, int n_perms) {
    num_instances = n_instances;
    num_permutations = n_perms;
    
    //allocateCuda(instances, num_instances, ReorderInstance);
    //allocateCuda(permutations, num_permutations * MAX_K, int);
    allocateCuda(costs, num_instances * num_permutations, int);
    allocateCuda(best_permute_id, num_instances, int);
  }

  void destroy() {
    cudaFree(instances);
    cudaFree(permutations);
    cudaFree(costs);
    cudaFree(best_permute_id);
  }
};

struct InstanceNet {
  int net_id;
  int node_marker;  ///< mark cells in one instance using bit
  int bxl;
  int bxh;
  int pin_offset_x[MAX_K];
};

struct KReorderInstance {
  int group_id;
  int row_id;
  int idx_bgn;
  int idx_end;
};

struct KReorderState {
  PitchNestedVector<int> row2node_map;
  int* permutations;  ///< num_permutations x K
  int num_permutations;

  int* node_space_x;  ///< cell size with spaces, a cell only considers its right
                      ///< space

  PitchNestedVector<KReorderInstance> reorder_instances;  ///< array of array
                                                          ///< for independent
                                                          ///< instances; each
                                                          ///< instance is a
                                                          ///< sequence of at
                                                          ///< most K cells to
                                                          ///< be solved.
  int* costs;                                             ///< maximum reorder_instances.size2 * num_permutations
  int* best_permute_id;                                   ///< maximum reorder_instances.size2
  InstanceNet* instance_nets;                             ///< reorder_instances.size2 * MAX_NUM_NETS_PER_INSTANCE
  int* instance_nets_size;                                ///< reorder_instances.size2, number of nets for
                                                          ///< each instance
  int* node2inst_map;                                     ///< map cell to instance
  int* net_markers;                                       ///< whether a net is in this group
  unsigned char* node_markers;                            ///< cell offset in instance

  int* device_num_moved;
  int K;  ///< number of cells to reorder

  int* net_hpwls;  ///< used for compute HPWL
};

class DetailedReorderer
{
 public:
  DetailedReorderer(Architecture* arch, Network* network);

  void run(DetailedMgr* mgrPtr, GpuData& db, const std::string& command);
  void run(DetailedMgr* mgrPtr, GpuData& db_, const std::vector<std::string>& args);

 private:
  Architecture* arch_;
  Network* network_;

  // For segments.
  DetailedMgr* mgrPtr_ = nullptr;

  // Other.
  int windowSize_ = 3;
  int numBinsX_ = 256;
  int numBinsY_ = 256;
};

}  // namespace dpl
