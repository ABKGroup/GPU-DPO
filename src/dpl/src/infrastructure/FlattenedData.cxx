// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include <vector>
#include <iostream>
#include <cmath>
#include <numeric>
#include <algorithm>
#include <limits>

#include "FlattenedData.h"

namespace dpl {

FlattenedData::FlattenedData(DetailedMgr* mgr) {
  mgr_ = mgr;
  arch_ = mgr_->getArchitecture();
  network_ = mgr_->getNetwork();
}

void FlattenedData::createFlattenedData() {
  num_nodes = network_->getNumNodes();
  num_cells = network_->getNumCells();
  num_pins = network_->getNumPins();
  num_nets = network_->getNumEdges();
  num_regions = arch_->getNumRegions();
  site_width = arch_->getRow(0)->getSiteWidth().v;
  row_height = arch_->getRow(0)->getHeight().v;
  site_spacing = arch_->getRow(0)->getSiteSpacing().v;
  row_left = arch_->getRow(0)->getLeft().v;
  max_displacement_x = mgr_->getMaxDisplacementX();
  max_displacement_y = mgr_->getMaxDisplacementY();
  num_threads = 8;

  createNodeInfo();
  createSegmentInfo();
  createPinInfo();
  createNetInfo();
  createFenceInfo();
  createChipInfo();
  createRowInfo();
  //shiftDatabase();    // don't think this is needed
}

void FlattenedData::createNodeInfo() {
  // Creates padding info for each node
  use_padding = arch_->getUsePadding();
  node_left_padding.resize(num_nodes);
  node_right_padding.resize(num_nodes);
  
  num_movable_nodes = network_->getNumMovableNodes();
  num_terminal_nodes = network_->getNumTerminalNodes();
  num_filler_nodes = network_->getNumFillerNodes();

  init_x.resize(num_nodes);
  init_y.resize(num_nodes);
  x.resize(num_nodes);
  y.resize(num_nodes);
  node_size_x.resize(num_nodes);
  node_size_y.resize(num_nodes);
  node_bottom_power.resize(num_nodes);
  node_top_power.resize(num_nodes);

  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    init_x[node_id] = node->getOrigLeft().v;
    init_y[node_id] = node->getOrigBottom().v;
    x[node_id] = node->getLeft().v;
    y[node_id] = node->getBottom().v;
    node_size_x[node_id] = node->getWidth().v;
    node_size_y[node_id] = node->getHeight().v;
    node_bottom_power[node_id] = node->getBottomPower();
    node_top_power[node_id] = node->getTopPower();
    if (use_padding) {
      int leftPadding, rightPadding;
      arch_->getCellPadding(node, leftPadding, rightPadding);
      node_left_padding[node->getId()] = leftPadding;
      node_right_padding[node->getId()] = rightPadding;
    } else {
      node_left_padding[node->getId()] = 0;
      node_right_padding[node->getId()] = 0;
    }
  }
}

void FlattenedData::createSegmentInfo() {
  num_segments = mgr_->getNumSegments();
  node2segs.resize(num_nodes);
  for (int i = 0; i < mgr_->getNumSegments(); i++) {
    const std::vector<Node*>& nodes = mgr_->getCellsInSeg(i);
    for (Node* node : nodes) {
      int node_id = node->getId();
      node2segs[node_id] = i; 
    }
  }
}

void FlattenedData::createPinInfo() {
  pin2node_map.resize(num_pins);
  pin2net_map.resize(num_pins);
  for (int i = 0; i < network_->getNumPins(); i++) {
    Pin* pin = network_->getPin(i);
    int pin_id = pin->getId();
    pin2node_map[pin_id] = pin->getNode()->getId();
    pin2net_map[pin_id] = pin->getEdge()->getId();
  }

  // create flattened mapping between node and list of its pins
  flat_node2pin_map.resize(num_pins);
  flat_node2pin_start_map.resize(num_nodes + 1);
  pin_offset_x.resize(num_pins);
  pin_offset_y.resize(num_pins);

  for (int pin_id = 0; pin_id < num_pins; pin_id++) {
    const Pin* pin = network_->getPin(pin_id);
    pin_offset_x[pin_id] = pin->getOffsetX().v;
    pin_offset_y[pin_id] = pin->getOffsetY().v;
  }

  int ptr = 0;
  int lastIdx = 0;
  flat_node2pin_start_map[0] = 0;
  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    for (auto* pin : node->getPins()) {
      flat_node2pin_map[ptr] = pin->getId();
      ptr++;
    }
    lastIdx += node->getPins().size();
    flat_node2pin_start_map[node_id + 1] = lastIdx;
  }
}

void FlattenedData::createNetInfo() {
  flat_net2pin_map.resize(num_pins);
  flat_net2pin_start_map.resize(num_nets + 1);

  int ptr = 0;
  int lastIdx = 0;
  flat_net2pin_start_map[0] = 0;
  for (int i = 0; i < network_->getNumEdges(); i++) {
    Edge* edge = network_->getEdge(i);
    int edge_id = edge->getId();
    for (auto& pin : edge->getPins()) {
      flat_net2pin_map[ptr] = pin->getId();
      ptr++;
    }
    lastIdx += edge->getPins().size();
    flat_net2pin_start_map[edge_id + 1] = lastIdx;
  }

  // net mask to filter out which nets to skip during hpwl calculation
  net_mask.resize(num_nets);
  for (int i = 0; i < network_->getNumEdges(); i++) {
    int net2_num_pins = network_->getEdge(i)->getNumPins();
    if ((net2_num_pins <= skipNetsLargerThanThis_) && (net2_num_pins >= 2)) {
      net_mask[i] = 1;
    } else {
      net_mask[i] = 0;
    }
  }
}

void FlattenedData::createFenceInfo() {
  // the simplest case: if there is only one region (which is the entire chip)
  // and the region has only one rectangle (no sub-rectangles)
  // then disregard fence regions completely
  // this implementation might need to change
  if (arch_->getRegions().size() == 1 
    && arch_->getRegions()[0]->getRects().size() == 1
    && arch_->getRegions()[0]->getRects()[0].xMin() == arch_->getMinX().v
    && arch_->getRegions()[0]->getRects()[0].yMin() == arch_->getMinY().v
    && arch_->getRegions()[0]->getRects()[0].xMax() == arch_->getMaxX().v
    && arch_->getRegions()[0]->getRects()[0].yMax() == arch_->getMaxY().v) {
    flat_region_boxes_start.resize(1);
    flat_region_boxes.resize(0);
    node2fence_region_map.resize(num_nodes);

    flat_region_boxes_start[0] = 0;
    for (int i = 0; i < num_nodes; i++) {
      node2fence_region_map[i] = std::numeric_limits<int>::max();
    }
    num_regions = 0;
    region_boxes_size = 0;
  }
  else {
    unsigned num_rects = 0;
    
    for (auto& region : arch_->getRegions()) {
      num_rects += region->getRects().size();
    }
    flat_region_boxes_start.resize(num_regions + 1);
    flat_region_boxes.resize(num_rects * 4);
    region_boxes_size = num_rects * 4;
    node2fence_region_map.resize(num_nodes);
    for (int i = 0; i < network_->getNumNodes(); i++) {
      Node* node = network_->getNode(i);
      int node_id = node->getId();
      int region_id = node->getGroupId();
      node2fence_region_map[node_id] = region_id;
    }

    int ptr = 0;
    int lastIdx = 0;
    flat_region_boxes_start[0] = 0;
    for (auto& region : arch_->getRegions()) {
      int region_id = region->getId();
      for (auto& rect : region->getRects()) {
        flat_region_boxes[ptr++] = rect.xMin();
        flat_region_boxes[ptr++] = rect.yMin();
        flat_region_boxes[ptr++] = rect.xMax();
        flat_region_boxes[ptr++] = rect.yMax();
      }
      lastIdx += region->getRects().size();
      flat_region_boxes_start[region_id + 1] = lastIdx;
    }
  }  
}

void FlattenedData::createChipInfo() {
  xl = arch_->getMinX().v;
  yl = arch_->getMinY().v;
  xh = arch_->getMaxX().v;
  yh = arch_->getMaxY().v;
}

void FlattenedData::createRowInfo() {
  num_sites_x = std::round((xh - xl) / site_width);
  num_sites_y = arch_->getNumRows();
}

void FlattenedData::shiftDatabase() {
  if (xl != 0) {
    shift_factor_x = xl;
    xl -= shift_factor_x;
    xh -= shift_factor_x;
    for (auto& val : x) {
      val -= shift_factor_x;
    }
    for (auto& val : init_x) {
      val -= shift_factor_x;
    }
  }
  if (yl != 0) {
    shift_factor_y = yl;
    yl -= shift_factor_y;
    yh -= shift_factor_y;
    for (auto& val : y) {
      val -= shift_factor_y;
    }
    for (auto& val : init_y) {
      val -= shift_factor_y;
    }
  }
}

// update node locations once device ops are done
void FlattenedData::populateNetwork(Network& network, DetailedMgr& mgr) {
  // shift the chip layout back to its original state
  /*if (xl == 0 && shift_factor_x != 0) {
    xl += shift_factor_x;
    xh += shift_factor_x;
    for (auto& val : x) {
      val += shift_factor_x;
    }
    for (auto& val : init_x) {
      val += shift_factor_x;
    }
  }
  if (yl == 0 && shift_factor_y != 0) {
    yl += shift_factor_y;
    yh += shift_factor_y;
    for (auto& val : y) {
      val += shift_factor_y;
    }
    for (auto& val : init_y) {
      val += shift_factor_y;
    }
  }*/
  std::vector<int> orig_node2segs(num_nodes);
  for (int i = 0; i < mgr.getNumSegments(); i++) {
    const std::vector<Node*>& nodes = mgr.getCellsInSeg(i);
    for (Node* node : nodes) {
      int node_id = node->getId();
      orig_node2segs[node_id] = i;
    }
  }
  // we should only have to update locations of non-fixed nodes
  for (int i = 0; i < network.getNumMovableNodes(); i++) {
    Node* node = network.getNode(i);
    if (node->getLeft().v != x[i]) {
      node->setLeft(DbuX{x[i]});
    }
    if (node->getBottom().v != y[i]) {
      node->setBottom(DbuY{y[i]});
    }
    // nodes might have moved to a different segment
    if (node2segs[i] != orig_node2segs[i]) {
      mgr.removeCellFromSegment(node, orig_node2segs[i]);
      mgr.addCellToSegment(node, node2segs[i]);
    }
  }
  mgr.resortSegments();
}

} // namespace dpl