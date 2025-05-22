// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <map>
#include <string>
#include <vector>

#include "infrastructure/Coordinates.h"
#include "infrastructure/GpuData.cuh"

#define DETERMINISTIC

#define NUM_NODE_SIZES 64

namespace dpl {
class Node;
class Architecture;
class DetailedMgr;
class Network;

struct SizedBinIndex {
  int size_id;
  int bin_id;
};

struct IndependentSetMatchingState {
  typedef int cost_type;

  int* ordered_nodes = nullptr;
  Space* spaces = nullptr;  ///< array of cell spaces, each cell only consider the space on its left side except
                                ///< for the left and right boundary
  int num_node_sizes;          ///< number of cell sizes considered
  int* independent_sets = nullptr;       ///< independent sets, length of batch_size*set_size
  int* independent_set_sizes = nullptr;  ///< size of each independent set
  int* selected_maximal_independent_set = nullptr;  ///< storing the selected maximum independent set
  int* select_scratch = nullptr;                    ///< temporary storage for selection kernel
  int num_selected;                                 ///< maximum independent set size
  int* device_num_selected;                         ///< maximum independent set size

  int* net_hpwls;  ///< HPWL for each net, use integer to get consistent values

  int* selected_markers = nullptr;  ///< must be int for cub to compute prefix sum
  unsigned char* dependent_markers = nullptr;
  int* independent_set_empty_flag = nullptr;  ///< a stopping flag for maximum independent set
  int num_independent_sets;  ///< host copy

  int* cost_matrices = nullptr;       ///< cost matrices batch_size*set_size*set_size
  int* cost_matrices_copy = nullptr;  ///< temporary copy of cost matrices
  int* solutions = nullptr;                 ///< batch_size*set_size
  char* auction_scratch = nullptr;          ///< temporary memory for auction solver
  char* stop_flags = nullptr;               ///< record stopping status from auction solver
  int* orig_x = nullptr;                      ///< original locations of cells for applying solutions
  int* orig_y = nullptr;
  int* orig_seg = nullptr;        ///< original segments of cells for applying solutions
  int* orig_costs = nullptr;      ///< original costs
  int* solution_costs = nullptr;  ///< solution costs
  Space* orig_spaces = nullptr;      ///< original spaces of cells for apply solutions

  int batch_size;  ///< pre-allocated number of independent sets
  int set_size;
  int cost_matrix_size;   ///< set_size*set_size
  int num_bins;           ///< num_bins_x*num_bins_y
  int* device_num_moved;  ///< device copy
  int num_moved;          ///< host copy, number of moved cells
  int large_number;       ///< a large number

  float auction_max_eps;       ///< maximum epsilon for auction solver
  float auction_min_eps;       ///< minimum epsilon for auction solver
  float auction_factor;        ///< decay factor for auction epsilon
  int auction_max_iterations;  ///< maximum iteration
  float skip_threshold;            ///< ignore connections if cells are far apart
};

class DetailedMisParams
{
 public:
  enum Strategy
  {
    KDTree = 0,
    Binning = 1,
    Colour = 2,
  };

  double _maxDifferenceInMetric = 0.03;  // How much we allow the routine to
                                         // reintroduce overlap into placement
  unsigned _maxNumNodes = 15;  // Only consider this many number of nodes for
                               // B&B (<= MAX_BB_NODES)
  unsigned _maxPasses = 1;     // Maximum number of B&B passes
  double _sizeTol = 1.1;       // Tolerance for what is considered same-size
  unsigned _skipNetsLargerThanThis = 50;  // Skip nets larger than this amount.
  Strategy _strategy = Binning;           // The type of strategy to consider
  bool _useSameSize = true;  // If 'false', cells can swap with approximately
                             // same-size locations
};

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
class DetailedMis
{
  // Flow-based solver for replacing nodes using matching.
  enum Objective
  {
    Hpwl,
    Disp
  };

 public:
  DetailedMis(Architecture* arch, Network* network);
  // virtual ~DetailedMis();

  void run(DetailedMgr* mgrPtr, GpuData& db_, const std::string& command);
  void run(DetailedMgr* mgrPtr, GpuData& db_, std::vector<std::string>& args);

 public:
  /* DetailedMisParams _params; */

  DetailedMgr* mgrPtr_ = nullptr;

  Architecture* arch_;
  Network* network_;

  // Other.
  int batchSize_ = 16;
  int numBinsX_ = 256;
  int numBinsY_ = 256;
  int setSize_ = 64;
};

}  // namespace dpl
