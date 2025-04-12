#include <vector>
#include <iostream>
#include <cmath>
#include <numeric>

#include "architecture.h"
#include "detailed_db.h"
#include "detailed_manager.h"
#include "network.h"
#include "orientation.h"
#include "router.h"
#include "symmetry.h"

namespace dpo {

DetailedPlaceDB::DetailedPlaceDB(Network* network, Architecture* arch, DetailedMgr* mgr) {
  network_ = network;
  arch_ = arch;
  mgr_ = mgr;
}

DetailedPlaceDB::~DetailedPlaceDB() {
  network_ = nullptr;
  arch_ = nullptr;
  mgr_ = nullptr;
}

void DetailedPlaceDB::createDetailedPlaceDB() {
  num_nodes = network_->getNumNodes();
  num_pins = network_->getNumPins();
  num_nets = network_->getNumEdges();
  num_regions = arch_->getNumRegions();
  num_movable_nodes = mgr_->getSingleHeightCells().size();
  site_width = arch_->getRow(0)->getSiteWidth();
  row_height = arch_->getRow(0)->getHeight();    // single row height
  num_threads = 256;  // may need to change this later
  createNodeInfo();
  createPinInfo();
  createNetInfo();
  createFenceInfo();
  createChipInfo();
  createRowInfo();
  // debug();
}

void DetailedPlaceDB::createNodeInfo() {
  init_x.resize(num_nodes);
  init_y.resize(num_nodes);
  x.resize(num_nodes);
  y.resize(num_nodes);
  node_size_x.resize(num_nodes);
  node_size_y.resize(num_nodes);

  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    init_x[node_id] = node->getOrigLeft();
    init_y[node_id] = node->getOrigBottom();
    x[node_id] = node->getLeft();
    y[node_id] = node->getBottom();
    node_size_x[node_id] = node->getWidth();
    node_size_y[node_id] = node->getHeight();
  }
}

void DetailedPlaceDB::createPinInfo() {
  std::vector<int> flat_node2pin_map_index(num_pins);

  pin2node_map.resize(num_pins);
  pin2net_map.resize(num_pins);
  for (int i = 0; i < num_pins; i++) {
    Pin* pin = network_->getPin(i);
    pin2node_map[i] = pin->getNode()->getId();
    pin2net_map[i] = pin->getEdge()->getId();
  }

  // create flattened mapping between node and a list of its pins
  flat_node2pin_map.resize(num_pins);
  flat_node2pin_start_map.resize(num_nodes);
  pin_offset_x.resize(num_pins);
  pin_offset_y.resize(num_pins);

  int ptr = 0;
  int lastIdx = 0;
  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    for (auto& pin : node->getPins()) {
      flat_node2pin_map[ptr] = pin->getId();
      flat_node2pin_map_index[ptr] = node_id;
      pin_offset_x[ptr] = pin->getOffsetX();
      pin_offset_y[ptr] = pin->getOffsetY();
      ptr++;
    }
    lastIdx += node->getPins().size();
    flat_node2pin_start_map[node_id] = lastIdx;
  }

  for (int i = flat_node2pin_start_map.size() - 1; i > 0; --i) {
      flat_node2pin_start_map[i] = flat_node2pin_start_map[i - 1];
  }
  flat_node2pin_start_map[0] = 0; 
  // sort flat_node2pin_map_index by increasing node id, then reorder all pin related arrays accordingly
  // std::vector<int> indices(num_pins);
  // std::iota(indices.begin(), indices.end(), 0);

  // std::sort(indices.begin(), indices.end(), [&](int a, int b) {
  //   return flat_node2pin_map[a] < flat_node2pin_map[b];
  // });

  // std::vector<int> sorted_flat_node2pin_map(num_pins);
  // std::vector<int> sorted_flat_node2pin_map_index(num_pins);
  // std::vector<float> sorted_pin_offset_x(num_pins);
  // std::vector<float> sorted_pin_offset_y(num_pins);

  // for (int i = 0; i < num_pins; i++) {
  //   int sorted_idx = indices[i];
  //   sorted_flat_node2pin_map[i]       = flat_node2pin_map[sorted_idx];
  //   sorted_flat_node2pin_map_index[i] = flat_node2pin_map_index[sorted_idx];
  //   sorted_pin_offset_x[i]            = pin_offset_x[sorted_idx];
  //   sorted_pin_offset_y[i]            = pin_offset_y[sorted_idx];
  // }

  // flat_node2pin_map = std::move(sorted_flat_node2pin_map);
  // flat_node2pin_map_index = std::move(sorted_flat_node2pin_map_index);
  // pin_offset_x = std::move(sorted_pin_offset_x);
  // pin_offset_y = std::move(sorted_pin_offset_y);

  // // Recompute flat_node2pin_start_map from sorted node_id mapping
  // // For each node, we mark the *end index* (exclusive) in the flat_node2pin_map
  // for (int i = 0; i < num_pins; ++i) {
  //   int node_id = flat_node2pin_map_index[i];
  //   flat_node2pin_start_map[node_id] = i + 1;
  // }

  // // Convert flat_node2pin_start_map from end indices to end of ranges
  // // i.e., if node i ends at pos k, and node i-1 ended at j, then node i’s pins are at [j, k)
  // // So we want to accumulate max for correct CSR-style ranges
  // for (int i = 1; i < num_nodes; ++i) {
  //   flat_node2pin_start_map[i] = std::max(flat_node2pin_start_map[i], flat_node2pin_start_map[i - 1]);
  // }
}

void DetailedPlaceDB::debug() {
  int nodeSize = network_->getNumNodes();
  int node_id;
  for (int i = 0; i < nodeSize; i++) {
    Node* node = network_->getNode(i);
    if (node->getPins().size() > 0) {
      node_id = i;
    }
    if (node_id == nodeSize - 1) {
      break;
    }
    Node* nd = network_->getNode(node_id);
    std::vector<Pin*> pins = nd->getPins();
    for (auto& pin : pins) {
      //std::cout << "Pin id " << pin->getId() << std::endl;
    }
    int node2pin_id = flat_node2pin_start_map[node_id];
    const int node2pin_id_end = flat_node2pin_start_map[node_id + 1];
    // for all pins that this node has print it out 
    int count = 0;
    for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
        int node_pin_id = flat_node2pin_map[node2pin_id];
        //std::cout << "Pin id " << node_pin_id << std::endl;
        int net_id = pin2net_map[node_pin_id];
        count++;
    }
    if (count != nd->getPins().size()) {
      std::cout << "Expected " << nd->getPins().size() << " but received " << count << std::endl;
    }
  }
}

void DetailedPlaceDB::createNetInfo() {
  std::vector<int> flat_net2pin_map(num_pins);        // pin IDs, flattened
  std::vector<int> flat_net2pin_map_index(num_pins);  // corresponding net IDs
  std::vector<int> flat_net2pin_start_map(num_nets);  // end offset per net

  int ptr = 0;
  int lastIdx = 0;
  for (int i = 0; i < network_->getNumEdges(); i++) {
    Edge* edge = network_->getEdge(i);
    int edge_id = edge->getId();
    for (auto& pin : edge->getPins()) {
      flat_net2pin_map[ptr] = pin->getId();        
      flat_net2pin_map_index[ptr] = edge_id;        
      ptr++;
    }
    lastIdx += edge->getPins().size();
    flat_net2pin_start_map[edge_id] = lastIdx;
  }

  for (int i = flat_net2pin_start_map.size() - 1; i > 0; --i) {
      flat_net2pin_start_map[i] = flat_net2pin_start_map[i - 1];
  }
  flat_net2pin_start_map[0] = 0; 
  // sort by pin ID
  // std::vector<int> indices(num_pins);
  // std::iota(indices.begin(), indices.end(), 0);

  // std::sort(indices.begin(), indices.end(), [&](int a, int b) {
  //   return flat_net2pin_map[a] < flat_net2pin_map[b];  // sort by pin ID
  // });

  // // apply sort
  // std::vector<int> sorted_flat_net2pin_map(num_pins);
  // std::vector<int> sorted_flat_net2pin_map_index(num_pins);
  // for (int i = 0; i < num_pins; i++) {
  //   int sorted_idx = indices[i];
  //   sorted_flat_net2pin_map[i]       = flat_net2pin_map[sorted_idx];
  //   sorted_flat_net2pin_map_index[i] = flat_net2pin_map_index[sorted_idx];
  // }

  // flat_net2pin_map = std::move(sorted_flat_net2pin_map);

  // net_mask to filter out which nets to skip during hpwl calculation
  net_mask.resize(num_nets);
  for (int i = 0; i < num_nets; i++) {
    int net2_num_pins = network_->getEdge(i)->getNumPins();
    net_mask[i] = ((net2_num_pins <= skipNetsLargerThanThis_) & (net2_num_pins >= 2));
  }
}

void DetailedPlaceDB::createFenceInfo() {
  unsigned num_rects = 0;

  for (auto& region : arch_->getRegions()) {
    num_rects += region->getRects().size();
  }
  flat_region_boxes_start.resize(num_regions + 1);
  flat_region_boxes.resize(num_rects * 4);
  node2fence_region_map.resize(num_nodes);
  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    int region_id = node->getRegionId();
    node2fence_region_map[node_id] = region_id;
  }

  int ptr = 0;
  int lastIdx = 0;
  flat_region_boxes_start[0] = 0;
  for (auto& region : arch_->getRegions()) {
    int region_id = region->getId();
    for (auto& rect : region->getRects()) {
      flat_region_boxes[ptr++] = rect.xmin();
      flat_region_boxes[ptr++] = rect.ymin();
      flat_region_boxes[ptr++] = rect.xmax();
      flat_region_boxes[ptr++] = rect.ymax();
    }
    lastIdx += ptr;
    flat_region_boxes_start[region_id + 1] = lastIdx;
  }
}

void DetailedPlaceDB::createChipInfo() {
  xl = arch_->getMinX();
  yl = arch_->getMinY();
  xh = arch_->getMaxX();
  yh = arch_->getMaxY();
}

void DetailedPlaceDB::createRowInfo() {
  num_sites_x = std::round((xh - xl) / site_width);
  num_sites_y = std::round((yh - yl) / row_height);
}

} // namespace dpo