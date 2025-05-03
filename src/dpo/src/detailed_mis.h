///////////////////////////////////////////////////////////////////////////////
// BSD 3-Clause License
//
// Copyright (c) 2021, Andrew Kennings
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// * Neither the name of the copyright holder nor the names of its
//   contributors may be used to endorse or promote products derived from
//   this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#pragma once

////////////////////////////////////////////////////////////////////////////////
// Includes.
////////////////////////////////////////////////////////////////////////////////
#include <map>
#include <string>
#include <vector>

#include "detailed_db_cuda.cuh"

namespace dpo {

struct SizedBinIndex {
    int size_id;
    int bin_id;
};

template <typename T>
struct IndependentSetMatchingState {
    typedef T type;
    typedef int cost_type;

    int* ordered_nodes = nullptr;
    Space<T>* spaces = nullptr;  ///< array of cell spaces, each cell only consider the space on its left side except
                                 ///< for the left and right boundary
    int num_node_sizes;          ///< number of cell sizes considered
    int* independent_sets = nullptr;       ///< independent sets, length of batch_size*set_size
    int* independent_set_sizes = nullptr;  ///< size of each independent set
    int* selected_maximal_independent_set = nullptr;  ///< storing the selected maximum independent set
    int* select_scratch = nullptr;                    ///< temporary storage for selection kernel
    int num_selected;                                 ///< maximum independent set size
    int* device_num_selected;                         ///< maximum independent set size

    double* net_hpwls;  ///< HPWL for each net, use integer to get consistent values

    int* selected_markers = nullptr;  ///< must be int for cub to compute prefix sum
    unsigned char* dependent_markers = nullptr;
    int* independent_set_empty_flag = nullptr;  ///< a stopping flag for maximum independent set
    int num_independent_sets;  ///< host copy

    cost_type* cost_matrices = nullptr;       ///< cost matrices batch_size*set_size*set_size
    cost_type* cost_matrices_copy = nullptr;  ///< temporary copy of cost matrices
    int* solutions = nullptr;                 ///< batch_size*set_size
    char* auction_scratch = nullptr;          ///< temporary memory for auction solver
    char* stop_flags = nullptr;               ///< record stopping status from auction solver
    T* orig_x = nullptr;                      ///< original locations of cells for applying solutions
    T* orig_y = nullptr;
    cost_type* orig_costs = nullptr;      ///< original costs
    cost_type* solution_costs = nullptr;  ///< solution costs
    Space<T>* orig_spaces = nullptr;      ///< original spaces of cells for apply solutions

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
    T skip_threshold;            ///< ignore connections if cells are far apart
};

////////////////////////////////////////////////////////////////////////////////
// Forward declarations.
////////////////////////////////////////////////////////////////////////////////
class Architecture;
class DetailedMgr;
class Network;
class Node;
class RoutingParams;

////////////////////////////////////////////////////////////////////////////////
// Classes.
////////////////////////////////////////////////////////////////////////////////
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
  DetailedMis(Architecture* arch, Network* network, RoutingParams* rt);
  virtual ~DetailedMis();

  void run(DetailedMgr* mgrPtr, DetailedPlaceData& db, const std::string& command);
  void run(DetailedMgr* mgrPtr, DetailedPlaceData& db, std::vector<std::string>& args);

 private:
  struct Bucket;

  void place();
  void collectMovableCells();
  void colorCells();
  void buildGrid();
  void clearGrid();
  void populateGrid();
  bool gatherNeighbours(Node* ndi);
  void solveMatch();
  double getHpwl(const Node* ndi, double xi, double yi);
  double getDisp(const Node* ndi, double xi, double yi);

 public:
  /* DetailedMisParams _params; */

  DetailedMgr* mgrPtr_ = nullptr;

  Architecture* arch_;
  Network* network_;
  RoutingParams* rt_;

  std::vector<Node*> candidates_;
  std::vector<bool> movable_;
  std::vector<int> colors_;
  std::vector<Node*> neighbours_;

  // Grid used for binning and locating cells.
  std::vector<std::vector<Bucket*>> grid_;
  int dimW_ = 0;
  int dimH_ = 0;
  double stepX_ = 0;
  double stepY_ = 0;
  std::map<Node*, Bucket*> cellToBinMap_;

  std::vector<int> timesUsed_;

  // Other.
  int skipEdgesLargerThanThis_ = 100;
  int maxProblemSize_ = 32;
  int traversal_ = 0;
  bool useSameSize_ = true;
  bool useSameColor_ = true;
  int maxTimesUsed_ = 2;
  Objective obj_ = DetailedMis::Hpwl;
};

}  // namespace dpo
