// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <vector>

#include "architecture.h"
#include "network.h"

namespace dpl {

class FlattenedData {
public:
  FlattenedData(Architecture* arch, Network* network);

  void createFlattenedData();

  void populateNetwork(Network& network);

  Architecture* arch_;
  Network* network_;

  /* node info */
  std::vector<int> init_x;  
  std::vector<int> init_y;  
  std::vector<int> x;      
  std::vector<int> y;     
  std::vector<int> node_size_x; 
  std::vector<int> node_size_y; 

  /* pin info */
  std::vector<int> pin_offset_x;  
  std::vector<int> pin_offset_y;  

  std::vector<int> flat_node2pin_start_map;   
  std::vector<int> flat_node2pin_map;   
  std::vector<int> pin2node_map;     

  /* net info */
  std::vector<int> flat_net2pin_start_map;  
  std::vector<int> flat_net2pin_map;    
  std::vector<int> pin2net_map;  
  std::vector<int> net_mask; 

  /* fence info */
  std::vector<int> flat_region_boxes_start;
  std::vector<float> flat_region_boxes;
  std::vector<int> node2fence_region_map;

  // Core die coordinates
  int xl;
  int yl;
  int xh;
  int yh;

  // used to shift core to the origin
  int shift_factor_x = 0;   
  int shift_factor_y = 0;

  // Row/site grid info
  int num_sites_x;     // number of columns
  int num_sites_y;     // number of rows

  // Count info
  int num_pins;
  int num_nets;
  int num_cells;
  int num_nodes;             // Total nodes: movable + terminals + fillers
  int num_movable_nodes;     // Nodes in [0, num_movable_nodes)
  int num_terminal_nodes;    // Nodes in [num_movable_nodes, num_nodes - num_filler_nodes)
  int num_filler_nodes;      // Nodes in [num_nodes - num_filler_nodes, num_nodes)
  int num_regions;
  int region_boxes_size;

  // Placement/site dimensions
  int site_width;
  int row_height;

  // System settings
  int num_threads;

private:
  void createNodeInfo();
  void createPinInfo();
  void createNetInfo();
  void createFenceInfo();
  void createChipInfo();
  void createRowInfo();
  void shiftDatabase();

  // Other
  int skipNetsLargerThanThis_ = 100;
};

} // namespace dpl