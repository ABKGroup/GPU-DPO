#include <vector>
#include <iostream>
#include <cmath>
#include <numeric>

#include "architecture.h"
#include "detailed.h"
#include "detailed_db.h"
#include "detailed_manager.h"
#include "network.h"
#include "orientation.h"
#include "router.h"
#include "symmetry.h"

namespace dpo {

DetailedPlaceDB::DetailedPlaceDB() {
  
}

DetailedPlaceDB::DetailedPlaceDB(Network* network, Architecture* arch, DetailedMgr* mgr) {
  network_ = network;
  arch_ = arch;
  mgr_ = mgr;
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
  std::cout << "THE NUMBER OF REGIONS IS " << num_regions << std::endl;
  void createNodeInfo();
  void createPinInfo();
  void createNetInfo();
  void createFenceInfo();
  void createChipInfo();
  void createRowInfo();
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
  for (auto& pin : network_->getPins()) {
    pin2node_map.emplace_back(pin->getNode()->getId());
    pin2net_map.emplace_back(pin->getEdge()->getId());
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

  // sort flat_node2pin_map_index by increasing node id, then reorder all pin related arrays accordingly
  std::vector<int> indices(num_pins);
  std::iota(indices.begin(), indices.end(), 0);

  std::sort(indices.begin(), indices.end(), [&](int a, int b) {
    return flat_node2pin_map[a] < flat_node2pin_map[b];
  });

  std::vector<int> sorted_flat_node2pin_map(num_pins);
  std::vector<int> sorted_flat_node2pin_map_index(num_pins);
  std::vector<float> sorted_pin_offset_x(num_pins);
  std::vector<float> sorted_pin_offset_y(num_pins);

  for (int i = 0; i < num_pins; i++) {
    int sorted_idx = indices[i];
    sorted_flat_node2pin_map[i]       = flat_node2pin_map[sorted_idx];
    sorted_flat_node2pin_map_index[i] = flat_node2pin_map_index[sorted_idx];
    sorted_pin_offset_x[i]            = pin_offset_x[sorted_idx];
    sorted_pin_offset_y[i]            = pin_offset_y[sorted_idx];
  }

  flat_node2pin_map = std::move(sorted_flat_node2pin_map);
  pin_offset_x = std::move(sorted_pin_offset_x);
  pin_offset_y = std::move(sorted_pin_offset_y);
}

void DetailedPlaceDB::createNetInfo() {
  std::vector<int> flat_net2pin_map_index(num_pins);

  // create flattened mapping between net and a list of its pins
  flat_net2pin_map.resize(num_pins);
  flat_net2pin_start_map.resize(num_nets);

  int ptr = 0;
  int lastIdx = 0;
  for (int i = 0; i < network_->getNumEdges(); i++) {
    Edge* edge = network_->getEdge(i);
    int edge_id = edge->getId();
    for (auto& pin : edge->getPins()) {
      flat_net2pin_map[ptr] = edge_id;
      ptr++;
    }
    lastIdx += edge->getPins().size();
    flat_net2pin_start_map[edge_id] = lastIdx;
  }

  // sort flat_node2pin_map_index by increasing node id, then reorder all pin related arrays accordingly
  std::vector<int> indices(num_pins);
  std::iota(indices.begin(), indices.end(), 0);

  std::sort(indices.begin(), indices.end(), [&](int a, int b) {
    return flat_net2pin_map[a] < flat_net2pin_map[b];
  });

  std::vector<int> sorted_flat_net2pin_map(num_pins);
  std::vector<int> sorted_flat_net2pin_map_index(num_pins);

  for (int i = 0; i < num_pins; i++) {
    int sorted_idx = indices[i];
    sorted_flat_net2pin_map[i]       = flat_net2pin_map[sorted_idx];
    sorted_flat_net2pin_map_index[i] = flat_net2pin_map_index[sorted_idx];
  }

  flat_net2pin_map = std::move(sorted_flat_net2pin_map);

  // net_mask to filter out which nets to skip during hpwl calculation
  net_mask.resize(num_nets);
  for (int i = 0; i < num_nets; i++) {
    int net2_num_pins = network_->getEdge(i)->getNumPins();
    net_mask[i] = ((net2_num_pins <= skipNetsLargerThanThis_) & net2_num_pins >= 2);
  }
}

void DetailedPlaceDB::createFenceInfo() {
  unsigned num_rects = 0;

  for (auto& region : arch_->getRegions()) {
    num_rects += region->getRects().size();
  }

  flat_region_boxes_start.resize(num_rects * 4);
  flat_region_boxes.resize(num_regions + 1);
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

// void DetailedPlaceDB::setupIndexMap() {
//   // used to create 1:1 mappings between important components (nodes, pins, nets, etc.)
//   std::vector<int> pin_id2node_id_vec;
//   std::vector<int> pin_id2net_id_vec;
//   for (int i = 0; i < network_->getNumNodes(); i++) {
//     Node* node = network->getNode(i);
//     for (int j = 0; j < node->getPins().size(); j++) {
//       Pin* pin = node->getPins()[j];
//       pin_id2node_id.emplace_back(node->getId());
//     }
//   }
//   for (int i = 0; i < network_->getNumEdges(); i++) {
//     Edge* edge = network_->getEdge(i);
//     for (int j = 0; j < edge->getPins().size(); j++) {
//       Pin* pin = edge->getPins()[j];
//       pin_id2net_id.emplace_back(j);
//     }
//   }
//   pin_id2net_id = pin_id2net_id_vec.data();
//   pin_id2node_id = pin_id2node_id_vec.data();
// }

// void DetailedPlaceDB::createRegionInfo() {
//   auto optionsInt = torch::TensorOptions().dtype(torch::kInt64);

//   unsigned numRects = 0;
//   for (auto& region : arch_->getRegions()) {
//     numRects += region->getRects().size();
//   }
  
//   torch::Tensor node_id2region_id = torch::zeros({numNodes}, optionsInt);
//   torch::Tensor region_boxes = torch::zeros({numRects, 4});
//   torch::Tensor region_boxes_end = torch::zeros({numRegions}, optionsInt);

//   auto node_id2region_id_accessor = node_id2region_id.accessor<int64_t, 1>();
//   auto region_boxes_accessor = region_boxes.accessor<float, 2>();
//   auto region_boxes_end_accessor = region_boxes_end.accessor<int64_t, 1>();

//   for (int i = 0; i < network_->getNumNodes(); i++) {
//     Node* nd = network_->getNode(i);
//     int node_id = nd->getId();
//     int region_id = nd->getRegionId();
//     node_id2region_id_accessor[node_id] = region_id;
//   }

//   int ptr = 0;
//   int lastIdx = 0;
//   for (auto& region : arch_->getRegions()) {
//     int region_id = region->getId();
//     for (auto& rect : region->getRects()) {
//       region_boxes_accessor[ptr][0] = rect.getMinX();
//       region_boxes_accessor[ptr][1] = rect.getMinY();
//       region_boxes_accessor[ptr][2] = rect.getMaxX();
//       region_boxes_accessor[ptr][3] = rect.getMaxY();
//       ptr++;
//     }
//     lastIdx += region->getRects().size();
//     region_boxes_end_accessor[region_id] = lastIdx;
//   }
//   node2fence_region_map = node_id2region_id.data_ptr<int>();
//   flat_region_boxes = region_boxes.flatten().contiguous().clone().data_ptr<float>();
//   flat_region_boxes_start = torch::cat({torch::zeros({1}, torch::dtype(torch::kInt32).device(torch::Device(nodeSizeTensor.device()))),
//                     region_boxes_end},
//                    0)
//             .contiguous().data_ptr<int>();
// }

// void DetailedPlaceDB::createNode2PinInfo() {
//   auto options = torch::TensorOptions().dtype(torch::kInt64);

//   //torch::Tensor node2pin_index_helper = torch::zeros({numPins}, options);
//   torch::Tensor node2pin_list = torch::zeros({numPins}, options);
//   torch::Tensor node2pin_list_end = torch::zeros({numNodes}, options);
//   torch::Tensor node2pin_offsetx_list = torch::zeros({numPins}, options);
//   torch::Tensor node2pin_offsety_list = torch::zeros({numPins}, options);
//   torch::Tensor node2pin_width_list = torch::zeros({numPins}, options);
//   torch::Tensor node2pin_height_list = torch::zeros({numPins}, options); 

//   //auto node2pin_index_helper_accessor = node2pin_index_helper.accessor<int64_t, 1>();
//   auto node2pin_list_accessor = node2pin_list.accessor<int64_t, 1>();
//   auto node2pin_list_end_accessor = node2pin_list_end.accessor<int64_t, 1>();
//   auto node2pin_offsetx_list_accessor = node2pin_offsetx_list.accessor<int64_t, 1>();
//   auto node2pin_offsety_list_accessor = node2pin_offsety_list.accessor<int64_t, 1>();
//   auto node2pin_width_list_accessor = node2pin_width_list.accessor<int64_t, 1>();
//   auto node2pin_height_list_accessor = node2pin_height_list.accessor<int64_t, 1>();

//   int ptr = 0;
//   int lastIdx = 0;
//   for (int i = 0; i < network_->getNumNodes(); i++) {
//     Node* node = network_->getNode(i);
//     int node_id = node->getId();
//     for (auto& pin : node->getPins()) {
//       node2pin_list_accessor[ptr] = node_id;
//       node2pin_offsetx_list_accessor[ptr] = pin->getOffsetX();
//       node2pin_offsety_list_accessor[ptr] = pin->getOffsetY();
//       node2pin_width_list_accessor[ptr] = pin->getPinWidth();
//       node2pin_height_list_accessor[ptr] = pin->getPinHeight();
//       ptr++;
//     }
//     lastIdx += node->getPins().size();
//     node2pin_list_end_accessor[node_id] = lastIdx;
//   }

//   // sort all the pin information based on increasing node id
//   auto node2pin_index = torch::cat({
//     node2pin_list.unsqueeze(0),
//     node2pin_offsetx_list.unsqueeze(0),
//     node2pin_offsety_list.unsqueeze(0),
//     node2pin_width_list.unsqueeze(0),
//     node2pin_height_list.unsqueeze(0)
//   }, 0);

//   auto new_order_idx = torch::argsort(node2pin_index.index({0}), 0, false);
//   node2pin_index = node2pin_index.index({torch::indexing::Slice(), new_order_idx});
//   //auto node2pin_index = torch::cat({node2pin_list.unsqueeze(0), node2pin_offsetx_list_accessor.unsqueeze(0)}, 0);
//   //auto new_order_idx = torch::argsort(node2pin_index.index({0}), 0, false);
//   //node2pin_index = node2pin_index.index({torch::indexing::Slice(), new_order_idx});
//   flat_node2pin_map = node2pin_list.data_ptr<int>();
//   flat_node2pin_start_map = torch::cat({torch::zeros({1}, torch::dtype(torch::kInt32).device(torch::Device(nodeSizeTensor.device()))),
//                     node2pin_list_end},
//                    0)
//             .contiguous().data_ptr<int>();
// }

// void DetailedPlaceDB::createNet2PinInfo() {
//   auto options = torch::TensorOptions().dtype(torch::kInt64);

//   //torch::Tensor net_index_helper = torch::zeros({numPins}, options);
//   torch::Tensor net_list = torch::zeros({numPins}, options);
//   torch::Tensor net_list_end = torch::zeros({numEdges}, options);

//   //auto net_index_helper_accessor = net_index_helper.accessor<int64_t, 1>();
//   auto net_list_accessor = net_list.accessor<int64_t, 1>();
//   auto net_list_end_accessor = net_list_end.accessor<int64_t, 1>();

//   int ptr = 0;
//   int lastIdx = 0;
//   for (int i = 0; i < network_->getNumEdges(); i++) {
//     Edge* edge = network_->getEdge(i);
//     int edge_id = edge->getId();
//     for (auto& pin : edge->getPins()) {
//       net_list_accessor[ptr] = edge_id;
//       ptr++;
//     }
//     lastIdx += edge->getPins().size();
//     net_list_end_accessor[edge_id] = lastIdx;
//   }
//   auto net_index = torch::cat({net_list.unsqueeze(0)}, 0);
//   auto new_order_idx = torch::argsort(net_index.index({0}), 0, false);
//   net_index = net_index.index({torch::indexing::Slice(), new_order_idx});

//   std::vector<int> edgeMaskTemp;
//   edgeMaskTemp.resize(network_->getNumEdges());
//   std::fill(edgeMaskTemp.begin(), edgeMaskTemp.end(), 0);
//   edgeMask = edgeMaskTemp.data();

//   flat_net2pin_map = net_list.data_ptr<int>();
//   flat_net2pin_start_map = torch::cat({torch::zeros({1}, torch::dtype(torch::kInt32).device(torch::Device(nodeSizeTensor.device()))),
//                     net_list_end},
//                    0)
//             .contiguous().data_ptr<int>();
// }

// void DetailedPlaceDB::getCandidates(std::vector<Node*>& candidates) {
//   candidates = mgr_->getSingleHeightCells();

//   // flatten single height cells
  
// }

} // namespace dpo