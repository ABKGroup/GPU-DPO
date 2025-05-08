// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <string>
#include <vector>

#define MAX_K 4
#define MAX_NUM_NETS_PER_NODE 20
#define MAX_NUM_NETS_PER_INSTANCE (MAX_NUM_NETS_PER_NODE * MAX_K)

#include "infrastructure/Coordinates.h"
#include "infrastructure/GpuData.cuh"
namespace dpl {
class Node;
class Architecture;
class DetailedMgr;
class Network;

template <typename T1, typename T2>
__device__ inline void device_swap(T1& a, T2& b) {
  T1 tmp = a;
  a = b;
  b = tmp;
}

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

struct ItemWithIndex {
  int value;
  int index;
};

struct ReduceMinOP {
  __host__ __device__ ItemWithIndex operator()(const ItemWithIndex& a, const ItemWithIndex& b) const {
      return (a.value < b.value) ? a : b;
  }
};

class DetailedReorderer
{
 public:
  DetailedReorderer(GpuData* gpuData);

  void run(DetailedMgr* mgrPtr, const std::string& command);
  void run(DetailedMgr* mgrPtr, const std::vector<std::string>& args);

 private:
  // Standard stuff.
  GpuData* db_;

  // For segments.
  DetailedMgr* mgrPtr_ = nullptr;

  // Other.
  int windowSize_ = 3;
  int numBinsX_ = 256;
  int numBinsY_ = 256;
};

}  // namespace dpl
