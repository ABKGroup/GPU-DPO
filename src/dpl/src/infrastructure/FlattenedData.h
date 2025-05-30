// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <vector>

#include "architecture.h"
#include "network.h"
#include "optimization/detailed_manager.h"

namespace dpl {

class FlattenedData {
public:
  FlattenedData(DetailedMgr* mgr);

  void createFlattenedData();

  void populateNetwork(Network& network, DetailedMgr& mgr);

  DetailedMgr* mgr_;
  Architecture* arch_;
  Network* network_;

  /* node info */
  std::vector<int> init_x;  
  std::vector<int> init_y;  
  std::vector<int> x;      
  std::vector<int> y;     
  std::vector<int> node_size_x; 
  std::vector<int> node_size_y; 
  std::vector<int> node_bottom_power;
  std::vector<int> node_top_power;

  /* segment info */
  std::vector<int> node2segs;               // stores which cells are in the segments
  //std::vector<int> flat_seg2node_map;       // stores the contiguous list of nodes in each segment
  //std::vector<int> flat_seg2node_start_map; // start position of segments
  int num_segments;

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

  // DRC info (for edge spacing and padding checks)
  // Padding and edge spacing is usually 0 
  bool use_padding = 0;
  std::vector<int> node_left_padding;
  std::vector<int> node_right_padding;

  // Core die coordinates
  int xl;
  int yl;
  int xh;
  int yh;

  // used to shift core to the origin (may not need this at all)
  int shift_factor_x = 0;   
  int shift_factor_y = 0;

  // displacement limits
  int max_displacement_x;
  int max_displacement_y;

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
  int site_spacing;
  int row_left;

  // System settings
  int num_threads;

  // MIS parameters
  bool use_same_size = true;   // only exchange cells with the same size

private:
  void createNodeInfo();
  void createPinInfo();
  void createNetInfo();
  void createFenceInfo();
  void createChipInfo();
  void createRowInfo();
  void createSegmentInfo();
  void shiftDatabase(); // we may not need this

  // Other
  int skipNetsLargerThanThis_ = 100;
};

} // namespace dpl