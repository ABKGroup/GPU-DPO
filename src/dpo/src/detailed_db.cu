#include <vector>
#include <iostream>
#include <cmath>
#include <numeric>
#include <fstream>

#include "architecture.h"
#include "detailed_db.h"
#include "detailed_manager.h"
#include "network.h"
#include "orientation.h"
#include "router.h"
#include "symmetry.h"
#include "utility.h"
#include "rectangle.h"

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
  check_flattened_arrays();
  //compareFlattenedAndNetworkHPWL();
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
    int pin_id = pin->getId();
    pin2node_map[pin_id] = pin->getNode()->getId();
    pin2net_map[pin_id] = pin->getEdge()->getId();
  }

  // create flattened mapping between node and a list of its pins
  flat_node2pin_map.resize(num_pins);
  flat_node2pin_start_map.resize(num_nodes + 1);
  pin_offset_x.resize(num_pins);
  pin_offset_y.resize(num_pins);

  int ptr = 0;
  int lastIdx = 0;
  flat_node2pin_start_map[0] = 0;
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
    flat_node2pin_start_map[node_id + 1] = lastIdx;
  }
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

void DetailedPlaceDB::check_flattened_arrays() {
    bool passed = true;

    // Check node2pin mapping
    for (int node_id = 0; node_id < network_->getNumNodes(); ++node_id) {
        const Node* node = network_->getNode(node_id);
        const std::vector<Pin*>& pins = node->getPins();
        int start = flat_node2pin_start_map[node_id];
        int end = flat_node2pin_start_map[node_id + 1];

        if (end - start != (int)pins.size()) {
            std::cerr << "[INFO GPU-DPO] Mismatch in pin count for node " << node_id << std::endl;
            passed = false;
            continue;
        }

        for (int i = 0; i < (int)pins.size(); ++i) {
            int pin_id = flat_node2pin_map[start + i];
            int mapped_node = pin2node_map[pin_id];
            if (mapped_node != node_id) {
                std::cerr << "[INFO GPU-DPO] Incorrect pin2node mapping for pin " << pin_id << " at node " << node_id << std::endl;
                passed = false;
            }
        }
    }

    // Check net2pin mapping
    for (int net_id = 0; net_id < network_->getNumEdges(); ++net_id) {
        const Edge* net = network_->getEdge(net_id);
        const std::vector<Pin*>& pins = net->getPins();
        int start = flat_net2pin_start_map[net_id];
        int end = flat_net2pin_start_map[net_id + 1];

        if (end - start != (int)pins.size()) {
            std::cerr << "[INFO GPU-DPO] Mismatch in pin count for net " << net_id << std::endl;
            passed = false;
            continue;
        }

        for (int i = 0; i < (int)pins.size(); ++i) {
            int pin_id = flat_net2pin_map[start + i];
            const Pin* pin = pins[i];
            const Node* expected_node = pin->getNode();
            int expected_node_id = expected_node->getId();
            int actual_node_id = pin2node_map[pin_id];

            if (actual_node_id != expected_node_id) {
                std::cerr << "[INFO GPU-DPO] Incorrect pin2node mapping in net " << net_id
                          << " for pin " << pin_id << ": expected " << expected_node_id
                          << ", got " << actual_node_id << std::endl;
                passed = false;
            }
        }
    }

    // Check node coordinates
    for (int node_id = 0; node_id < network_->getNumNodes(); ++node_id) {
        const Node* node = network_->getNode(node_id);
        double expected_x = node->getLeft();
        double expected_y = node->getBottom();

        float actual_x = x[node_id];
        float actual_y = y[node_id];

        if (std::abs(actual_x - expected_x) > 1e-3 || std::abs(actual_y - expected_y) > 1e-3) {
            std::cerr << "[INFO GPU-DPO] Mismatch in node location for node " << node_id
                      << ": expected (" << expected_x << ", " << expected_y << ")"
                      << ", got (" << actual_x << ", " << actual_y << ")" << std::endl;
            passed = false;
        }
    }

    if (passed) {
        std::cout << "[INFO GPU-DPO] CHECK PASSED: Flattened arrays are consistent with the original data.\n";
    } else {
        std::cerr << "[INFO GPU-DPO] CHECK FAILED: See messages above for details.\n";
    }
}

/*double DetailedPlaceDB::compare_flattened_hpwl_vs_network()
{
  assert(network_ != nullptr);
  assert(flat_net2pin_start_map.size() == network_->getNumEdges() + 1);

  double hpwlx_flat = 0.0, hpwly_flat = 0.0;

  for (unsigned net_id = 0; net_id < network_->getNumEdges(); ++net_id) {
      int pin_start = flat_net2pin_start_map[net_id];
      int pin_end = flat_net2pin_start_map[net_id + 1];
      int num_pins = pin_end - pin_start;

      if (num_pins <= 1) continue;

      double min_x = std::numeric_limits<double>::max();
      double max_x = std::numeric_limits<double>::lowest();
      double min_y = std::numeric_limits<double>::max();
      double max_y = std::numeric_limits<double>::lowest();

      for (int i = pin_start; i < pin_end; ++i) {
          int pin_id = flat_net2pin_map[i];
          int node_id = pin2node_map[pin_id];
          double px = x[node_id] + 0.5 * node_size_x[node_id] + pin_offset_x[pin_id];
          double py = y[node_id] + 0.5 * node_size_y[node_id] + pin_offset_y[pin_id];

          min_x = std::min(min_x, px);
          max_x = std::max(max_x, px);
          min_y = std::min(min_y, py);
          max_y = std::max(max_y, py);
      }

      hpwlx_flat += (max_x - min_x);
      hpwly_flat += (max_y - min_y);
  }

  double flat_hpwl = hpwlx_flat + hpwly_flat;

  // Reference HPWL from network
  double hpwlx_ref = 0.0, hpwly_ref = 0.0;
  double ref_hpwl = Utility::hpwl(network_, hpwlx_ref, hpwly_ref);

  std::cout << "[INFO GPU-DPO] Original HPWL : " << ref_hpwl << " (x = " << hpwlx_ref << ", y = " << hpwly_ref << ")\n";
  std::cout << "[INFO GPU-DPO] Flattened HPWL: " << flat_hpwl << " (x = " << hpwlx_flat << ", y = " << hpwly_flat << ")\n";

  double relative_diff = std::abs(flat_hpwl - ref_hpwl) / std::max(1.0, ref_hpwl);
  std::cout << "[INFO GPU-DPO] Relative difference: " << relative_diff * 100.0 << "%\n";

  return relative_diff;
}*/

void DetailedPlaceDB::compareFlattenedAndNetworkHPWL()
{
    double total_original_hpwl = 0.0;
    double total_flattened_hpwl = 0.0;

    for (int net_id = 0; net_id < num_nets; ++net_id) {
        const Edge* edge = network_->getEdge(net_id);
        int num_pins = edge->getNumPins();
        if (num_pins <= 1) continue;

        // HPWL using Network
        Rectangle box1;
        float net_xl = std::numeric_limits<float>::max();
        float net_xh = std::numeric_limits<float>::lowest();
        float net_yl = std::numeric_limits<float>::max();
        float net_yh = std::numeric_limits<float>::lowest();

        for (const Pin* pin : edge->getPins()) {
            const Node* node = pin->getNode();
            double px = node->getLeft() + 0.5 * node->getWidth() + pin->getOffsetX();
            double py = node->getBottom() + 0.5 * node->getHeight() + pin->getOffsetY();
            box1.addPt(px, py);

            net_xl = std::min(net_xl, static_cast<float>(px));
            net_xh = std::max(net_xh, static_cast<float>(px));
            net_yl = std::min(net_yl, static_cast<float>(py));
            net_yh = std::max(net_yh, static_cast<float>(py));
        }

        double hpwl1 = box1.getWidth() + box1.getHeight();
        total_original_hpwl += hpwl1;

        // HPWL using flattened data
        float flat_xl = std::numeric_limits<float>::max();
        float flat_xh = std::numeric_limits<float>::lowest();
        float flat_yl = std::numeric_limits<float>::max();
        float flat_yh = std::numeric_limits<float>::lowest();

        for (int i = flat_net2pin_start_map[net_id]; i < flat_net2pin_start_map[net_id + 1]; ++i) {
            int pin_id = flat_net2pin_map[i];
            int node_id = pin2node_map[pin_id];

            float x_loc = x[node_id] + 0.5f * node_size_x[node_id] + pin_offset_x[pin_id];
            float y_loc = y[node_id] + 0.5f * node_size_y[node_id] + pin_offset_y[pin_id];

            flat_xl = std::min(flat_xl, x_loc);
            flat_xh = std::max(flat_xh, x_loc);
            flat_yl = std::min(flat_yl, y_loc);
            flat_yh = std::max(flat_yh, y_loc);

            // Only validate raw left/bottom and pin offset
            const Pin* pin = network_->getPin(pin_id);
            const Node* node = pin->getNode();

            float expected_left = node->getLeft();
            float expected_bottom = node->getBottom();
            float expected_offset_x = pin->getOffsetX();
            float expected_offset_y = pin->getOffsetY();

            float dx = std::abs(expected_left - x[node_id]);
            float dy = std::abs(expected_bottom - y[node_id]);
            float dox = std::abs(expected_offset_x - pin_offset_x[pin_id]);
            float doy = std::abs(expected_offset_y - pin_offset_y[pin_id]);

            if (dx > 1e-3 || dy > 1e-3 || dox > 1e-4 || doy > 1e-4) {
                printf("[Mismatch] pin_id %d node_id %d\n", pin_id, node_id);
                printf("  Expected pos: (%.6f, %.6f), Actual: (%.6f, %.6f), Δx=%.6f, Δy=%.6f\n",
                       expected_left, expected_bottom, x[node_id], y[node_id], dx, dy);
                printf("  Expected offset: (%.6f, %.6f), Actual: (%.6f, %.6f), Δx=%.6f, Δy=%.6f\n",
                       expected_offset_x, expected_offset_y, pin_offset_x[pin_id], pin_offset_y[pin_id], dox, doy);
            }
        }

        float hpwl2 = (flat_xh - flat_xl) + (flat_yh - flat_yl);
        total_flattened_hpwl += hpwl2;

        float diff = std::abs(hpwl1 - hpwl2);
        if (diff > 1e-2) {
            printf("Net %d: HPWL mismatch — Original: %.6f, Flattened: %.6f, Δ = %.6f\n",
                   net_id, hpwl1, hpwl2, diff);
            printf("  Network BBox : [%.3f, %.3f] x [%.3f, %.3f]\n", net_xl, net_xh, net_yl, net_yh);
            printf("  Flattened BBox: [%.3f, %.3f] x [%.3f, %.3f]\n", flat_xl, flat_xh, flat_yl, flat_yh);
        }
    }

    double rel_diff = std::abs(total_original_hpwl - total_flattened_hpwl) / total_original_hpwl * 100.0;
    printf("Total Original HPWL : %.6f\n", total_original_hpwl);
    printf("Total Flattened HPWL: %.6f\n", total_flattened_hpwl);
    printf("Relative difference : %.6f%%\n", rel_diff);
}

void DetailedPlaceDB::createNetInfo() {
  flat_net2pin_map.resize(num_pins);        // pin IDs, flattened
  std::vector<int> flat_net2pin_map_index(num_pins);  // corresponding net IDs
  flat_net2pin_start_map.resize(num_nets + 1);  // end offset per net

  int ptr = 0;
  int lastIdx = 0;
  flat_net2pin_start_map[0] = 0;
  for (int i = 0; i < network_->getNumEdges(); i++) {
    Edge* edge = network_->getEdge(i);
    assert(i == edge_id);
    int edge_id = edge->getId();
    for (auto& pin : edge->getPins()) {
      flat_net2pin_map[ptr] = pin->getId();        
      flat_net2pin_map_index[ptr] = edge_id;        
      ptr++;
    }
    lastIdx += edge->getPins().size();
    flat_net2pin_start_map[edge_id + 1] = lastIdx;
  }
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
  region_boxes_size = num_rects * 4;
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
    lastIdx += region->getRects().size();
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