// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include "detailed_global.cuh"

#include <algorithm>
#include <boost/tokenizer.hpp>
#include <cmath>
#include <cstddef>
#include <string>
#include <vector>
#include <cstdio>

#include "detailed_manager.h"
#include "infrastructure/Objects.h"
#include "objective/detailed_hpwl.h"
#include "utl/Logger.h"

namespace dpl {

using utl::DPL;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedGlobalSwap::DetailedGlobalSwap(Architecture* arch, Network* network)
    : DetailedGenerator("global swap"),
      mgr_(nullptr),
      arch_(arch),
      network_(network),
      skipNetsLargerThanThis_(100),
      traversal_(0),
      attempts_(0),
      moves_(0),
      swaps_(0)
{
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedGlobalSwap::DetailedGlobalSwap() : DetailedGlobalSwap(nullptr, nullptr)
{
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::run(DetailedMgr* mgrPtr,
                             std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgr_ = mgrPtr;
  arch_ = mgr_->getArchitecture();
  network_ = mgr_->getNetwork();

  int passes = 1;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    }
  }
  passes = std::max(passes, 1);
  tol = std::max(tol, 0.01);

  int64_t last_hpwl, curr_hpwl, init_hpwl;
  uint64_t hpwl_x, hpwl_y;

  curr_hpwl = Utility::hpwl(network_, hpwl_x, hpwl_y);
  init_hpwl = curr_hpwl;
  for (int p = 1; p <= passes; p++) {
    last_hpwl = curr_hpwl;

    // XXX: Actually, global swapping is nothing more than random
    // greedy improvement in which the move generating is done
    // using this object to generate a target which is the optimal
    // region for each candidate cell.
    globalSwap();

    curr_hpwl = Utility::hpwl(network_, hpwl_x, hpwl_y);

    mgr_->getLogger()->info(DPL,
                            306,
                            "Pass {:3d} of global swaps; hpwl is {:.6e}.",
                            p,
                            (double) curr_hpwl);

    if (std::abs(curr_hpwl - last_hpwl) / (double) last_hpwl <= tol) {
      break;
    }
  }
  double curr_imp = (((init_hpwl - curr_hpwl) / (double) init_hpwl) * 100.);
  mgr_->getLogger()->info(DPL,
                          307,
                          "End of global swaps; objective is {:.6e}, "
                          "improvement is {:.2f} percent.",
                          (double) curr_hpwl,
                          curr_imp);
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::globalSwap()
{
  // Nothing for than random greedy improvement with only a hpwl objective
  // and done such that every candidate cell is considered once!!!

  traversal_ = 0;
  edgeMask_.resize(network_->getNumEdges());
  std::fill(edgeMask_.begin(), edgeMask_.end(), 0);

  mgr_->resortSegments();

  // Get candidate cells.
  std::vector<Node*> candidates = mgr_->getSingleHeightCells();
  mgr_->shuffle(candidates);

  // Wirelength objective.
  DetailedHPWL hpwlObj(network_);
  hpwlObj.init(mgr_, nullptr);  // Ignore orientation.

  double currHpwl = hpwlObj.curr();
  double nextHpwl = 0.;
  // Consider each candidate cell once.
  for (auto ndi : candidates) {
    if (!generate(ndi)) {
      continue;
    }

    double delta = hpwlObj.delta(mgr_->getJournal());

    nextHpwl = currHpwl - delta;  // -delta is +ve is less.

    if (nextHpwl <= currHpwl) {
      mgr_->acceptMove();
      currHpwl = nextHpwl;
    } else {
      mgr_->rejectMove();
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::getRange(Node* nd, odb::Rect& nodeBbox)
{
  // Determines the median location for a node.

  Edge* ed;
  unsigned mid;

  Pin* pin;
  unsigned t = 0;

  DbuX xmin = arch_->getMinX();
  DbuX xmax = arch_->getMaxX();
  DbuY ymin = arch_->getMinY();
  DbuY ymax = arch_->getMaxY();

  xpts_.clear();
  ypts_.clear();
  for (int n = 0; n < nd->getNumPins(); n++) {
    pin = nd->getPins()[n];

    ed = pin->getEdge();

    nodeBbox.mergeInit();

    int numPins = ed->getNumPins();
    if (numPins <= 1) {
      continue;
    }
    if (numPins > skipNetsLargerThanThis_) {
      continue;
    }
    if (!calculateEdgeBB(ed, nd, nodeBbox)) {
      continue;
    }

    // We've computed an interval for the pin.  We need to alter it to work for
    // the cell center. Also, we need to avoid going off the edge of the chip.
    nodeBbox.set_xlo(std::min(
        std::max(xmin.v, nodeBbox.xMin() - pin->getOffsetX().v), xmax.v));
    nodeBbox.set_xhi(std::max(
        std::min(xmax.v, nodeBbox.xMax() - pin->getOffsetX().v), xmin.v));
    nodeBbox.set_ylo(std::min(
        std::max(ymin.v, nodeBbox.yMin() - pin->getOffsetY().v), ymax.v));
    nodeBbox.set_yhi(std::max(
        std::min(ymax.v, nodeBbox.yMax() - pin->getOffsetY().v), ymin.v));

    // Record the location and pin offset used to generate this point.

    xpts_.push_back(nodeBbox.xMin());
    xpts_.push_back(nodeBbox.xMax());

    ypts_.push_back(nodeBbox.yMin());
    ypts_.push_back(nodeBbox.yMax());

    ++t;
    ++t;
  }

  // If, for some weird reason, we didn't find anything connected, then
  // return false to indicate that there's nowhere to move the cell.
  if (t <= 1) {
    return false;
  }

  // Get the median values.
  mid = t >> 1;

  std::sort(xpts_.begin(), xpts_.end());
  std::sort(ypts_.begin(), ypts_.end());

  nodeBbox.set_xlo(xpts_[mid - 1]);
  nodeBbox.set_xhi(xpts_[mid]);

  nodeBbox.set_ylo(ypts_[mid - 1]);
  nodeBbox.set_yhi(ypts_[mid]);

  return true;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::calculateEdgeBB(Edge* ed, Node* nd, odb::Rect& bbox)
{
  // Computes the bounding box of an edge.  Node 'nd' is the node to SKIP.
  DbuX curX;
  DbuY curY;

  bbox.mergeInit();

  int count = 0;
  for (Pin* pin : ed->getPins()) {
    auto other = pin->getNode();
    if (other == nd) {
      continue;
    }
    curX = other->getCenterX() + pin->getOffsetX().v;
    curY = other->getCenterY() + pin->getOffsetY().v;

    bbox.set_xlo(std::min(curX.v, bbox.xMin()));
    bbox.set_xhi(std::max(curX.v, bbox.xMax()));
    bbox.set_ylo(std::min(curY.v, bbox.yMin()));
    bbox.set_yhi(std::max(curY.v, bbox.yMax()));

    ++count;
  }

  return (count == 0) ? false : true;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::generate(Node* ndi)
{
  double yi = ndi->getBottom().v + 0.5 * ndi->getHeight().v;
  double xi = ndi->getLeft().v + 0.5 * ndi->getWidth().v;

  // Determine optimal region.
  odb::Rect bbox;
  if (!getRange(ndi, bbox)) {
    // Failed to find an optimal region.
    return false;
  }
  if (xi >= bbox.xMin() && xi <= bbox.xMax() && yi >= bbox.yMin()
      && yi <= bbox.yMax()) {
    // If cell inside box, do nothing.
    return false;
  }

  // Observe displacement limit.  I suppose there are options.
  // If we cannot move into the optimal region, we could try
  // to move closer to it.  Or, we could just reject if we cannot
  // get into the optimal region.
  int dispX, dispY;
  mgr_->getMaxDisplacement(dispX, dispY);
  odb::Rect lbox(ndi->getLeft().v - dispX,
                 ndi->getBottom().v - dispY,
                 ndi->getLeft().v + dispX,
                 ndi->getBottom().v + dispY);
  if (lbox.xMax() <= bbox.xMin()) {
    bbox.set_xlo(ndi->getLeft().v);
    bbox.set_xhi(lbox.xMax());
  } else if (lbox.xMin() >= bbox.xMax()) {
    bbox.set_xlo(lbox.xMin());
    bbox.set_xhi(ndi->getLeft().v);
  } else {
    bbox.set_xlo(std::max(bbox.xMin(), lbox.xMin()));
    bbox.set_xhi(std::min(bbox.xMax(), lbox.xMax()));
  }
  if (lbox.yMax() <= bbox.yMin()) {
    bbox.set_ylo(ndi->getBottom().v);
    bbox.set_yhi(lbox.yMax());
  } else if (lbox.yMin() >= bbox.yMax()) {
    bbox.set_ylo(lbox.yMin());
    bbox.set_yhi(ndi->getBottom().v);
  } else {
    bbox.set_ylo(std::max(bbox.yMin(), lbox.yMin()));
    bbox.set_yhi(std::min(bbox.yMax(), lbox.yMax()));
  }

  if (mgr_->getNumReverseCellToSegs(ndi->getId()) != 1) {
    return false;
  }
  int si = mgr_->getReverseCellToSegs(ndi->getId())[0]->getSegId();

  // Position target so center of cell at center of box.
  DbuX xj{(int) std::floor(0.5 * (bbox.xMin() + bbox.xMax())
                           - 0.5 * ndi->getWidth().v)};
  DbuY yj{(int) std::floor(0.5 * (bbox.yMin() + bbox.yMax())
                           - 0.5 * ndi->getHeight().v)};

  // Row and segment for the destination.
  int rj = arch_->find_closest_row(yj);
  yj = DbuY{arch_->getRow(rj)->getBottom()};  // Row alignment.
  int sj = -1;
  for (int s = 0; s < mgr_->getNumSegsInRow(rj); s++) {
    DetailedSeg* segPtr = mgr_->getSegsInRow(rj)[s];
    if (xj >= segPtr->getMinX() && xj <= segPtr->getMaxX()) {
      sj = segPtr->getSegId();
      break;
    }
  }
  if (sj == -1) {
    return false;
  }
  if (ndi->getGroupId() != mgr_->getSegment(sj)->getRegId()) {
    return false;
  }

  if (mgr_->tryMove(ndi, ndi->getLeft(), ndi->getBottom(), si, xj, yj, sj)) {
    ++moves_;
    return true;
  }
  if (mgr_->trySwap(ndi, ndi->getLeft(), ndi->getBottom(), si, xj, yj, sj)) {
    ++swaps_;
    return true;
  }
  return false;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::init(DetailedMgr* mgr)
{
  mgr_ = mgr;
  arch_ = mgr->getArchitecture();
  network_ = mgr->getNetwork();

  traversal_ = 0;
  edgeMask_.resize(network_->getNumEdges());
  std::fill(edgeMask_.begin(), edgeMask_.end(), 0);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::generate(DetailedMgr* mgr,
                                  std::vector<Node*>& candidates)
{
  ++attempts_;

  mgr_ = mgr;
  arch_ = mgr->getArchitecture();
  network_ = mgr->getNetwork();

  Node* ndi = candidates[mgr_->getRandom(candidates.size())];

  return generate(ndi);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::stats()
{
  mgr_->getLogger()->info(
      DPL,
      334,
      "Generator {:s}, "
      "Cumulative attempts {:d}, swaps {:d}, moves {:5d} since last reset.",
      getName().c_str(),
      attempts_,
      swaps_,
      moves_);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::run(DetailedMgr* mgrPtr, GpuData& db_, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, db_, args);
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
template <int ThreadsPerBlock = 128>
__global__ void reduce_min_2d_cub(SwapCandidate* candidates,
                                  int max_num_elements) {
  typedef cub::BlockReduce<ItemWithIndex, ThreadsPerBlock> BlockReduce;

  __shared__ typename BlockReduce::TempStorage temp_storage;

  auto row_candidates = candidates + blockIdx.x * max_num_elements;

  ItemWithIndex thread_data;

  thread_data.value = cuda::numeric_limits<int>::max();
  thread_data.index = 0;
  for (int col = threadIdx.x; col < max_num_elements; col += ThreadsPerBlock) {
    int cost = row_candidates[col].cost;
    if (cost < thread_data.value) {
      thread_data.value = cost;
      thread_data.index = col;
    }
  }

  __syncthreads();

  // Compute the block-wide max for thread0
  ItemWithIndex aggregate = BlockReduce(temp_storage).Reduce(thread_data, ReduceMinOP(), max_num_elements);

  __syncthreads();

  if (threadIdx.x == 0) {
    row_candidates[0] = row_candidates[aggregate.index];
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
inline __device__ int compute_pair_hpwl_general(const int* __restrict__ flat_node2pin_start_map,
                                                  const int* __restrict__ flat_node2pin_map,
                                                  const int* __restrict__ pin2net_map,
                                                  const int xh,
                                                  const int yh,
                                                  const int xl,
                                                  const int yl,
                                                  const int* __restrict__ net_mask,
                                                  const int* __restrict__ flat_net2pin_start_map,
                                                  const int* __restrict__ flat_net2pin_map,
                                                  const int* __restrict__ pin2node_map,
                                                  const int* __restrict__ x,
                                                  const int* __restrict__ y,
                                                  const int* __restrict__ pin_offset_x,
                                                  const int* __restrict__ pin_offset_y,
                                                  int node_id,
                                                  int node_xl,
                                                  int node_yl,
                                                  int target_node_id,
                                                  int target_node_xl,
                                                  int target_node_yl,
                                                  int skip_node_id) {
  int cost = 0;
  int node2pin_id = flat_node2pin_start_map[node_id];
  const int node2pin_id_end = flat_node2pin_start_map[node_id + 1];
  for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
    int node_pin_id = flat_node2pin_map[node2pin_id];
    int net_id = pin2net_map[node_pin_id];
    Box box(xh, yh, xl, yl);
    int flag = net_mask[net_id];
    int net2pin_id = flat_net2pin_start_map[net_id];
    const int net2pin_id_end = flat_net2pin_start_map[net_id + 1] * flag;
    for (; net2pin_id < net2pin_id_end; ++net2pin_id) {
      int net_pin_id = flat_net2pin_map[net2pin_id];
      int other_node_id = pin2node_map[net_pin_id];
      int xxl = x[other_node_id];
      int yyl = y[other_node_id];
      flag &= (other_node_id != skip_node_id);
      int cond1 = (other_node_id == node_id);
      int cond2 = (other_node_id == target_node_id);
      xxl =
          cond1 * node_xl + cond2 * target_node_xl + (!(cond1 || cond2)) * xxl;
      yyl =
          cond1 * node_yl + cond2 * target_node_yl + (!(cond1 || cond2)) * yyl;
      // xxl+px
      xxl += pin_offset_x[net_pin_id];
      // yyl+py
      yyl += pin_offset_y[net_pin_id];
      box.xl = min(box.xl, xxl);
      box.xh = max(box.xh, xxl);
      box.yl = min(box.yl, yyl);
      box.yh = max(box.yh, yyl);
    }
    cost += (box.xh - box.xl + box.yh - box.yl) * flag;
    
  }
  return cost;
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
inline __device__ int compute_pair_hpwl_general_fast(PitchNestedVector<int>& node2net_map,
                                                       PitchNestedVector<NodePinPair>& net2nodepin_map,
                                                       const int xh,
                                                       const int yh,
                                                       const int xl,
                                                       const int yl,
                                                       const int* __restrict__ net_mask,
                                                       const int* __restrict__ x,
                                                       const int* __restrict__ y,
                                                       int node_id,
                                                       int node_xl,
                                                       int node_yl,
                                                       int target_node_id,
                                                       int target_node_xl,
                                                       int target_node_yl,
                                                       int skip_node_id) {
  int cost = 0;
  auto node2nets = node2net_map(node_id);
  for (int i = 0; i < node2net_map.size(node_id); ++i) {
    int net_id = node2nets[i];
    int flag = net_mask[net_id];
    auto net2nodepins = net2nodepin_map(net_id);
    Box box(xh, yh, xl, yl);

    int end = net2nodepin_map.size(net_id) * flag;
    for (int j = 0; j < end; ++j) {
      NodePinPair& node_pin_pair = net2nodepins[j];
      int other_node_id = node_pin_pair.node_id;

      flag &= (other_node_id != skip_node_id);

      int xxl = x[other_node_id];
      int yyl = y[other_node_id];
      int cond1 = (other_node_id == node_id);
      int cond2 = (other_node_id == target_node_id);
      xxl = cond1 * node_xl + cond2 * target_node_xl + (!(cond1 || cond2)) * xxl;
      yyl = cond1 * node_yl + cond2 * target_node_yl + (!(cond1 || cond2)) * yyl;

      xxl += node_pin_pair.pin_offset_x;
      yyl += node_pin_pair.pin_offset_y;
      box.xl = min(box.xl, xxl);
      box.xh = max(box.xh, xxl);
      box.yl = min(box.yl, yyl);
      box.yh = max(box.yh, yyl);
    }
    cost += (box.xh - box.xl + box.yh - box.yl) * flag;
  }
  return cost;
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__device__ int compute_positions_hint(const GpuData& db,
                                        const SwapState& state,
                                        SwapCandidate& cand,
                                        int node_xl,
                                        int node_yl,
                                        int node_width,
                                        Space& space) {
  // case I: two cells are horizontally abutting
  cand.node_xl[0][0] = node_xl;
  cand.node_yl[0][0] = node_yl;
  cand.node_xl[1][0] = db.x[cand.node_id[1]];
  cand.node_yl[1][0] = db.y[cand.node_id[1]];
  int target_node_width = db.node_size_x[cand.node_id[1]];
  auto target_space = db.align2site(state.spaces[cand.node_id[1]]);
  int cond = (space.xh >= target_space.xl);
  cond &= (target_space.xh >= space.xl);
  cond &= (cand.node_yl[0][0] == cand.node_yl[1][0]);
  if (cond) {
    // case I: abutting, not exactly abutting, there might be space
    // between two cells, this is a generalized case
    cond = (space.xl < target_space.xl);
    cand.node_xl[0][1] = cand.node_xl[1][0] + (target_node_width - node_width) * cond;
    cand.node_xl[1][1] = cand.node_xl[0][0] - (target_node_width - node_width) * (!cond);
  } else {
    // case II: not abutting
    cond = (space.xh < target_node_width + space.xl);
    cond |= (target_space.xh < node_width + target_space.xl);
    if (cond) {
      // some large number
      return cuda::numeric_limits<int>::max();
    }
    cand.node_xl[0][1] = cand.node_xl[1][0] + (target_node_width - node_width) / 2;
    cand.node_xl[1][1] = cand.node_xl[0][0] + (node_width - target_node_width) / 2;
    cand.node_xl[0][1] = db.align2site(cand.node_xl[0][1]);
    cand.node_xl[0][1] = max(cand.node_xl[0][1], target_space.xl);
    cand.node_xl[0][1] = min(cand.node_xl[0][1], target_space.xh - node_width);
    cand.node_xl[1][1] = db.align2site(cand.node_xl[1][1]);
    cand.node_xl[1][1] = max(cand.node_xl[1][1], space.xl);
    cand.node_xl[1][1] = min(cand.node_xl[1][1], space.xh - target_node_width);
  }
  cand.node_yl[0][1] = cand.node_yl[1][0];
  cand.node_yl[1][1] = cand.node_yl[0][0];

  return 0;
}


//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void compute_search_bins(GpuData db, SwapState state, int begin, int end) {
  for (int node_id = begin + blockIdx.x * blockDim.x + threadIdx.x; node_id < end;
       node_id += blockDim.x * gridDim.x) {
    // compute optimal region
    Box opt_box = (state.search_bin_strategy)
      ? db.compute_optimal_region(node_id, db.x, db.y, db.node_size_x, db.node_size_y)
      : Box(db.x[node_id],
                   db.y[node_id],
                   db.x[node_id] + db.node_size_x[node_id],
                   db.y[node_id] + db.node_size_y[node_id]);
    int cx = db.pos2bin_x(opt_box.center_x());
    int cy = db.pos2bin_y(opt_box.center_y());
    state.search_bins[node_id] = cx * db.num_bins_y + cy;
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void reset_state(GpuData db, SwapState state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    SwapCandidate& cand = state.candidates[i];
    cand.cost = 0;
    cand.node_id[0] = cuda::numeric_limits<int>::max();
    cand.node_id[1] = cuda::numeric_limits<int>::max();
    cand.node_xl[0][0] = 0;
    cand.node_xl[0][1] = 0;
    cand.node_yl[0][0] = 0;
    cand.node_yl[0][1] = 0;
    cand.node_xl[1][0] = 0;
    cand.node_xl[1][1] = 0;
    cand.node_yl[1][0] = 0;
    cand.node_yl[1][1] = 0;
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_movable_nodes; i += blockDim.x * gridDim.x) {
    state.node_markers[i] = 0;
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void check_state(GpuData db, SwapState state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_movable_nodes;
       i += blockDim.x * gridDim.x) {
    const BinMapIndex& bm_idx = state.node2bin_map[i];
    if (state.bin2node_map(bm_idx.bin_id, bm_idx.sub_id) != i) {
      printf("[E] node %d @ (%d, %d), bin [%d, %d], found %d\n", i,
             (int)db.x[i], (int)db.y[i], bm_idx.bin_id, bm_idx.sub_id,
             state.bin2node_map(bm_idx.bin_id, bm_idx.sub_id));
      assert(0);
    }
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    SwapCandidate& cand = state.candidates[i];
    if (cand.cost < 0 && (cand.node_id[0] >= db.num_movable_nodes ||
                          cand.node_id[1] >= db.num_movable_nodes)) {
      printf("[E] node %d, target_node %d, cost %d\n", cand.node_id[0],
             cand.node_id[1], (int)cand.cost);
      assert(0);
    }
    if (cand.cost < 0) {
      if (db.x[cand.node_id[0]] != cand.node_xl[0][0]) {
        printf("[E] node %d x %d node_xl %d\n", cand.node_id[0],
               (int)db.x[cand.node_id[0]], (int)cand.node_xl[0][0]);
      }
      if (db.y[cand.node_id[0]] != cand.node_yl[0][0]) {
        printf("[E] node %d y %d node_yl %d\n", cand.node_id[0],
               (int)db.y[cand.node_id[0]], (int)cand.node_yl[0][0]);
      }
      if (db.x[cand.node_id[1]] != cand.node_xl[1][0]) {
        printf("[E] node %d x %d target_node_xl %d\n", cand.node_id[1],
               (int)db.x[cand.node_id[1]], (int)cand.node_xl[1][0]);
      }
      if (db.y[cand.node_id[1]] != cand.node_yl[1][0]) {
        printf("[E] node %d y %d target_node_yl %d\n", cand.node_id[1],
               (int)db.y[cand.node_id[1]], (int)cand.node_yl[1][0]);
      }
      assert(db.x[cand.node_id[0]] == cand.node_xl[0][0]);
      assert(db.y[cand.node_id[0]] == cand.node_yl[0][0]);
      assert(db.x[cand.node_id[1]] == cand.node_xl[1][0]);
      assert(db.y[cand.node_id[1]] == cand.node_yl[1][0]);
    }
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void __launch_bounds__(256, 4)
    collect_candidates(GpuData db, SwapState state, int idx_bgn,
                       int idx_end) {
  // assume following inequality
  assert(gridDim.y == (idx_end - idx_bgn));
  assert(gridDim.x == 5);
  __shared__ int node_id;
  __shared__ int node_xl, node_yl, node_width;
  __shared__ Space space;
  __shared__ int max_num_candidates;
  __shared__ int bin_id;
  __shared__ const int* __restrict__ bin2nodes;
  __shared__ int num_nodes_in_bin;
  __shared__ float step_size;
  __shared__ int iters;
  __shared__ int block_offset;
  if (threadIdx.x == 0) {
    node_id = state.ordered_nodes[blockIdx.y + idx_bgn];
    node_xl = db.x[node_id];
    node_yl = db.y[node_id];
    node_width = db.node_size_x[node_id];
    space = db.align2site(state.spaces[node_id]);
    max_num_candidates = state.max_num_candidates / 5;

    block_offset =
        blockIdx.y * state.max_num_candidates + blockIdx.x * max_num_candidates;
    bin_id = state.search_bins[node_id];
    int bx = bin_id / db.num_bins_y;
    int by = bin_id - bx * db.num_bins_y;
    if (blockIdx.x == 1)  // left bin
    {
      if (bx > 0) {
        bin_id -= db.num_bins_y;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 2)  // bottom bin
    {
      if (by > 0) {
        bin_id -= 1;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 3)  // right bin
    {
      if (bx + 1 < db.num_bins_x) {
        bin_id += db.num_bins_y;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 4)  // top bin
    {
      if (by + 1 < db.num_bins_y) {
        bin_id += 1;
      } else {
        bin_id = -1;
      }
    }
    // else is center bin

    if (bin_id >= 0) {
      bin2nodes = state.bin2node_map(bin_id);
      num_nodes_in_bin =
          state.bin2node_map.size(bin_id) *
          (db.node_size_y[node_id] ==
           db.row_height);  // only consider single-row height cell
      step_size = max((float)num_nodes_in_bin / (float)max_num_candidates, (float)1);
      iters = min(max_num_candidates, num_nodes_in_bin);
    }
  }
  __syncthreads();
  SwapCandidate cand;
  cand.node_id[0] = node_id;
  if (bin_id >= 0) {
    for (int i = threadIdx.x; i < iters; i += blockDim.x) {
      cand.node_id[1] = bin2nodes[int(i * step_size)];
      int cond = (cand.node_id[0] != cand.node_id[1]);
      cond &= (db.node_size_y[cand.node_id[1]] == db.row_height);
      if (cond) {
        cand.cost = compute_positions_hint(db, state, cand, node_xl, node_yl,
                                           node_width, space);
        cond = (cand.cost == 0);
        if (cond) {
          state.candidates[block_offset + i] = cand;
        }
      }
    }
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void reset_candidate_costs(GpuData db,
                                      SwapState state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    state.candidates[i].cost = cuda::numeric_limits<int>::max();
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void check_candidate_costs(GpuData db,
                                      SwapState state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    auto const& cand = state.candidates[i];
    if (cand.cost < 0) {
      assert(cand.node_id[0] < db.num_movable_nodes &&
             cand.node_id[1] < db.num_movable_nodes);
    }
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void __launch_bounds__(256, 4)
    compute_candidate_cost(GpuData db, SwapState state) {
  extern __shared__ unsigned char cost_proxy[];
  __shared__ int num_candidates;
  int* cost = reinterpret_cast<int*>(cost_proxy);
  if (threadIdx.x == 0) {
    num_candidates = (state.max_num_candidates_all << 2);
  }
  __syncthreads();
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < num_candidates;
       i += blockDim.x * gridDim.x) {
    SwapCandidate& cand = state.candidates[i >> 2];
    int node_id_flag = ((threadIdx.x & 2) >> 1);
    int offset = (threadIdx.x & 1);
    int skip_node_id = cand.node_id[0] + INT_MIN * (!node_id_flag);
    if (cand.node_id[0] < db.num_movable_nodes &&
        cand.node_id[1] < db.num_movable_nodes) {
      int cost1 =
          (state.pair_hpwl_computing_strategy)
              ? compute_pair_hpwl_general_fast(
                    state.node2net_map, state.net2nodepin_map, db.xh, db.yh,
                    db.xl, db.yl, db.net_mask, db.x, db.y,
                    cand.node_id[node_id_flag],
                    cand.node_xl[node_id_flag][offset],
                    cand.node_yl[node_id_flag][offset],
                    cand.node_id[!node_id_flag],
                    cand.node_xl[!node_id_flag][offset],
                    cand.node_yl[!node_id_flag][offset], skip_node_id)
              : compute_pair_hpwl_general(
                    db.flat_node2pin_start_map, db.flat_node2pin_map,
                    db.pin2net_map, db.xh, db.yh, db.xl, db.yl, db.net_mask,
                    db.flat_net2pin_start_map, db.flat_net2pin_map,
                    db.pin2node_map, db.x, db.y, db.pin_offset_x,
                    db.pin_offset_y, cand.node_id[node_id_flag],
                    cand.node_xl[node_id_flag][offset],
                    cand.node_yl[node_id_flag][offset],
                    cand.node_id[!node_id_flag],
                    cand.node_xl[!node_id_flag][offset],
                    cand.node_yl[!node_id_flag][offset], skip_node_id);
      cost[threadIdx.x] = cost1;
    } else {
      cost[threadIdx.x] = 0;
    }
  }
  __syncthreads();
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < num_candidates;
       i += blockDim.x * gridDim.x) {
    SwapCandidate& cand = state.candidates[i >> 2];
    if ((threadIdx.x & 3) == 3)
    {
      // consider FENCE region
      if (db.num_regions &&
          ((cand.node_id[0] < db.num_movable_nodes &&
            !db.inside_fence(cand.node_id[0], cand.node_xl[0][1],
                             cand.node_yl[0][1])) ||
           (cand.node_id[1] < db.num_movable_nodes &&
            !db.inside_fence(cand.node_id[1], cand.node_xl[1][1],
                             cand.node_yl[1][1])))) {
        cand.cost = cuda::numeric_limits<int>::max(); // cost is infinite if not in fence
      } else {
        cand.cost = cost[threadIdx.x] - cost[threadIdx.x - 1] +
                    cost[threadIdx.x - 2] - cost[threadIdx.x - 3];  // else cost is difference of prev and next
      }
    }
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void apply_candidates(GpuData db, SwapState state, int num_candidates) {
  // overlap, edge spacing, and padding aware
  for (int i = 0; i < num_candidates; ++i) {
    const SwapCandidate& best_cand = state.candidates[i * state.max_num_candidates];

    if (best_cand.cost < 0 &&
        !(state.node_markers[best_cand.node_id[0]] || state.node_markers[best_cand.node_id[1]])) {
      int node_width = db.node_size_x[best_cand.node_id[0]];
      int target_node_width = db.node_size_x[best_cand.node_id[1]];
      Space& space = state.spaces[best_cand.node_id[0]];
      Space& target_space = state.spaces[best_cand.node_id[1]];

      if (best_cand.node_xl[0][1] >= target_space.xl && best_cand.node_xl[0][1] + node_width <= target_space.xh &&
          best_cand.node_xl[1][1] >= space.xl && best_cand.node_xl[1][1] + target_node_width <= space.xh) {
        state.node_markers[best_cand.node_id[0]] = 1;
        state.node_markers[best_cand.node_id[1]] = 1;

        BinMapIndex& bin_id = state.node2bin_map[best_cand.node_id[0]];
        BinMapIndex& target_bin_id = state.node2bin_map[best_cand.node_id[1]];
        RowMapIndex& row_id = state.node2row_map[best_cand.node_id[0]];
        RowMapIndex& target_row_id = state.node2row_map[best_cand.node_id[1]];
        int* row2nodes = state.row2node_map(row_id.row_id);
        int* target_row2nodes = state.row2node_map(target_row_id.row_id);

        db.x[best_cand.node_id[0]] = best_cand.node_xl[0][1];
        db.y[best_cand.node_id[0]] = best_cand.node_yl[0][1];
        db.x[best_cand.node_id[1]] = best_cand.node_xl[1][1];
        db.y[best_cand.node_id[1]] = best_cand.node_yl[1][1];
        int& bin2node_map_node_id = state.bin2node_map(bin_id.bin_id, bin_id.sub_id);
        int& bin2node_map_target_node_id = state.bin2node_map(target_bin_id.bin_id, target_bin_id.sub_id);
        device_swap(bin2node_map_node_id, bin2node_map_target_node_id);
        device_swap(bin_id, target_bin_id);

        {
          int neighbor_node_id = row2nodes[row_id.sub_id - 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xh = min(neighbor_space.xh, best_cand.node_xl[1][1]);
          }
          neighbor_node_id = row2nodes[row_id.sub_id + 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xl = max(neighbor_space.xl, best_cand.node_xl[1][1] + target_node_width);
          }
          neighbor_node_id = target_row2nodes[target_row_id.sub_id - 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xh = min(neighbor_space.xh, best_cand.node_xl[0][1]);
          }
          neighbor_node_id = target_row2nodes[target_row_id.sub_id + 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xl = max(neighbor_space.xl, best_cand.node_xl[0][1] + node_width);
          }
        }

        if ((best_cand.node_yl[0][0] == best_cand.node_yl[1][0]) && (space.xh >= target_space.xl) &&
            (target_space.xh >= space.xl)) {
          if (best_cand.node_xl[0][0] < best_cand.node_xl[1][0]) {
            space.xh = target_space.xh;
            target_space.xl = space.xl;
            space.xl = best_cand.node_xl[1][1] + target_node_width;
            target_space.xh = best_cand.node_xl[0][1];
          } else {
            target_space.xh = space.xh;
            space.xl = target_space.xl;
            target_space.xl = best_cand.node_xl[0][1] + node_width;
            space.xh = best_cand.node_xl[0][1];
          }
        } else {
          device_swap(space, target_space);
        }

        device_swap(row2nodes[row_id.sub_id], target_row2nodes[target_row_id.sub_id]);
        device_swap(row_id, target_row_id);
      }
    }
  }
}


//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void iota(int* ptr, int n) {
  // generate array from 0 to n-1
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x) {
    ptr[i] = i;
  }
}


//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void global_swap(GpuData& db, SwapState& state) {
  compute_search_bins<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state, 0, db.num_movable_nodes);
  checkCuda(cudaDeviceSynchronize());

  for (int i = 0; i < db.num_movable_nodes; i += state.batch_size) {
    // all results are stored in state.candidates
    int idx_bgn = i;
    int idx_end = min(i + state.batch_size, db.num_movable_nodes);
    reset_state<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state);
    dim3 grid(5, (idx_end - idx_bgn), 1);
    collect_candidates<<<grid, 256>>>(db, state, idx_bgn, idx_end);
    reset_candidate_costs<<<ceilDiv(state.max_num_candidates_all, 256), 256>>>(db, state);
    compute_candidate_cost<<<ceilDiv(state.max_num_candidates_all, 64), 64 * 4, 64 * 4 * sizeof(int)>>>(db, state);

    //check_state<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state);
    //check_candidate_costs<<<ceilDiv(state.max_num_candidates_all, 256), 256>>>(
    //    db, state);

    reduce_min_2d_cub<256><<<idx_end - idx_bgn, 256>>>(state.candidates, state.max_num_candidates);
    apply_candidates<<<1, 1>>>(db, state, idx_end - idx_bgn);
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void initNode2NetMap_kernel(PitchNestedVector<int> node2net_map, GpuData db, const int num_nodes) {
  const int node_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (node_id >= num_nodes) {
    return;
  }
  int num_elements = 0;
  int beg = db.flat_node2pin_start_map[node_id];
  int end = min((int)db.flat_node2pin_start_map[node_id + 1], beg + maxNodeDegree_);
  for (int node2pin_id = beg; node2pin_id < end; ++node2pin_id, ++num_elements) {
    if (num_elements < maxNodeDegree_)  
    {
      int node_pin_id = db.flat_node2pin_map[node2pin_id];
      int net_id = db.pin2net_map[node_pin_id];
      node2net_map.flat_element_map[node_id * maxNodeDegree_ + num_elements] = net_id;
    }
  }
  node2net_map.dim2_sizes[node_id] = num_elements;
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void initNode2NetMap(PitchNestedVector<int>& node2net_map, GpuData& db) {
  // allocate memory
  allocateCuda(node2net_map.flat_element_map, db.num_movable_nodes * maxNodeDegree_, int);
  allocateCuda(node2net_map.dim2_sizes, db.num_movable_nodes, unsigned int);
  node2net_map.size1 = db.num_movable_nodes;
  node2net_map.size2 = maxNodeDegree_;
  // init on GPU
  initNode2NetMap_kernel<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(node2net_map, db, db.num_movable_nodes);
  checkCuda(cudaDeviceSynchronize());
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void initNet2NodePinMap_kernel(PitchNestedVector<NodePinPair> net2nodepin_map,
                                          GpuData db,
                                          const int num_nets) {
  const int net_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (net_id >= num_nets) {
    return;
  }
  int num_elements = 0;
  int beg = db.flat_net2pin_start_map[net_id];
  int end = min((int)db.flat_net2pin_start_map[net_id + 1], beg + maxNetDegree_);
  for (int net2pin_id = beg; net2pin_id < end; ++net2pin_id, ++num_elements) {
    if (num_elements < maxNetDegree_)  // only consider maxNetDegree_ pins
    {
      int net_pin_id = db.flat_net2pin_map[net2pin_id];
      int px = db.pin_offset_x[net_pin_id];
      int py = db.pin_offset_y[net_pin_id];
      int node_id = db.pin2node_map[net_pin_id];
      NodePinPair& node_pin_pair =
          net2nodepin_map.flat_element_map[net_id * maxNetDegree_ + num_elements];
      node_pin_pair.node_id = node_id;
      node_pin_pair.pin_offset_x = px;
      node_pin_pair.pin_offset_y = py;
    }
  }
  net2nodepin_map.dim2_sizes[net_id] = num_elements;
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void initNet2NodePinMap(PitchNestedVector<NodePinPair>& net2nodepin_map, GpuData& db) {
  // allocate memory
  allocateCuda(net2nodepin_map.flat_element_map, db.num_nets * maxNetDegree_, NodePinPair);
  allocateCuda(net2nodepin_map.dim2_sizes, db.num_nets, unsigned int);
  net2nodepin_map.size1 = db.num_nets;
  net2nodepin_map.size2 = maxNetDegree_;
  // init on GPU
  initNet2NodePinMap_kernel<<<ceilDiv(db.num_nets, 512), 512>>>(net2nodepin_map, db, db.num_nets);
  checkCuda(cudaDeviceSynchronize());
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
__global__ void compute_num_nodes_in_bins(GpuData db, int* node_count_map) {
  for (int node_id = blockIdx.x * blockDim.x + threadIdx.x; node_id < db.num_movable_nodes;
       node_id += blockDim.x * gridDim.x) {
    int bx = db.pos2bin_x(db.x[node_id]);
    int by = db.pos2bin_y(db.y[node_id]);
    int bin_id = bx * db.num_bins_y + by;
    atomicAdd(node_count_map + bin_id, 1);
  }
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
int compute_max_num_nodes_per_bin(const GpuData& db) {
  int num_bins = db.num_bins_x * db.num_bins_y;
  int* node_count_map = nullptr;
  allocateCuda(node_count_map, num_bins, int);

  checkCuda(cudaMemset(node_count_map, 0, sizeof(int) * num_bins));
  compute_num_nodes_in_bins<<<ceilDiv(db.num_movable_nodes, 256), 256>>>(db, node_count_map);

  int* d_out = NULL;
  // Determine temporary device storage requirements
  void* d_temp_storage = NULL;
  size_t temp_storage_bytes = 0;
  cub::DeviceReduce::Max(d_temp_storage, temp_storage_bytes, node_count_map, d_out, num_bins);
  // Allocate temporary storage
  checkCuda(cudaMalloc(&d_temp_storage, temp_storage_bytes));
  checkCuda(cudaMalloc(&d_out, sizeof(int)));
  // Run max-reduction
  cub::DeviceReduce::Max(d_temp_storage, temp_storage_bytes, node_count_map, d_out, num_bins);
  // copy d_out to hpwl
  int max_num_nodes_per_bin = 0;
  checkCuda(cudaMemcpy(&max_num_nodes_per_bin, d_out, sizeof(int), cudaMemcpyDeviceToHost));
  cudaFree(d_temp_storage);
  cudaFree(d_out);
  cudaFree(node_count_map);

  return max_num_nodes_per_bin;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::run(DetailedMgr* mgrPtr, GpuData& db_,
                             std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgr_ = mgrPtr;

  int passes = 5;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    } else if (args[i] == "-batch" && i + 1 < args.size()) {
      batchSize_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "binX" && i + 1 < args.size()) {
      numBinsX_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "binY" && i + 1 < args.size()) {
      numBinsY_ = std::atoi(args[++i].c_str());
    }
  }
  passes = std::max(passes, 1);
  tol = std::max(tol, 0.01); 

  db_.set_num_bins(numBinsX_, numBinsY_);
  printf("[INFO GPU-DPO] bins %dx%d, bin sizes %gx%g, die size %d, %d, %d, %d\n",
         db_.num_bins_x,
         db_.num_bins_y,
         (float)db_.bin_size_x,
         (float)db_.bin_size_y,
         (int)db_.xl,
         (int)db_.yl,
         (int)db_.xh,
         (int)db_.yh);

  SwapState state;

  state.batch_size = batchSize_;
  int max_num_nodes_per_bin = compute_max_num_nodes_per_bin(db_);
  state.max_num_candidates = max_num_nodes_per_bin * 5;
  state.max_num_candidates_all = state.batch_size * state.max_num_candidates;
  printf("[INFO GPU-DPO] batch_size = %d, max_num_nodes_per_bin = %d, "
         "max_num_candidates = %d, max_num_candidates_all = %d\n",
         state.batch_size,
         max_num_nodes_per_bin,
         state.max_num_candidates,
         state.max_num_candidates_all);
  state.search_bin_strategy = 1;
  // use fast mode for small designs, because extra memory is required
  long estimate_memory_usage = db_.num_nodes * maxNodeDegree_ * sizeof(int)                 // size of node2net_map
                                + db_.num_nets * maxNetDegree_ * sizeof(NodePinPair)        // size of net2nodepin_map
      ;
  if (estimate_memory_usage < 4e9) {  // use 4GB as a switch threshold
    printf("[INFO GPU-DPO] Estimate memory usage = %ld, use fast pair HPWL "
           "computation strategy requires additional memory\n",
           estimate_memory_usage);
    state.search_bin_strategy = 1;
  } else {
    printf("[INFO GPU-DPO] Estimate memory usage = %ld, use general pair HPWL\n", state.search_bin_strategy);
    //state.search_bin_strategy = 0;
  }

  // std::srand(1000);

   // allocate temporary memory to CPU, add dummy cells for xl and xh
  std::vector<int> host_x(db_.num_nodes + 2);
  std::vector<int> host_y(db_.num_nodes + 2);
  std::vector<int> host_node_size_x(db_.num_nodes + 2);
  std::vector<int> host_node_size_y(db_.num_nodes + 2);
  host_x[db_.num_nodes] = db_.xl - 1;
  host_y[db_.num_nodes] = db_.yl;
  host_node_size_x[db_.num_nodes] = 1;
  host_node_size_y[db_.num_nodes] = db_.yh - db_.yl;
  host_x[db_.num_nodes + 1] = db_.xh;
  host_y[db_.num_nodes + 1] = db_.yl;
  host_node_size_x[db_.num_nodes + 1] = 1;
  host_node_size_y[db_.num_nodes + 1] = db_.yh - db_.yl;
  checkCuda(cudaMemcpy(host_x.data(), db_.x, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(cudaMemcpy(host_y.data(), db_.y, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(
      cudaMemcpy(host_node_size_x.data(), db_.node_size_x, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(
      cudaMemcpy(host_node_size_y.data(), db_.node_size_y, sizeof(int) * db_.num_nodes, cudaMemcpyDeviceToHost));

  // distribute cells to rows on host, copy cell locations from device to host
  std::vector<std::vector<int>> host_row2node_map(db_.num_sites_y);
  std::vector<RowMapIndex> host_node2row_map(db_.num_movable_nodes);
  std::vector<Space> host_spaces(db_.num_movable_nodes);
  db_.make_row2node_map_with_spaces(host_x.data(),
                                    host_y.data(),
                                    host_node_size_x.data(),
                                    host_node_size_y.data(),
                                    host_row2node_map,
                                    host_node2row_map,
                                    host_spaces,
                                    1);
  // distribute movable cells to bins on host, bin map is column-major
  std::vector<std::vector<int>> host_bin2node_map(db_.num_bins_x * db_.num_bins_y);
  std::vector<BinMapIndex> host_node2bin_map(db_.num_movable_nodes);
  db_.make_bin2node_map(host_x.data(),
                        host_y.data(),
                        host_node_size_x.data(),
                        host_node_size_y.data(),
                        host_bin2node_map,
                        host_node2bin_map);

  // initialize SwapState
  std::vector<int> host_ordered_nodes;
  host_ordered_nodes.reserve(db_.num_movable_nodes);
  // reorder such that a batch of cells are distributed to different bins
  int sub_id_counter = 0;
  while ((int)host_ordered_nodes.size() < db_.num_movable_nodes) {
    for (int i = 0; i < state.batch_size; ++i) {
      for (unsigned int j = i; j < host_bin2node_map.size(); j += state.batch_size) {
        auto const& bin2nodes = host_bin2node_map[j];
        if (sub_id_counter < bin2nodes.size()) {
          host_ordered_nodes.push_back(bin2nodes[sub_id_counter]);
        }
      }
    }
    ++sub_id_counter;
  }

  allocateCopyCuda(state.ordered_nodes, host_ordered_nodes.data(), db_.num_movable_nodes);
  state.row2node_map.initialize(host_row2node_map);
  allocateCopyCuda(state.node2row_map, host_node2row_map.data(), host_node2row_map.size());
  allocateCopyCuda(state.spaces, host_spaces.data(), host_spaces.size());
  state.bin2node_map.initialize(host_bin2node_map);
  allocateCopyCuda(state.node2bin_map, host_node2bin_map.data(), host_node2bin_map.size());

  allocateCuda(state.candidates, state.max_num_candidates_all, SwapCandidate);
  allocateCuda(state.search_bins, db_.num_movable_nodes, int);
  allocateCuda(state.net_hpwls, db_.num_nets, typename std::remove_pointer<decltype(state.net_hpwls)>::type);
  allocateCuda(state.node_markers, db_.num_movable_nodes, unsigned char);
  checkCuda(cudaMemset(state.node_markers, 0, sizeof(unsigned char) * db_.num_movable_nodes));

  if (state.pair_hpwl_computing_strategy) {
    initNode2NetMap(state.node2net_map, db_);
    initNet2NodePinMap(state.net2nodepin_map, db_);
  }

  int64_t last_hpwl, curr_hpwl, init_hpwl;

  curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);
  init_hpwl = curr_hpwl;
  for (int p = 1; p <= passes; p++) {
    last_hpwl = curr_hpwl;

    global_swap(db_, state);
    checkCuda(cudaDeviceSynchronize());

    curr_hpwl = compute_total_hpwl(db_, db_.x, db_.y, state.net_hpwls);

    printf("[INFO GPU-DPO] Pass %d of global swaps; hpwl is %d.\n", p, (int) curr_hpwl);

    // if (std::abs(curr_hpwl - last_hpwl) / (double) last_hpwl <= tol) {
    //   break;
    // }
  }
  double curr_imp = (((init_hpwl - curr_hpwl) / (double) init_hpwl) * 100.);
  printf("[INFO GPU-DPO] End of global swaps; objective is %d, "
            "improvement is %f percent.\n",
            (int) curr_hpwl,
            curr_imp);

  checkCuda(cudaDeviceSynchronize());

  // destroy SwapState
  cudaFree(state.ordered_nodes);
  state.row2node_map.destroy();
  cudaFree(state.node2row_map);
  cudaFree(state.spaces);
  state.bin2node_map.destroy();
  cudaFree(state.node2bin_map);
  cudaFree(state.candidates);
  cudaFree(state.search_bins);
  cudaFree(state.net_hpwls);
  cudaFree(state.node_markers);

  if (state.pair_hpwl_computing_strategy) {
    state.node2net_map.destroy();
    state.net2nodepin_map.destroy();
  }

  checkCuda(cudaDeviceSynchronize());
}

}  // namespace dpl
