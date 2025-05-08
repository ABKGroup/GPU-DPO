// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <string>
#include <vector>

#include "detailed_generator.h"
#include "infrastructure/GpuData.cuh"

#define maxNodeDegree_ 20
#define maxNetDegree_ 100

namespace odb {
class Rect;
}
namespace dpl {
class Edge;
class Architecture;
class DetailedMgr;
class Network;
class GpuData;

struct __align__(16) SwapCandidate {
  int cost;
  int node_xl[2][2];  ///< [0][] for node, [1][] for target node, [][0] for old,
                      ///< [][1] for new
  int node_yl[2][2];
  int node_id[2];     ///< [0] for node, [1] for target node
};

struct SearchBinInfo {
  int cx;
  int cy;
};

struct __align__(16) NetPinPair {
  int net_id;
  int pin_offset_x;
  int pin_offset_y;
};

struct __align__(16) NodePinPair {
  int node_id;
  int pin_offset_x;
  int pin_offset_y;
};

struct SwapState {
  int* ordered_nodes = nullptr;

  Space* spaces = nullptr;

  PitchNestedVector<int> row2node_map;
  RowMapIndex* node2row_map = nullptr;

  PitchNestedVector<int> bin2node_map;
  BinMapIndex* node2bin_map = nullptr;

  // PitchNestedVector<NetPinPair<T> > node2netpin_map;
  PitchNestedVector<int> node2net_map;
  PitchNestedVector<NodePinPair> net2nodepin_map;

  int* search_bins = nullptr;
  int search_bin_strategy;  ///< how to compute search bins for eahc cell: 0 for
                            ///< cell bin, 1 for optimal region

  SwapCandidate* candidates;

  int* net_hpwls;  ///< HPWL for each net, use integer to get consistent values
  unsigned char* node_markers;  ///< markers for cells

  int batch_size;
  int max_num_candidates_per_row;
  int max_num_candidates;
  int max_num_candidates_all;

  int pair_hpwl_computing_strategy;  ///< 0: for the original node2pin_map and
                                     ///< net2pin_map; 1: for node2net_map and
                                     ///< net2node_map, which requires
                                     ///< additional memory
};

class DetailedGlobalSwap : public DetailedGenerator
{
 public:
  DetailedGlobalSwap(Architecture* arch, Network* network);
  DetailedGlobalSwap();

  // Interfaces for scripting.
  void run(DetailedMgr* mgrPtr, const std::string& command);
  void run(DetailedMgr* mgrPtr, std::vector<std::string>& args);

  void run(DetailedMgr* mgrPtr, GpuData& db_, const std::string& command);
  void run(DetailedMgr* mgrPtr, GpuData& db_, std::vector<std::string>& args);

  // Interface for move generation.
  bool generate(DetailedMgr* mgr, std::vector<Node*>& candidates) override;
  void stats() override;
  void init(DetailedMgr* mgr) override;

 private:
  void globalSwap();  // tries to avoid overlap.
  bool calculateEdgeBB(Edge* ed, Node* nd, odb::Rect& bbox);
  bool getRange(Node*, odb::Rect&);
  bool generate(Node* ndi);

  // Standard stuff.
  DetailedMgr* mgr_;
  Architecture* arch_;
  Network* network_;

  // Other.
  int skipNetsLargerThanThis_;
  std::vector<int> edgeMask_;
  int traversal_;

  std::vector<double> xpts_;
  std::vector<double> ypts_;

  // For use as a move generator.
  int attempts_;
  int moves_;
  int swaps_;

  int batchSize_ = 32;
  int numBinsX_ = 256;
  int numBinsY_ = 256;
};

}  // namespace dpl
