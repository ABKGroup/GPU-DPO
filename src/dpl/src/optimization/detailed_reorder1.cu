// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include "detailed_reorder.h"

#include <algorithm>
#include <cstddef>
#include <limits>
#include <string>
#include <omp.h>
#include <cuda_runtime.h>
#include <cuda.h>

#include "detailed_manager.h"
#include "infrastructure/architecture.h"
#include "infrastructure/detailed_segment.h"
#include "util/utility.h"
#include "utl/Logger.h"
#include "GpuData.cuh"

using utl::DPL;

// GPU data structures
struct ReorderInstance {
    int seg_id;
    int row_id;
    int start_idx;
    int end_idx;
    int num_cells;
    int node_ids[4]; // Since max window size is 4
    int left_limit;
    int right_limit;
};

struct ReorderState {
    int num_instances;
    int num_permutations;
    int K; // window size
    
    ReorderInstance* instances;
    int* permutations;
    int* costs;
    int* best_permute_id;
    
    void allocate(int num_inst, int num_perm) {
        allocateCuda(costs, num_inst * num_perm, int);
        allocateCuda(best_permute_id, num_inst, int);
    }
    
    void destroy() {
        cudaFree(instances);
        cudaFree(permutations);
        cudaFree(costs);
        cudaFree(best_permute_id);
    }
};

namespace dpl {

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
DetailedReorderer::DetailedReorderer(Architecture* arch, Network* network)
    : arch_(arch), network_(network)
{
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::run(DetailedMgr* mgrPtr, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, args);
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::run(DetailedMgr* mgrPtr,
                            const std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.

  mgrPtr_ = mgrPtr;

  windowSize_ = 3;

  int passes = 1;
  double tol = 0.01;
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-w" && i + 1 < args.size()) {
      windowSize_ = std::atoi(args[++i].c_str());
    } else if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    }
  }
  windowSize_ = std::min(4, std::max(2, windowSize_));
  tol = std::max(tol, 0.01);

  mgrPtr_->resortSegments();

  uint64_t hpwl_x, hpwl_y;
  int64_t curr_hpwl = Utility::hpwl(network_, hpwl_x, hpwl_y);  // change this to gpu style hpwl
  const int64_t init_hpwl = curr_hpwl;
  if (init_hpwl == 0) {
    return;
  }
  for (int p = 1; p <= passes; p++) {
    const int64_t last_hpwl = curr_hpwl;

    // change this to gpu style reordering
    reorder();

    curr_hpwl = Utility::hpwl(network_, hpwl_x, hpwl_y);

    mgrPtr_->getLogger()->info(DPL,
                               304,
                               "Pass {:3d} of reordering; objective is {:.6e}.",
                               p,
                               (double) curr_hpwl);
    if (last_hpwl == 0
        || std::abs(curr_hpwl - last_hpwl) / (double) last_hpwl <= tol) {
      // std::cout << "Terminating due to low improvement." << std::endl;
      break;
    }
  }
  mgrPtr_->resortSegments();
  const double curr_imp
      = (((init_hpwl - curr_hpwl) / (double) init_hpwl) * 100.);
  mgrPtr_->getLogger()->info(
      DPL,
      305,
      "End of reordering; objective is {:.6e}, improvement is {:.2f} percent.",
      (double) curr_hpwl,
      curr_imp);
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::reorder() {
    traversal_ = 0;
    edgeMask_.resize(network_->getNumEdges());
    std::fill(edgeMask_.begin(), edgeMask_.end(), traversal_);

    // Get independent segment groups
    auto segment_groups = group_independent_segments(mgrPtr_);

    // Create GPU state
    ReorderState state;
    state.K = windowSize_;

    // Generate all permutations
    std::vector<std::vector<int>> host_permutations = quick_perm(windowSize_);
    state.num_permutations = host_permutations.size();
    
    // Flatten permutations for GPU
    std::vector<int> flat_perms(state.num_permutations * windowSize_);
    for (int i = 0; i < state.num_permutations; i++) {
        for (int j = 0; j < windowSize_; j++) {
            flat_perms[i * windowSize_ + j] = host_permutations[i][j];
        }
    }
    allocateCopyCuda(state.permutations, flat_perms.data(), state.num_permutations * windowSize_);

    // Process each group
    for (const auto& segments : segment_groups) {
        // Collect all reorder instances from this group
        std::vector<ReorderInstance> host_instances;
        
        for (int seg_id : segments) {
            DetailedSeg* segPtr = mgrPtr_->getSegment(seg_id);
            const int rowId = segPtr->getRowId();
            const std::vector<Node*>& nodes = mgrPtr_->getCellsInSeg(seg_id);
            
            if (nodes.size() < 2) continue;
            
            int j = 0;
            while (j < (int)nodes.size()) {
                // Skip multi-height cells
                while (j < (int)nodes.size() && arch_->isMultiHeightCell(nodes[j])) {
                    j++;
                }
                int jstrt = j;
                
                // Find consecutive single-height cells
                while (j < (int)nodes.size() && arch_->isSingleHeightCell(nodes[j])) {
                    j++;
                }
                int jstop = j - 1;

                // Create non-overlapping windows
                for (int i = jstrt; i + windowSize_ <= jstop + 1; i += windowSize_) {
                    int window_start = i;
                    int window_end = std::min(i + windowSize_ - 1, jstop);
                    
                    // Compute window limits
                    const Node* next = (window_end != (int)nodes.size() - 1) ? 
                                      nodes[window_end + 1] : nullptr;
                    const Node* prev = (window_start != 0) ? 
                                      nodes[window_start - 1] : nullptr;
                    
                    DbuX rightLimit = segPtr->getMaxX();
                    if (next) {
                        int leftPadding, rightPadding;
                        arch_->getCellPadding(next, leftPadding, rightPadding);
                        rightLimit = std::min(next->getLeft() - leftPadding, rightLimit);
                    }
                    
                    DbuX leftLimit = segPtr->getMinX();
                    if (prev) {
                        int leftPadding, rightPadding;
                        arch_->getCellPadding(prev, leftPadding, rightPadding);
                        leftLimit = std::max(prev->getRight() + rightPadding, leftLimit);
                    }

                    ReorderInstance inst;
                    inst.seg_id = seg_id;
                    inst.row_id = rowId;
                    inst.start_idx = window_start;
                    inst.end_idx = window_end;
                    inst.num_cells = window_end - window_start + 1;
                    inst.left_limit = leftLimit.v;
                    inst.right_limit = rightLimit.v;
                    
                    // Store node IDs
                    for (int k = 0; k < inst.num_cells; k++) {
                        inst.node_ids[k] = nodes[window_start + k]->getId();
                    }
                    
                    host_instances.push_back(inst);
                }
            }
        }

        if (host_instances.empty()) continue;

        // Copy instances to GPU
        state.num_instances = host_instances.size();
        allocateCopyCuda(state.instances, host_instances.data(), state.num_instances);
        
        // Allocate cost arrays
        state.allocate(state.num_instances, state.num_permutations);

        // Launch kernels
        int total_threads = state.num_instances * state.num_permutations;
        int blocks = (total_threads + 255) / 256;
        compute_reorder_costs<<<blocks, 256>>>(db_, state);
        reduce_min_costs<<<state.num_instances, 256>>>(state);
        
        // Copy best permutation IDs back
        std::vector<int> host_best_perms(state.num_instances);
        copyBackToCpu(state.best_permute_id, host_best_perms.data(), state.num_instances);

        // Apply best permutations
        for (int i = 0; i < state.num_instances; i++) {
            const auto& inst = host_instances[i];
            const auto& perm = host_permutations[host_best_perms[i]];
            
            // Store original positions
            std::vector<Node*> window_nodes;
            std::unordered_map<Node*, DbuX> orig_pos;
            for (int j = 0; j < inst.num_cells; j++) {
                Node* node = mgrPtr_->getNode(inst.node_ids[j]);
                window_nodes.push_back(node);
                orig_pos[node] = node->getLeft();
            }

            // Apply permutation
            DbuX x{inst.left_limit};
            bool valid = true;
            
            for (int j = 0; j < inst.num_cells; j++) {
                Node* node = window_nodes[perm[j]];
                int leftPadding, rightPadding;
                arch_->getCellPadding(node, leftPadding, rightPadding);
                
                x += leftPadding;
                mgrPtr_->eraseFromGrid(node);
                node->setLeft(x);
                mgrPtr_->paintInGrid(node);
                
                if (mgrPtr_->hasEdgeSpacingViolation(node)) {
                    valid = false;
                    break;
                }
                
                x += node->getWidth();
                x += rightPadding;
            }

            if (!valid) {
                // Restore original positions
                for (auto& node : window_nodes) {
                    mgrPtr_->eraseFromGrid(node);
                    node->setLeft(orig_pos[node]);
                    mgrPtr_->paintInGrid(node);
                }
            } else {
                // Resort segment
                mgrPtr_->sortCellsInSeg(inst.seg_id, inst.start_idx, inst.end_idx + 1);
            }
        }
    }

    state.destroy();
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
void DetailedReorderer::reorder(const std::vector<Node*>& nodes,
                                const int jstrt,
                                const int jstop,
                                const DbuX leftLimit,
                                const DbuX rightLimit,
                                const int segId,
                                const int rowId)
{
  const int size = jstop - jstrt + 1;
  if (size <= 0) {
    return;
  }
  // XXX: Node positions still doubles!
  std::unordered_map<const Node*, DbuX> origLeft;
  for (int i = 0; i < size; i++) {
    const Node* ndi = nodes[jstrt + i];
    origLeft[ndi] = ndi->getLeft();
  }

  // Changed...  I want to work entirely with the left edge of
  // the cells.  If there is not enough space to satisfy
  // the cell widths _and_ the padding, then don't do anything.
  DbuX totalPadding{0};
  DbuX totalWidth{0};
  std::vector<DbuX> right(size, DbuX{0});
  std::vector<DbuX> left(size, DbuX{0});
  std::vector<DbuX> width(size, DbuX{0});
  for (int i = 0; i < size; i++) {
    const Node* ndi = nodes[jstrt + i];
    arch_->getCellPadding(ndi, left[i], right[i]);
    width[i] = ndi->getWidth();
    totalPadding += (left[i] + right[i]);
    totalWidth += width[i];
  }
  if (rightLimit - leftLimit < totalWidth + totalPadding) {
    // We do not have enough space, so abort.
    return;
  }

  // We might have more space than required.  Space cells out
  // somewhat evenly by adding extra space to the padding.
  const DbuX spacePerCell
      = ((rightLimit - leftLimit) - (totalWidth + totalPadding)) / size;
  const DbuX siteWidth = arch_->getRow(0)->getSiteWidth();
  const int sitePerCellTotal = (spacePerCell / siteWidth).v;
  const int sitePerCellRight = (sitePerCellTotal >> 1);
  const int sitePerCellLeft = sitePerCellTotal - sitePerCellRight;
  for (int i = 0; i < size; i++) {
    if (totalWidth + totalPadding + sitePerCellRight * siteWidth
        < rightLimit - leftLimit) {
      totalPadding += sitePerCellRight * siteWidth;
      right[i] += sitePerCellRight * siteWidth;
    }
    if (totalWidth + totalPadding + sitePerCellLeft * siteWidth
        < rightLimit - leftLimit) {
      totalPadding += sitePerCellLeft * siteWidth;
      left[i] += sitePerCellLeft * siteWidth;
    }
  }
  if (rightLimit - leftLimit < totalWidth + totalPadding) {
    // We do not have enough space, so abort.
    return;
  }

  // Generate the different permutations.  Evaluate each one and keep
  // the best one.
  //
  // NOTE: The first permutation, which is the original placement,
  // might not generate the original placement since the spacing
  // might be different.  So, just consider the first permutation
  // like all the others.

  double bestCost = cost(nodes, jstrt, jstop);
  const double origCost = bestCost;

  std::vector<DbuX> bestPosn(size, DbuX{0});  // Current positions.
  std::vector<DbuX> currPosn(size, DbuX{0});  // Current positions.
  std::vector<int> order(size, 0);            // For generating permutations.
  for (int i = 0; i < size; i++) {
    order[i] = i;
  }
  bool found = false;
  do {
    // Position the cells.
    bool dispOkay = true;
    DbuX x = leftLimit;
    for (int i = 0; i < size; i++) {
      const int ix = order[i];
      Node* ndi = nodes[jstrt + ix];
      x += left[ix];
      currPosn[ix] = x;
      mgrPtr_->eraseFromGrid(ndi);
      ndi->setLeft(currPosn[ix]);
      mgrPtr_->paintInGrid(ndi);
      x += width[ix];
      x += right[ix];

      const DbuX dx = abs(ndi->getLeft() - ndi->getOrigLeft());
      if (dx > mgrPtr_->getMaxDisplacementX()) {
        dispOkay = false;
      }
    }
    if (dispOkay) {
      const double currCost = cost(nodes, jstrt, jstop);
      if (currCost < bestCost) {
        bestPosn = currPosn;
        bestCost = currCost;

        found = true;
      }
    }
  } while (std::next_permutation(order.begin(), order.end()));

  if (!found) {
    // No improvement.  Restore positions and return.
    for (size_t i = 0; i < size; i++) {
      Node* ndi = nodes[jstrt + i];
      mgrPtr_->eraseFromGrid(ndi);
      ndi->setLeft(origLeft[ndi]);
      mgrPtr_->paintInGrid(ndi);
    }
    return;
  }

  // Put cells at their best positions.
  for (int i = 0; i < size; i++) {
    Node* ndi = nodes[jstrt + i];
    mgrPtr_->eraseFromGrid(ndi);
    ndi->setLeft(bestPosn[i]);
    mgrPtr_->paintInGrid(ndi);
  }

  // Need to resort.
  mgrPtr_->sortCellsInSeg(segId, jstrt, jstop + 1);

  // Check that cells are site aligned and fix if needed.
  {
    bool shifted = false;
    bool failed = false;
    DbuX left = leftLimit;
    for (int i = 0; i < size; i++) {
      Node* ndi = nodes[jstrt + i];

      DbuX x = ndi->getLeft();
      if (!mgrPtr_->alignPos(ndi, x, left, rightLimit)) {
        failed = true;
        break;
      }
      if (abs(x - ndi->getLeft()) != 0) {
        shifted = true;
      }
      mgrPtr_->eraseFromGrid(ndi);
      ndi->setLeft(x);
      mgrPtr_->paintInGrid(ndi);
      left = ndi->getRight();

      const DbuX dx = abs(ndi->getLeft() - ndi->getOrigLeft());
      if (dx > mgrPtr_->getMaxDisplacementX()) {
        failed = true;
        break;
      }
    }
    if (!failed) {
      // This implies everything got site aligned within the specified
      // interval.  However, we might have shifted something.
      if (shifted) {
        // Recost.  The shifting might have changed the cost.
        const double lastCost = cost(nodes, jstrt, jstop);
        if (lastCost >= origCost) {
          failed = true;
        }
      }
    }
    if (!failed) {
      for (int i = 0; i < size; i++) {
        if (mgrPtr_->hasEdgeSpacingViolation(nodes[jstrt + i])) {
          failed = true;
          break;
        }
      }
    }

    if (failed) {
      // Restore original placement.
      for (int i = 0; i < size; i++) {
        Node* ndi = nodes[jstrt + i];
        mgrPtr_->eraseFromGrid(ndi);
        ndi->setLeft(origLeft[ndi]);
        mgrPtr_->paintInGrid(ndi);
      }
      mgrPtr_->sortCellsInSeg(segId, jstrt, jstop + 1);
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
double DetailedReorderer::cost(const std::vector<Node*>& nodes,
                               const int istrt,
                               const int istop)
{
  // Compute hpwl for the specified sequence of cells.

  ++traversal_;

  double cost = 0.;
  for (int i = istrt; i <= istop; i++) {
    const Node* ndi = nodes[i];
    if (mgrPtr_->hasEdgeSpacingViolation(ndi)) {
      return std::numeric_limits<double>::max();
    }

    for (int pi = 0; pi < ndi->getNumPins(); pi++) {
      const Pin* pini = ndi->getPins()[pi];

      const Edge* edi = pini->getEdge();

      const int npins = edi->getNumPins();
      if (npins <= 1 || npins >= skipNetsLargerThanThis_) {
        continue;
      }
      if (edgeMask_[edi->getId()] == traversal_) {
        continue;
      }
      edgeMask_[edi->getId()] = traversal_;

      DbuX xmin = std::numeric_limits<DbuX>::max();
      DbuX xmax = std::numeric_limits<DbuX>::min();
      for (int pj = 0; pj < edi->getNumPins(); pj++) {
        const Pin* pinj = edi->getPins()[pj];

        const Node* ndj = pinj->getNode();

        const DbuX x = ndj->getCenterX() + pinj->getOffsetX();

        xmin = std::min(xmin, x);
        xmax = std::max(xmax, x);
      }
      cost += (xmax - xmin).v;
    }
  }
  return cost;
}

// Add new helper struct for window information
struct ReorderWindow {
    int seg_id;
    int row_id;
    int start_idx;
    int end_idx;
    DbuX left_limit;
    DbuX right_limit;
    std::vector<Node*> nodes;
};

// Add new helper function to identify independent segment groups
std::vector<std::vector<int>> group_independent_segments(DetailedMgr* mgrPtr) {
    int num_segments = mgrPtr->getNumSegments();
    std::vector<std::vector<int>> seg_graph(num_segments);
    std::vector<std::set<int>> seg2nets(num_segments);

    // Build segment to nets mapping
    #pragma omp parallel for
    for (int s = 0; s < num_segments; ++s) {
        DetailedSeg* seg = mgrPtr->getSegment(s);
        const std::vector<Node*>& nodes = mgrPtr->getCellsInSeg(s);
        for (Node* node : nodes) {
            for (int p = 0; p < node->getNumPins(); ++p) {
                const Pin* pin = node->getPins()[p];
                const Edge* edge = pin->getEdge();
                if (edge) {
                    #pragma omp critical
                    seg2nets[s].insert(edge->getId());
                }
            }
        }
    }

    // Build segment conflict graph
    std::vector<std::vector<unsigned char>> adjacency_matrix(num_segments, 
        std::vector<unsigned char>(num_segments, 0));
    
    #pragma omp parallel for collapse(2)
    for (int i = 0; i < num_segments; ++i) {
        for (int j = i + 1; j < num_segments; ++j) {
            bool has_common_net = false;
            for (int net : seg2nets[j]) {
                if (seg2nets[i].count(net)) {
                    has_common_net = true;
                    break;
                }
            }
            if (has_common_net) {
                adjacency_matrix[i][j] = adjacency_matrix[j][i] = 1;
            }
        }
    }

    // Build adjacency lists
    #pragma omp parallel for
    for (int i = 0; i < num_segments; ++i) {
        for (int j = 0; j < num_segments; ++j) {
            if (i != j && adjacency_matrix[i][j]) {
                #pragma omp critical
                seg_graph[i].push_back(j);
            }
        }
    }

    // Find independent sets using graph coloring
    std::vector<std::vector<int>> independent_groups;
    std::vector<unsigned char> visited(num_segments, 0);
    std::vector<unsigned char> in_current_set(num_segments, 0);
    
    while (true) {
        std::vector<int> independent_set;
        
        // Find nodes for current independent set
        for (int i = 0; i < num_segments; ++i) {
            if (!visited[i]) {
                bool can_add = true;
                for (int j : independent_set) {
                    if (adjacency_matrix[i][j]) {
                        can_add = false;
                        break;
                    }
                }
                if (can_add) {
                    independent_set.push_back(i);
                    visited[i] = 1;
                }
            }
        }
        
        if (independent_set.empty()) break;
        independent_groups.push_back(independent_set);
    }

    return independent_groups;
}

// Add new helper function to generate non-overlapping windows
std::vector<ReorderWindow> generate_windows(DetailedMgr* mgrPtr, 
                                          Architecture* arch,
                                          int seg_id, 
                                          int window_size) {
    std::vector<ReorderWindow> windows;
    DetailedSeg* seg = mgrPtr->getSegment(seg_id);
    const int row_id = seg->getRowId();
    const std::vector<Node*>& nodes = mgrPtr->getCellsInSeg(seg_id);
    
    if (nodes.size() < 2) return windows;

    int j = 0;
    while (j < (int)nodes.size()) {
        // Skip multi-height cells
        while (j < (int)nodes.size() && arch->isMultiHeightCell(nodes[j])) {
            j++;
        }
        int jstrt = j;
        
        // Find consecutive single-height cells
        while (j < (int)nodes.size() && arch->isSingleHeightCell(nodes[j])) {
            j++;
        }
        int jstop = j - 1;

        // Create non-overlapping windows
        for (int i = jstrt; i + window_size <= jstop + 1; i += window_size) {
            int window_start = i;
            int window_end = std::min(i + window_size - 1, jstop);
            
            // Compute window limits
            const Node* next = (window_end != (int)nodes.size() - 1) ? 
                              nodes[window_end + 1] : nullptr;
            const Node* prev = (window_start != 0) ? 
                              nodes[window_start - 1] : nullptr;
            
            DbuX right_limit = seg->getMaxX();
            if (next) {
                int left_padding, right_padding;
                arch->getCellPadding(next, left_padding, right_padding);
                right_limit = std::min(next->getLeft() - left_padding, right_limit);
            }
            
            DbuX left_limit = seg->getMinX();
            if (prev) {
                int left_padding, right_padding;
                arch->getCellPadding(prev, left_padding, right_padding);
                left_limit = std::max(prev->getRight() + right_padding, left_limit);
            }

            ReorderWindow window;
            window.seg_id = seg_id;
            window.row_id = row_id;
            window.start_idx = window_start;
            window.end_idx = window_end;
            window.left_limit = left_limit;
            window.right_limit = right_limit;
            window.nodes.assign(nodes.begin() + window_start, 
                              nodes.begin() + window_end + 1);
            
            windows.push_back(window);
        }
    }
    
    return windows;
}

// Helper function to position cells according to permutation
bool DetailedReorderer::position_cells(const ReorderWindow& window,
                                     const std::vector<int>& order,
                                     std::vector<DbuX>& positions) {
    const int size = window.nodes.size();
    
    // Calculate padding and widths
    std::vector<DbuX> left_padding(size), right_padding(size), widths(size);
    DbuX total_padding{0}, total_width{0};
    
    for (int i = 0; i < size; i++) {
        const Node* node = window.nodes[i];
        arch_->getCellPadding(node, left_padding[i], right_padding[i]);
        widths[i] = node->getWidth();
        total_padding += (left_padding[i] + right_padding[i]);
        total_width += widths[i];
    }
    
    // Check if we have enough space
    if (window.right_limit - window.left_limit < total_width + total_padding) {
        return false;
    }
    
    // Position cells with permutation
    DbuX x = window.left_limit;
    for (int i = 0; i < size; i++) {
        const int ix = order[i];
        x += left_padding[ix];
        positions[ix] = x;
        
        // Check displacement constraint
        const Node* node = window.nodes[ix];
        const DbuX dx = abs(positions[ix] - node->getOrigLeft());
        if (dx > mgrPtr_->getMaxDisplacementX()) {
            return false;
        }
        
        x += widths[ix];
        x += right_padding[ix];
    }
    
    return true;
}

// Helper function to apply positions to cells
void DetailedReorderer::apply_positions(const ReorderWindow& window,
                                      const std::vector<DbuX>& positions) {
    const int size = window.nodes.size();
    
    // Store original positions in case we need to revert
    std::unordered_map<const Node*, DbuX> orig_positions;
    for (int i = 0; i < size; i++) {
        Node* node = window.nodes[i];
        orig_positions[node] = node->getLeft();
    }
    
    // Apply new positions
    bool failed = false;
    for (int i = 0; i < size; i++) {
        Node* node = window.nodes[i];
        mgrPtr_->eraseFromGrid(node);
        node->setLeft(positions[i]);
        mgrPtr_->paintInGrid(node);
        
        // Check for violations
        if (mgrPtr_->hasEdgeSpacingViolation(node)) {
            failed = true;
            break;
        }
    }
    
    if (failed) {
        // Restore original positions
        for (int i = 0; i < size; i++) {
            Node* node = window.nodes[i];
            mgrPtr_->eraseFromGrid(node);
            node->setLeft(orig_positions[node]);
            mgrPtr_->paintInGrid(node);
        }
    } else {
        // Resort segment
        mgrPtr_->sortCellsInSeg(window.seg_id, window.start_idx, window.end_idx + 1);
    }
}

// Add GPU kernels
__global__ void compute_reorder_costs(GpuData db, ReorderState state) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= state.num_instances * state.num_permutations) return;
    
    int inst_id = idx / state.num_permutations;
    int perm_id = idx % state.num_permutations;
    
    auto inst = state.instances[inst_id];
    auto perm = state.permutations + perm_id * state.K;
    
    // Check if permutation is valid for this instance
    bool valid = true;
    for (int i = 0; i < inst.num_cells; i++) {
        if (perm[i] >= inst.num_cells) {
            valid = false;
            break;
        }
    }
    
    if (!valid) {
        state.costs[idx] = cuda::numeric_limits<int>::max();
        return;
    }
    
    // Position cells according to permutation
    int x = inst.left_limit;
    int positions[4]; // Since max window size is 4
    
    // Calculate positions
    for (int i = 0; i < inst.num_cells; i++) {
        int node_id = inst.node_ids[perm[i]];
        x += db.node_left_padding[node_id];
        positions[perm[i]] = x;
        
        // Check displacement constraint
        int dx = abs(positions[perm[i]] - db.init_x[node_id]);
        if (dx > db.max_displacement_x) {
            state.costs[idx] = cuda::numeric_limits<int>::max();
            return;
        }
        
        x += db.node_size_x[node_id];
        x += db.node_right_padding[node_id];
    }
    
    // Calculate cost (HPWL)
    int cost = 0;
    for (int i = 0; i < inst.num_cells; i++) {
        int node_id = inst.node_ids[i];
        
        // Check each net connected to this node
        for (int node2pin_id = db.flat_node2pin_start_map[node_id];
             node2pin_id < db.flat_node2pin_start_map[node_id + 1];
             ++node2pin_id) {
            int node_pin_id = db.flat_node2pin_map[node2pin_id];
            int net_id = db.pin2net_map[node_pin_id];
            
            if (!db.net_mask[net_id]) continue;
            
            // Calculate net bounding box
            int xl = cuda::numeric_limits<int>::max();
            int xh = cuda::numeric_limits<int>::lowest();
            
            for (int net2pin_id = db.flat_net2pin_start_map[net_id];
                 net2pin_id < db.flat_net2pin_start_map[net_id + 1];
                 ++net2pin_id) {
                int net_pin_id = db.flat_net2pin_map[net2pin_id];
                int other_node_id = db.pin2node_map[net_pin_id];
                
                int px;
                // If node is in our window, use proposed position
                bool found = false;
                for (int j = 0; j < inst.num_cells; j++) {
                    if (other_node_id == inst.node_ids[j]) {
                        px = positions[j] + db.pin_offset_x[net_pin_id];
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    px = db.x[other_node_id] + db.pin_offset_x[net_pin_id];
                }
                
                xl = min(xl, px);
                xh = max(xh, px);
            }
            
            cost += (xh - xl);
        }
    }
    
    state.costs[idx] = cost;
}

__global__ void reduce_min_costs(ReorderState state) {
    int inst_id = blockIdx.x;
    if (inst_id >= state.num_instances) return;
    
    int best_cost = cuda::numeric_limits<int>::max();
    int best_perm = 0;
    
    for (int i = threadIdx.x; i < state.num_permutations; i += blockDim.x) {
        int cost = state.costs[inst_id * state.num_permutations + i];
        if (cost < best_cost) {
            best_cost = cost;
            best_perm = i;
        }
    }
    
    __shared__ int shared_costs[256];
    __shared__ int shared_perms[256];
    
    shared_costs[threadIdx.x] = best_cost;
    shared_perms[threadIdx.x] = best_perm;
    
    __syncthreads();
    
    for (int stride = blockDim.x/2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride) {
            if (shared_costs[threadIdx.x] > shared_costs[threadIdx.x + stride]) {
                shared_costs[threadIdx.x] = shared_costs[threadIdx.x + stride];
                shared_perms[threadIdx.x] = shared_perms[threadIdx.x + stride];
            }
        }
        __syncthreads();
    }
    
    if (threadIdx.x == 0) {
        state.best_permute_id[inst_id] = shared_perms[0];
    }
}

}  // namespace dpl