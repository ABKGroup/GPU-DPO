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

  for (int pin_id = 0; pin_id < num_pins; ++pin_id) {
    const Pin* pin = network_->getPin(pin_id);
    pin_offset_x[pin_id] = static_cast<float>(pin->getOffsetX());
    pin_offset_y[pin_id] = static_cast<float>(pin->getOffsetY());
  }

  int ptr = 0;
  int lastIdx = 0;
  flat_node2pin_start_map[0] = 0;
  for (int i = 0; i < network_->getNumNodes(); i++) {
    Node* node = network_->getNode(i);
    int node_id = node->getId();
    for (auto& pin : node->getPins()) {
      flat_node2pin_map[ptr] = pin->getId();
      flat_node2pin_map_index[ptr] = node_id;
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

void DetailedPlaceDB::compareFlattenedAndNetworkHPWL()
{
  std::ofstream log("net_pin_detailed_comparison_log.txt");
  if (!log) {
      std::cerr << "Failed to open output file.\n";
      return;
  }

  double total_original_hpwl = 0.0;
  double total_flattened_hpwl = 0.0;

  for (int net_id = 0; net_id < num_nets; ++net_id) {
      const Edge* edge = network_->getEdge(net_id);
      int num_pins = edge->getNumPins();
      if (num_pins <= 1) continue;

      log << "Net ID: " << net_id << "\n";

      // --- Network pins ---
      std::vector<int> network_pin_ids;
      std::vector<int> network_node_ids;
      std::vector<std::pair<double, double>> network_offsets;

      log << "Network pins:\n";
      for (const Pin* pin : edge->getPins()) {
          int pin_id = pin->getId();
          int node_id = pin->getNode()->getId();
          double offset_x = pin->getOffsetX();
          double offset_y = pin->getOffsetY();

          network_pin_ids.push_back(pin_id);
          network_node_ids.push_back(node_id);
          network_offsets.emplace_back(offset_x, offset_y);

          log << "  Pin " << pin_id
              << " — Node: " << node_id
              << ", Offset: (" << offset_x << ", " << offset_y << ")\n";
      }

      // --- Flattened pins ---
      std::vector<int> flat_pin_ids;
      std::vector<int> flat_node_ids;
      std::vector<std::pair<float, float>> flat_offsets;

      log << "Flattened pins:\n";
      for (int i = flat_net2pin_start_map[net_id]; i < flat_net2pin_start_map[net_id + 1]; ++i) {
          int pin_id = flat_net2pin_map[i];
          int node_id = pin2node_map[pin_id];
          float offset_x = pin_offset_x[pin_id];
          float offset_y = pin_offset_y[pin_id];

          flat_pin_ids.push_back(pin_id);
          flat_node_ids.push_back(node_id);
          flat_offsets.emplace_back(offset_x, offset_y);

          log << "  Pin " << pin_id
              << " — Node: " << node_id
              << ", Offset: (" << offset_x << ", " << offset_y << ")\n";
      }

      // --- Consistency check ---
      bool mismatch = false;

      if (network_pin_ids.size() != flat_pin_ids.size()) {
          log << "[Mismatch] Pin count mismatch!\n";
          mismatch = true;
      } else {
          for (size_t i = 0; i < network_pin_ids.size(); ++i) {
              int npid = network_pin_ids[i];
              int fpid = flat_pin_ids[i];
              int nnid = network_node_ids[i];
              int fnid = flat_node_ids[i];
              double nox = network_offsets[i].first;
              double noy = network_offsets[i].second;
              float fox = flat_offsets[i].first;
              float foy = flat_offsets[i].second;

              float dox = std::abs(nox - fox);
              float doy = std::abs(noy - foy);

              if (npid != fpid || nnid != fnid || dox > 1e-4 || doy > 1e-4) {
                  log << "[Mismatch] Pin " << i << " — "
                      << "NetPinID=" << npid << ", FlatPinID=" << fpid << " | "
                      << "NetNodeID=" << nnid << ", FlatNodeID=" << fnid << " | "
                      << "NetOffset=(" << nox << ", " << noy << "), "
                      << "FlatOffset=(" << fox << ", " << foy << ")\n";
                  mismatch = true;
              }
          }
      }

      if (!mismatch) {
          log << "[OK] All pin details match.\n";
      }

      log << "--------------------------\n";
  }

  log.close();

    FILE* log_file = fopen("net_pin_mapping_debug.txt", "w");
    if (!log_file) {
        perror("Failed to open log file");
        return;
    }
    
    for (int net_id = 0; net_id < num_nets; ++net_id) {
      const Edge* edge = network_->getEdge(net_id);
      int num_pins = edge->getNumPins();
      if (num_pins <= 1) continue;

      // Log Network pins
      fprintf(log_file, "Net ID %d (Network pins): ", net_id);
      for (const Pin* pin : edge->getPins()) {
          fprintf(log_file, "%d ", pin->getId());
      }
      fprintf(log_file, "\n");

      // Log Flattened pins
      fprintf(log_file, "Net ID %d (Flattened pins): ", net_id);
      for (int i = flat_net2pin_start_map[net_id]; i < flat_net2pin_start_map[net_id + 1]; ++i) {
          int pin_id = flat_net2pin_map[i];
          fprintf(log_file, "%d ", pin_id);
      }
      fprintf(log_file, "\n");

      // --- HPWL computation continues below as before ---

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
          Pin* pin = network_->getPin(pin_id);
          Node* node = pin->getNode();

          int expected_left = node->getLeft();
          int expected_bottom = node->getBottom();
          double expected_offset_x = pin->getOffsetX();
          double expected_offset_y = pin->getOffsetY();

          float dx = std::abs(expected_left - (int)x[node_id]);
          float dy = std::abs(expected_bottom - (int)y[node_id]);
          float dox = std::abs(expected_offset_x - (double)pin_offset_x[pin_id]);
          float doy = std::abs(expected_offset_y - (double)pin_offset_y[pin_id]);

          if (dox > 1e-3) {
              fprintf(log_file, "[Offset Mismatch] pin_id %d node_id %d\n", pin_id, node_id);
              fprintf(log_file, "  Expected offset: (%.6f, %.6f), Actual: (%.6f, %.6f), Δx=%.6f, Δy=%.6f\n",
                      expected_offset_x, expected_offset_y, pin_offset_x[pin_id], pin_offset_y[pin_id], dox, doy);
          }
      }

      float hpwl2 = (flat_xh - flat_xl) + (flat_yh - flat_yl);
      total_flattened_hpwl += hpwl2;
  }

  double rel_diff = std::abs(total_original_hpwl - total_flattened_hpwl) / total_original_hpwl * 100.0;
  fprintf(log_file, "Total Original HPWL : %.6f\n", total_original_hpwl);
  fprintf(log_file, "Total Flattened HPWL: %.6f\n", total_flattened_hpwl);
  fprintf(log_file, "Relative difference : %.6f%%\n", rel_diff);

  fclose(log_file);
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