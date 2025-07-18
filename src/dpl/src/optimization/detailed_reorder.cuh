// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <string>
#include <vector>

#define MAX_K 8     // Maximum number of cells in a reorder window
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
  int group_id;           // which group this reorder instance belongs to
  int seg_id;             // segment ID in which this reorder is applied
  int row_id;             // physical row ID
  int istrt, istop;       // [start, stop] indices in the segment
  int left_limit;         // left boundary of legal space
  int right_limit;        // right boundary of legal space
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

struct DPState {
  int placed_mask; // bitmask: which cells are placed
  int pos[MAX_K];  // x position for each cell (if placed)
  int row[MAX_K];  // row for each cell (if placed)
  int cost;        // total cost (HPWL, inf if overlap)
  int variants[MAX_K]; // cell variants (0=original, 1=flipped)
  int status; // Binary status array (packed)
};

class DetailedReorderer
{
 public:
  DetailedReorderer(Architecture* arch, Network* network);

  void run(DetailedMgr* mgrPtr, const std::string& command);
  void run(DetailedMgr* mgrPtr, const std::vector<std::string>& args);

  void run(DetailedMgr* mgrPtr, GpuData& db, const std::string& command);
  void run(DetailedMgr* mgrPtr, GpuData& db_, const std::vector<std::string>& args);

 private:
  void reorder();
  void reorder(const std::vector<Node*>& nodes,
               int jstrt,
               int jstop,
               DbuX leftLimit,
               DbuX rightLimit,
               int segId,
               int rowId);
  double cost(const std::vector<Node*>& nodes, int istrt, int istop);
  Architecture* arch_;
  Network* network_;

  // For segments.
  DetailedMgr* mgrPtr_ = nullptr;

  // Other.
  int skipNetsLargerThanThis_ = 100;
  std::vector<int> edgeMask_;
  int traversal_ = 0;
  int windowSize_ = 3;
  int numBinsX_ = 256;
  int numBinsY_ = 256;
};

}  // namespace dpl
