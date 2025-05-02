////////////////////////////////////////////////////////////////////////////////
// Description:
// An implementation of maximum independent set matching to reduce either
// wirelength of displacement.
//
// The idea is to color the nodes (for wirelength).  Then, one can solve
// a matching problem to optimize for wirelength.  Nodes with the same
// color do not share nets so they can be repositioned without worsening
// wirelength.  Note that for displacement optimization, colors are not
// needed.
//
// There are likely many improvements which can be made to this code
// regarding the selection of nodes, etc.

#include "detailed_mis.h"
#include <curand.h>
#include <curand_kernel.h>

#include "mis_utils/apply_solution.cuh"
#include "mis_utils/auction.cuh"
#include "mis_utils/collect_independent_sets.cuh"
#include "mis_utils/cost_matrix_construction.cuh"
#include "mis_utils/cpu_state.cuh"
#include "mis_utils/maximal_independent_set.cuh"
#include "mis_utils/shuffle.cuh"

#include <lemon/cost_scaling.h>
#include <lemon/cycle_canceling.h>
#include <lemon/list_graph.h>
#include <lemon/network_simplex.h>
#include <lemon/preflow.h>
#include <lemon/smart_graph.h>

#include <boost/tokenizer.hpp>
#include <queue>
#include <vector>

#include "architecture.h"
#include "color.h"
#include "detailed_manager.h"
#include "detailed_segment.h"
#include "network.h"
#include "rectangle.h"
#include "router.h"
#include "utl/Logger.h"

using utl::DPO;

namespace dpo {

#define DETERMINISTIC

#define NUM_NODE_SIZES 64  ///< number of different cell sizes

template <typename T>
__global__ void iota(T* a, int n) {
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x) {
        a[i] = i;
    }
}

__global__ void cost_matrix_init(int* cost_matrix, int set_size) {
    for (int i = blockIdx.x; i < set_size; i += gridDim.x) {
        for (int j = threadIdx.x; j < set_size; j += blockDim.x) {
            cost_matrix[i * set_size + j] = (i == j) ? 0 : cuda::numeric_limits<int>::max();
        }
    }
}

template <typename T>
__global__ void print_global(T* a, int n) {
    unsigned int tid = threadIdx.x;
    unsigned int bid = blockIdx.x;
    if (tid == 0 && bid == 0) {
        printf("[%d]\n", n);
        for (int i = 0; i < n; ++i) {
            printf("%g ", (double)a[i]);
        }
        printf("\n");
    }
}

template <typename T>
__global__ void print_cost_matrix(const T* cost_matrix, int set_size, bool major) {
    unsigned int tid = threadIdx.x;
    unsigned int bid = blockIdx.x;
    if (tid == 0 && bid == 0) {
        printf("[%dx%d]\n", set_size, set_size);
        for (int r = 0; r < set_size; ++r) {
            for (int c = 0; c < set_size; ++c) {
                if (major)  // column major
                {
                    printf("%g ", (double)cost_matrix[c * set_size + r]);
                } else {
                    printf("%g ", (double)cost_matrix[r * set_size + c]);
                }
            }
            printf("\n");
        }
        printf("\n");
    }
}

template <typename T>
__global__ void print_solution(const T* solution, int n) {
    unsigned int tid = threadIdx.x;
    unsigned int bid = blockIdx.x;
    if (tid == 0 && bid == 0) {
        printf("[%d]\n", n);
        for (int i = 0; i < n; ++i) {
            printf("%g ", (double)solution[i]);
        }
        printf("\n");
    }
}

void construct_spaces(DetailedPlaceData& db,
                      const float* host_x,
                      const float* host_y,
                      const float* host_node_size_x,
                      const float* host_node_size_y,
                      std::vector<Space<float>>& host_spaces,
                      int num_threads) {
    std::vector<std::vector<int>> row2node_map(db.num_sites_y);
    db.make_row2node_map(host_x, host_y, host_node_size_x, host_node_size_y, db.num_nodes, row2node_map);
    // construct spaces
    host_spaces.resize(db.num_nodes);
    for (int i = 0; i < db.num_sites_y; ++i) {
        for (unsigned int j = 0; j < row2node_map[i].size(); ++j) {
            auto const& row2nodes = row2node_map[i];
            int node_id = row2nodes[j];
            auto& space = host_spaces[node_id]; // this line is an error
            if (node_id < db.num_movable_nodes) {
                auto left_bound = db.xl;
                if (j) {
                    left_bound = host_x[node_id];
                }
                space.xl = ceilDiv(left_bound - db.xl, db.site_width) * db.site_width + db.xl;

                auto right_bound = db.xh;
                if (j + 1 < row2nodes.size()) {
                    int right_node_id = row2nodes[j + 1];
                    right_bound = min(right_bound, host_x[right_node_id]);
                }
                // space.xh = right_bound;
                // NOTE: some designs' fixed nodes are not placed on site (e.g. mgc_edit_dist_a),
                //       fix these cases by aligning them to site
                // FIXME: need regression
                space.xh = std::floor(right_bound);
                space.xh = floorDiv(space.xh - db.xl, db.site_width) * db.site_width + db.xl; 
            }
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
struct DetailedMis::Bucket
{
  void clear() { nodes_.clear(); }

  std::deque<Node*> nodes_;
  double xmin_ = 0.0;
  double xmax_ = 0.0;
  double ymin_ = 0.0;
  double ymax_ = 0.0;
  int i_ = 0;
  int j_ = 0;
  int travId_ = 0;
};

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedMis::DetailedMis(Architecture* arch,
                         Network* network,
                         RoutingParams* rt)
    : arch_(arch), network_(network), rt_(rt)
{
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedMis::~DetailedMis()
{
  clearGrid();
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::run(DetailedMgr* mgrPtr, DetailedPlaceData& db, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, db, args);
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::run(DetailedMgr* mgrPtr, DetailedPlaceData& db, std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgrPtr_ = mgrPtr;

  int passes = 1;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    } else if (args[i] == "-d") {
      obj_ = DetailedMis::Disp;
    }
  }
  tol = std::max(tol, 0.01);
  passes = std::max(passes, 1);

  int num_bins_x = 16;
  int num_bins_y = 16;
  int batch_size = 32;
  int set_size = maxProblemSize_;

  db.set_num_bins(num_bins_x, num_bins_y);
  // fix random seed
  std::srand(1000);

  IndependentSetMatchingState<float> state;

  // initialize host database
  DetailedPlaceCPUDB<float> host_db;
  init_cpu_db(db, host_db);

  state.batch_size = batch_size;
  state.set_size = set_size;
  state.cost_matrix_size = state.set_size * state.set_size;
  state.num_bins = db.num_bins_x * db.num_bins_y;
  state.num_moved = 0;
  state.large_number = ((db.xh - db.xl) + (db.yh - db.yl)) * set_size;
  state.skip_threshold = ((db.xh - db.xl) + (db.yh - db.yl)) * 0.01;
  state.auction_max_eps = 10.0;
  state.auction_min_eps = 1.0;
  state.auction_factor = 0.1;
  state.auction_max_iterations = 9999;

  checkCuda(cudaMemcpy(host_db.x.data(), db.x, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(cudaMemcpy(host_db.y.data(), db.y, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));
  std::vector<Space<float>> host_spaces(db.num_nodes);
  construct_spaces(db,
                    host_db.x.data(),
                    host_db.y.data(),
                    host_db.node_size_x.data(),
                    host_db.node_size_y.data(),
                    host_spaces,
                    db.num_threads);

  // initialize cuda state

  allocateCopyCuda(state.spaces, host_spaces.data(), db.num_nodes);
  allocateCuda(state.ordered_nodes, db.num_movable_nodes, int);
  iota<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(state.ordered_nodes, db.num_movable_nodes);
  allocateCuda(state.independent_sets, state.batch_size * state.set_size, int);
  allocateCuda(state.independent_set_sizes, state.batch_size, int);
  allocateCuda(state.selected_maximal_independent_set, db.num_movable_nodes, int);
  allocateCuda(state.select_scratch, db.num_movable_nodes, int);
  allocateCuda(state.device_num_selected, 1, int);
  allocateCuda(state.orig_x, state.batch_size * state.set_size, float);
  allocateCuda(state.orig_y, state.batch_size * state.set_size, float);
  allocateCuda(state.orig_spaces, state.batch_size * state.set_size, Space<float>);
  allocateCuda(state.selected_markers, db.num_nodes, int);
  allocateCuda(state.dependent_markers, db.num_nodes, unsigned char);
  allocateCuda(state.independent_set_empty_flag, 1, int);
  allocateCuda(state.cost_matrices,
                state.batch_size * state.set_size * state.set_size,
                float);
  allocateCuda(state.cost_matrices_copy,
                state.batch_size * state.set_size * state.set_size,
                float);
  allocateCuda(state.solutions, state.batch_size * state.set_size, int);
  allocateCuda(
      state.orig_costs, state.batch_size * state.set_size, float);
  allocateCuda(state.solution_costs,
                state.batch_size * state.set_size,
                float);
  allocateCuda(state.net_hpwls, db.num_nets, double);
  allocateCopyCuda(state.device_num_moved, &state.num_moved, 1);

  init_auction<float>(state.batch_size, state.set_size, state.auction_scratch, state.stop_flags);

  Shuffler<int, unsigned int> shuffler(2023ULL, state.ordered_nodes, db.num_movable_nodes);

  // initialize host state
  IndependentSetMatchingCPUState<float> host_state;
  init_cpu_state(db, state, host_state);

  // initialize kmeans state
  KMeansState<float> kmeans_state;
  init_kmeans(db, state, kmeans_state);

  std::vector<float> hpwls(passes + 1);
  hpwls[0] = compute_total_hpwl(db, db.x, db.y, state.net_hpwls);
  printf("[INFO GPU-DPO] initial hpwl %g\n", hpwls[0]);

  for (int p = 1; p <= passes; p++) {
    shuffler();
    checkCuda(cudaDeviceSynchronize());

    maximal_independent_set(db, state);
    checkCuda(cudaDeviceSynchronize());

    collect_independent_sets(db, state, kmeans_state, host_db, host_state);
    checkCuda(cudaDeviceSynchronize());

    cost_matrix_construction(db, state);
    checkCuda(cudaDeviceSynchronize());

    // solve independent sets
    // print_cost_matrix<<<1, 1>>>(state.cost_matrices + state.cost_matrix_size*3, state.set_size, 0);
    linear_assignment_auction(state.cost_matrices,
                              state.solutions,
                              state.num_independent_sets,
                              state.set_size,
                              state.auction_scratch,
                              state.stop_flags,
                              state.auction_max_eps,
                              state.auction_min_eps,
                              state.auction_factor,
                              state.auction_max_iterations);
    checkCuda(cudaDeviceSynchronize());
    // print_solution<<<1, 1>>>(state.solutions + state.set_size*3, state.set_size);

    // apply solutions
    apply_solution(db, state);
    checkCuda(cudaDeviceSynchronize());

    hpwls[p] = compute_total_hpwl(db, db.x, db.y, state.net_hpwls);
    if ((p % (max(passes / 10, 1))) == 0 || p == passes) {
      printf("[INFO GPU-DPO] iteration %d, target hpwl %g, delta %g(%g%%), %d independent sets, moved %g%% cells",
                    p,
                    hpwls[p],
                    hpwls[p] - hpwls[0],
                    (hpwls[p] - hpwls[0]) / hpwls[0] * 100,
                    state.num_independent_sets,
                    state.num_moved / (double)db.num_movable_nodes * 100);
    }
  }

  // destroy state
  cudaFree(state.spaces);
  cudaFree(state.ordered_nodes);
  cudaFree(state.independent_sets);
  cudaFree(state.independent_set_sizes);
  cudaFree(state.selected_maximal_independent_set);
  cudaFree(state.select_scratch);
  cudaFree(state.device_num_selected);
  cudaFree(state.net_hpwls);
  cudaFree(state.cost_matrices);
  cudaFree(state.cost_matrices_copy);
  cudaFree(state.solutions);
  cudaFree(state.orig_costs);
  cudaFree(state.solution_costs);
  cudaFree(state.orig_x);
  cudaFree(state.orig_y);
  cudaFree(state.orig_spaces);
  cudaFree(state.selected_markers);
  cudaFree(state.dependent_markers);
  cudaFree(state.independent_set_empty_flag);
  cudaFree(state.device_num_moved);
  destroy_auction(state.auction_scratch, state.stop_flags);
  destroy_kmeans(kmeans_state);
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::place()
{
  // Populate the grid.  Used for searching.
  populateGrid();

  timesUsed_.resize(network_->getNumNodes());
  std::fill(timesUsed_.begin(), timesUsed_.end(), 0);

  // Select candidates and solve matching problem.  Note that we need to do
  // something to make this more efficient, otherwise we will solve way too
  // many problems for larger circuits.  I think one effective idea is to
  // keep track of how many problems a candidate cell has been involved in;
  // if it has been involved is >= a certain number of problems, it has "had
  // some chance" to be moved, so skip it.
  mgrPtr_->shuffle(candidates_);
  for (Node* ndi : candidates_) {  // Pick a candidate as a seed.
    // Skip seed if it has been used already.
    if (timesUsed_[ndi->getId()] >= maxTimesUsed_) {
      continue;
    }

    // Get other cells within the vicinity.
    if (!gatherNeighbours(ndi)) {
      continue;
    }

    // Solve the flow.
    solveMatch();

    // Increment times each node has been used.
    for (const Node* ndj : neighbours_) {
      ++timesUsed_[ndj->getId()];
    }

    // Update grid?  Or, do we need to even bother?
    ;
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::collectMovableCells()
{
  candidates_.clear();
  candidates_.insert(candidates_.end(),
                     mgrPtr_->getSingleHeightCells().begin(),
                     mgrPtr_->getSingleHeightCells().end());
  for (size_t i = 2; i < mgrPtr_->getNumMultiHeights(); i++) {
    candidates_.insert(candidates_.end(),
                       mgrPtr_->getMultiHeightCells(i).begin(),
                       mgrPtr_->getMultiHeightCells(i).end());
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::colorCells()
{
  colors_.resize(network_->getNumNodes());
  std::fill(colors_.begin(), colors_.end(), -1);

  movable_.resize(network_->getNumNodes());
  std::fill(movable_.begin(), movable_.end(), false);
  for (const Node* ndi : candidates_) {
    movable_[ndi->getId()] = true;
  }

  Graph gr(network_->getNumNodes());
  for (int e = 0; e < network_->getNumEdges(); e++) {
    const Edge* edi = network_->getEdge(e);

    const int numPins = edi->getNumPins();
    if (numPins <= 1 || numPins > skipEdgesLargerThanThis_) {
      continue;
    }

    for (int pi = 0; pi < edi->getNumPins(); pi++) {
      const Pin* pini = edi->getPins()[pi];
      const Node* ndi = pini->getNode();
      if (!movable_[ndi->getId()]) {
        continue;
      }

      for (int pj = pi + 1; pj < edi->getNumPins(); pj++) {
        const Pin* pinj = edi->getPins()[pj];
        const Node* ndj = pinj->getNode();
        if (!movable_[ndj->getId()]) {
          continue;
        }
        if (ndj == ndi) {
          continue;
        }

        gr.addEdge(ndi->getId(), ndj->getId());
      }
    }
  }

  // The actual coloring.
  gr.greedyColoring();

  std::vector<int> hist;
  for (int i = 0; i < network_->getNumNodes(); i++) {
    const Node* ndi = network_->getNode(i);

    const int color = gr.getColor(i);
    if (color < 0 || color >= gr.getNumColors()) {
      mgrPtr_->internalError("Unable to color cells during matching");
    }
    if (movable_[ndi->getId()]) {
      colors_[ndi->getId()] = color;

      if (color >= hist.size()) {
        hist.resize(color + 1, 0);
      }
      ++hist[color];
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::buildGrid()
{
  // Builds a coarse grid over the placement region for locating cells.
  traversal_ = 0;

  const double xmin = arch_->getMinX();
  const double xmax = arch_->getMaxX();
  const double ymin = arch_->getMinY();
  const double ymax = arch_->getMaxY();

  // Design each grid bin to hold a few hundred cells.  Do this based on the
  // average width and height of the cells.
  double avgH = 0.;
  double avgW = 0.;
  for (const Node* ndi : candidates_) {
    avgH += ndi->getHeight();
    avgW += ndi->getWidth();
  }
  avgH /= (double) candidates_.size();
  avgW /= (double) candidates_.size();

  stepX_ = avgW * std::sqrt(maxProblemSize_);
  stepY_ = avgH * std::sqrt(maxProblemSize_);

  dimW_ = (int) std::ceil((xmax - xmin) / stepX_);
  dimH_ = (int) std::ceil((ymax - ymin) / stepY_);

  clearGrid();
  grid_.resize(dimW_);
  for (int i = 0; i < dimW_; i++) {
    grid_[i].resize(dimH_);
    for (int j = 0; j < dimH_; j++) {
      auto bucket = new Bucket;
      bucket->xmin_ = xmin + (i) *stepX_;
      bucket->xmax_ = xmin + (i + 1) * stepX_;
      bucket->ymin_ = ymin + (j) *stepY_;
      bucket->ymax_ = ymin + (j + 1) * stepY_;
      bucket->i_ = i;
      bucket->j_ = j;
      bucket->travId_ = traversal_;
      grid_[i][j] = bucket;
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::populateGrid()
{
  // Inserts movable cells into the grid.

  for (size_t i = 0; i < grid_.size(); i++) {
    for (size_t j = 0; j < grid_[i].size(); j++) {
      grid_[i][j]->clear();
    }
  }

  const double xmin = arch_->getMinX();
  const double ymin = arch_->getMinY();

  // Insert cells into the constructed grid.
  cellToBinMap_.clear();
  for (Node* ndi : candidates_) {
    const double y = ndi->getBottom() + 0.5 * ndi->getHeight();
    const double x = ndi->getLeft() + 0.5 * ndi->getWidth();

    const int j = std::max(std::min((int) ((y - ymin) / stepY_), dimH_ - 1), 0);
    const int i = std::max(std::min((int) ((x - xmin) / stepX_), dimW_ - 1), 0);

    grid_[i][j]->nodes_.push_back(ndi);
    cellToBinMap_[ndi] = grid_[i][j];
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::clearGrid()
// Clear out any old grid.  The dimensions of the grid are also stored in the
// class...
{
  for (auto& row : grid_) {
    for (auto bucket : row) {
      delete bucket;
    }
    row.clear();
  }
  grid_.clear();
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
bool DetailedMis::gatherNeighbours(Node* ndi)
{
  const double singleRowHeight = arch_->getRow(0)->getHeight();

  neighbours_.clear();
  neighbours_.push_back(ndi);

  // Scan the grid structure gathering up cells which are compatible with the
  // current cell.

  auto it = cellToBinMap_.find(ndi);
  if (it == cellToBinMap_.end()) {
    return false;
  }

  const int spanned_i = std::lround(ndi->getHeight() / singleRowHeight);

  std::queue<Bucket*> Q;
  Q.push(it->second);
  ++traversal_;
  while (!Q.empty()) {
    Bucket* currPtr = Q.front();
    Q.pop();

    if (currPtr->travId_ == traversal_) {
      continue;
    }
    currPtr->travId_ = traversal_;

    // Scan all the cells in this bucket.  If they are compatible with the
    // original cell, then add them to the neighbour list.
    for (Node* ndj : currPtr->nodes_) {
      // Check to make sure the cell is not the original, that they have
      // the same region, that they have the same size (if applicable),
      // and that they have the same color (if applicable).

      // diff nodes
      if (ndj == ndi) {
        continue;
      }

      // Must be the same color to avoid sharing nets.
      if (useSameColor_ && colors_[ndi->getId()] != colors_[ndj->getId()]) {
        continue;
      }

      // Must be the same size.
      if (useSameSize_
          && (ndi->getWidth() != ndj->getWidth()
              || ndi->getHeight() != ndj->getHeight())) {
        continue;
      }

      // Must be in the same region.
      if (ndj->getRegionId() != ndi->getRegionId()) {
        continue;
      }

      // Must span the same number of rows and also be voltage compatible.
      if (ndi->getBottomPower() != ndj->getBottomPower()
          || ndi->getTopPower() != ndj->getTopPower()
          || spanned_i != std::lround(ndj->getHeight() / singleRowHeight)) {
        continue;
      }

      // If compatible, include this current cell.
      neighbours_.push_back(ndj);
    }

    if (neighbours_.size() >= maxProblemSize_) {
      break;
    }

    // Add more bins to the queue if we have not yet collected enough cells.
    if (currPtr->i_ > 0) {
      Q.push(grid_[currPtr->i_ - 1][currPtr->j_]);
    }
    if (currPtr->i_ + 1 < dimW_) {
      Q.push(grid_[currPtr->i_ + 1][currPtr->j_]);
    }
    if (currPtr->j_ > 0) {
      Q.push(grid_[currPtr->i_][currPtr->j_ - 1]);
    }
    if (currPtr->j_ + 1 < dimH_) {
      Q.push(grid_[currPtr->i_][currPtr->j_ + 1]);
    }
  }
  return true;
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void DetailedMis::solveMatch()
{
  if (neighbours_.size() <= 1) {
    return;
  }
  const std::vector<Node*>& nodes = neighbours_;

  const int nNodes = (int) nodes.size();
  const int nSpots = (int) nodes.size();

  // Original position of cells.
  std::vector<std::pair<int, int>> pos(nNodes);
  // Original segment assignment of cells.
  std::vector<std::vector<DetailedSeg*>> seg(nNodes);
  for (size_t i = 0; i < nodes.size(); i++) {
    Node* ndi = nodes[i];

    pos[i] = std::make_pair(ndi->getLeft(), ndi->getBottom());
    seg[i] = mgrPtr_->getReverseCellToSegs(ndi->getId());  // copy!
  }

  lemon::ListDigraph g;
  std::vector<lemon::ListDigraph::Node> nodeForCell;
  std::vector<lemon::ListDigraph::Node> nodeForSpot;
  nodeForCell.resize(nNodes);
  nodeForSpot.resize(nNodes);
  for (size_t i = 0; i < nodes.size(); i++) {
    nodeForCell[i] = g.addNode();
    nodeForSpot[i] = g.addNode();
  }
  lemon::ListDigraph::Node supplyNode = g.addNode();
  lemon::ListDigraph::Node demandNode = g.addNode();

  // Hook up the graph.
  lemon::ListDigraph::ArcMap<int> l_i(g);  // Lower bound on flow.
  lemon::ListDigraph::ArcMap<int> u_i(g);  // Upper bound on flow.
  lemon::ListDigraph::ArcMap<int> c_i(g);  // Cost of flow.

  std::map<lemon::ListDigraph::Arc, std::pair<int, int>> reverseMap;

  double icost;
  for (int i = 0; i < nNodes; i++) {
    // Supply to node.
    lemon::ListDigraph::Arc arc_sv = g.addArc(supplyNode, nodeForCell[i]);
    l_i[arc_sv] = 0;
    u_i[arc_sv] = 1;
    c_i[arc_sv] = 0;

    // Spot to demand.
    lemon::ListDigraph::Arc arc_vt = g.addArc(nodeForSpot[i], demandNode);
    l_i[arc_vt] = 0;
    u_i[arc_vt] = 1;
    c_i[arc_vt] = 0;

    // Nodes to spots.
    const Node* ndi = nodes[i];
    for (int j = 0; j < nSpots; j++) {
      // Determine the cost of assigning cell "ndi" to the
      // current position.  Note that we might want to
      // skip this location if it violates the maximum
      // displacement limit.  We _never_ prevent a cell
      // from being assigned to its original position as
      // this guarantees a solution!
      if (i != j) {
        double dx = std::fabs(pos[j].first - ndi->getOrigLeft());
        if ((int) std::ceil(dx) > mgrPtr_->getMaxDisplacementX()) {
          continue;
        }
        double dy = std::fabs(pos[j].second - ndi->getOrigBottom());
        if ((int) std::ceil(dy) > mgrPtr_->getMaxDisplacementY()) {
          continue;
        }
      }

      // Okay to assign the cell to this location.
      if (obj_ == DetailedMis::Hpwl) {
        icost = getHpwl(ndi,
                        pos[j].first + 0.5 * ndi->getWidth(),
                        pos[j].second + 0.5 * ndi->getHeight());
      } else {
        icost = getDisp(ndi,
                        pos[j].first + 0.5 * ndi->getWidth(),
                        pos[j].second + 0.5 * ndi->getHeight());
      }

      // Node to spot.
      lemon::ListDigraph::Arc arc_vu = g.addArc(nodeForCell[i], nodeForSpot[j]);
      l_i[arc_vu] = 0;
      u_i[arc_vu] = 1;
      c_i[arc_vu] = icost > std::numeric_limits<int>::max()
                        ? std::numeric_limits<int>::max()
                        : static_cast<int>(icost);

      reverseMap[arc_vu] = std::make_pair(i, j);
    }
  }
  // Try max flow.
  lemon::Preflow<lemon::ListDigraph> preflow(g, u_i, supplyNode, demandNode);
  preflow.run();
  const int maxFlow = preflow.flowValue();
  if (maxFlow != nNodes) {
    return;
  }
  // Find mincost flow.
  lemon::NetworkSimplex<lemon::ListDigraph> mincost(g);
  mincost.lowerMap(l_i);
  mincost.upperMap(u_i);
  mincost.costMap(c_i);
  mincost.stSupply(supplyNode, demandNode, maxFlow);
  // lemon::CycleCanceling<lemon::ListDigraph>::ProblemType ret = mincost.run();
  lemon::NetworkSimplex<lemon::ListDigraph>::ProblemType ret = mincost.run();
  if (ret != lemon::NetworkSimplex<lemon::ListDigraph>::OPTIMAL) {
    return;
  }

  // Get the solution and assign nodes to new spots.  We also need to update the
  // assignment of cells to segments!  I _believe_ it should be fine to go cell
  // by cell and remove, reposition and update segment assignments one-by-one.
  //
  // This is somewhat tricky.  We need to use the target spot to figure out the
  // segments into which the cell needs to be replaced.

  lemon::ListDigraph::ArcMap<int> flow(g);
  mincost.flowMap(flow);

  for (lemon::ListDigraph::ArcMap<int>::ItemIt it(flow); it != lemon::INVALID;
       ++it) {
    if (g.target(it) != demandNode && g.source(it) != supplyNode
        && mincost.flow(it) != 0) {
      auto it1 = reverseMap.find(it);
      if (reverseMap.end() == it1) {
        mgrPtr_->internalError("Unable to interpret flow during matching");
      }

      const int i = it1->second.first;
      const int j = it1->second.second;

      // If cell "i" is assigned to location "i", it means that it has not
      // moved. We don't need to remove and reinsert it...

      Node* ndi = nodes[i];
      const Node* ndj = nodes[j];

      const int spanned_i = arch_->getCellHeightInRows(ndi);
      const int spanned_j = arch_->getCellHeightInRows(ndj);

      if (ndi != ndj) {
        if (spanned_i != spanned_j || ndi->getWidth() != ndj->getWidth()
            || ndi->getHeight() != ndj->getHeight()) {
          mgrPtr_->internalError("Unable to interpret flow during matching");
        }

        // Remove cell "i" from its old segments.
        std::vector<DetailedSeg*>& old_segs = seg[i];
        if (spanned_i != old_segs.size()) {
          // This means an error someplace else...
          mgrPtr_->internalError("Unable to interpret flow during matching");
        }
        for (const DetailedSeg* segPtr : old_segs) {
          const int segId = segPtr->getSegId();
          mgrPtr_->removeCellFromSegment(ndi, segId);
        }

        // Update the postion of cell "i".
        ndi->setLeft(pos[j].first);
        ndi->setBottom(pos[j].second);

        // Determine new segments and add cell "i" to its new segments.
        const std::vector<DetailedSeg*>& new_segs = seg[j];
        if (spanned_i != new_segs.size()) {
          // Not setup for non-same size stuff right now.
          mgrPtr_->internalError("Unable to interpret flow during matching");
        }
        for (const DetailedSeg* segPtr : new_segs) {
          const int segId = segPtr->getSegId();
          mgrPtr_->addCellToSegment(ndi, segId);
        }
      }
    }
  }
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
double DetailedMis::getDisp(const Node* ndi, double xi, double yi)
{
  // Compute displacement of cell ndi if placed at (xi,y1) from its orig pos.

  // Specified target is cell center.  Need to offset.
  xi -= 0.5 * ndi->getWidth();
  yi -= 0.5 * ndi->getHeight();
  const double dx = std::fabs(xi - ndi->getOrigLeft());
  const double dy = std::fabs(yi - ndi->getOrigBottom());
  return dx + dy;
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
double DetailedMis::getHpwl(const Node* ndi, double xi, double yi)
{
  // Compute the HPWL of nets connected to ndi assuming ndi is at the
  // specified (xi,yi).

  double hpwl = 0.;
  Rectangle box;
  for (int pi = 0; pi < ndi->getNumPins(); pi++) {
    const Pin* pini = ndi->getPins()[pi];

    const Edge* edi = pini->getEdge();

    const int npins = edi->getNumPins();
    if (npins <= 1 || npins > skipEdgesLargerThanThis_) {
      continue;
    }

    box.reset();
    for (int pj = 0; pj < edi->getNumPins(); pj++) {
      const Pin* pinj = edi->getPins()[pj];

      const Node* ndj = pinj->getNode();

      const double x
          = (ndj == ndi)
                ? (xi + pinj->getOffsetX())
                : (ndj->getLeft() + 0.5 * ndj->getWidth() + pinj->getOffsetX());
      const double y = (ndj == ndi) ? (yi + pinj->getOffsetY())
                                    : (ndj->getBottom() + 0.5 * ndj->getHeight()
                                       + pinj->getOffsetY());

      box.addPt(x, y);
    }
    if (box.xmax() >= box.xmin() && box.ymax() >= box.ymin()) {
      hpwl += (box.getWidth() + box.getHeight());
    }
  }

  return hpwl;
}

}  // namespace dpo
