// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include <algorithm>
#include <boost/format.hpp>
#include <boost/tokenizer.hpp>
#include <cmath>
#include <iostream>
#include <stack>
#include <string>
#include <utility>
#include <vector>
#include <chrono>
#include <cuda.h>
#include <cuda_runtime.h>

#include "util/utility.h"
#include "utl/Logger.h"

// Detailed management of segments.
#include "infrastructure/detailed_segment.h"
#include "optimization/detailed_manager.h"
// Detailed placement algorithms.
#include "detailed.h"
#include "optimization/detailed_global.cuh"
#include "optimization/detailed_mis.cuh"
#include "optimization/detailed_orient.h"
#include "optimization/detailed_random.h"
#include "optimization/detailed_reorder.cuh"
#include "optimization/detailed_vertical.h"
#include "objective/detailed_hpwl.h"

using utl::DPL;

namespace dpl {

////////////////////////////////////////////////////////////////////////////////
// Defines.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Detailed::apply_lsmc:
////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void apply_lsmc(GpuData &db, DetailedMgr &mgr, int kick_move) {
  // Here, we apply large stage Markov chain descent.
  // Kick move is a percentage of movable design instances.
  // We perturb the initial placement by kick move percent,
  // which randomly swaps cells that make the HPWL worse.
  FlattenedData cpu_db(&mgr); 
  cpu_db.createFlattenedData();
  db.copyToHost(cpu_db);
  DetailedMgr* mgr_ptr = cpu_db.mgr_;
  Network* network = cpu_db.network_;
  Architecture* arch = cpu_db.arch_;

  DetailedHPWL hpwlObj(network);
  hpwlObj.init(mgr_ptr, nullptr);

  std::vector<Node*> candidates = mgr_ptr->getSingleHeightCells();
  int num_movable = (int)candidates.size();
  if (num_movable < 2) return;

  int num_swaps = 0;
  int currHpwl = hpwlObj.curr();
  uint64_t hpwl_x, hpwl_y;
  float total_swapped_cells = (float)kick_move / 100.0 * cpu_db.num_movable_nodes;
  printf("[INFO GPU-DPO] Performing LSMC. Attempting to randomly swap %d cells.\n", (int)total_swapped_cells);
  while (num_swaps < (int)total_swapped_cells) {
    // use the same random seed set in cmd line
    int i = mgr_ptr->getRandom(num_movable);    
    int j = mgr_ptr->getRandom(num_movable);    
    if (i == j) continue;
    Node* ni = candidates[i];
    Node* nj = candidates[j];
    if (ni == nj) continue;
    DbuX xi = ni->getLeft();
    DbuY yi = ni->getBottom();
    int si = mgr_ptr->getReverseCellToSegs(ni->getId())[0]->getSegId();
    DbuX xj = nj->getLeft();
    DbuY yj = nj->getBottom();
    int sj = mgr_ptr->getReverseCellToSegs(nj->getId())[0]->getSegId();
    if (mgr_ptr->trySwap(ni, xi, yi, si, xj, yj, sj)) {
      //uint64_t hpwl_x, hpwl_y;
      //int newHpwl = Utility::hpwl(network, hpwl_x, hpwl_y);
      //if (newHpwl < currHpwl) {
      //  currHpwl = newHpwl;
        mgr_ptr->acceptMove();
        num_swaps++;
      //}
      //else {
        //mgr_ptr->rejectMove();
      //}
    } else {
      mgr_ptr->rejectMove();
    }
  }
  int lsmc_hpwl = Utility::hpwl(network, hpwl_x, hpwl_y);
  printf("[INFO GPU-DPO] HPWL after performing LSMC is %d.\n", lsmc_hpwl);
  // Repopulate cpu_db.x, cpu_db.y, and cpu_db.node2segs from the network and manager after swaps
  for (int i = 0; i < cpu_db.num_movable_nodes; ++i) {
    Node* node = mgr_ptr->getNetwork()->getNode(i);
    if (cpu_db.x[i] != node->getLeft().v) {
      cpu_db.x[i] = node->getLeft().v;
    }
    if (cpu_db.y[i] != node->getBottom().v) {
      cpu_db.y[i] = node->getBottom().v;
    }
    // Update node2segs
    if (mgr_ptr->getNumReverseCellToSegs(i) > 0 
        && cpu_db.node2segs[i] != mgr_ptr->getReverseCellToSegs(i)[0]->getSegId()) {
      cpu_db.node2segs[i] = mgr_ptr->getReverseCellToSegs(i)[0]->getSegId();
    }
  }
  // Copy only the updated node locations and segment IDs to the GPU
  cudaMemcpy(db.x, cpu_db.x.data(), sizeof(int) * cpu_db.num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(db.y, cpu_db.y.data(), sizeof(int) * cpu_db.num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(db.node2segs, cpu_db.node2segs.data(), sizeof(int) * cpu_db.num_nodes, cudaMemcpyHostToDevice);

  printf("[INFO GPU-DPO] Performed %d random swaps.\n", num_swaps);
}

////////////////////////////////////////////////////////////////////////////////
// Detailed::improve:
////////////////////////////////////////////////////////////////////////////////
bool Detailed::improve(DetailedMgr& mgr, FlattenedData& flattenedData)
{
  mgr_ = &mgr;
  arch_ = mgr.getArchitecture();
  network_ = mgr.getNetwork();
  flattenedData_ = &flattenedData;

  // LSMC parameters
  int max_lsmc_iters = 1; // configurable
  int kick_move = 0;      // configurable
  int max_failures = 5;

  // Copy the data from host to device
  GpuData* gpuData_ = new GpuData();
  cudaFree(0);  // triggers context initialization
  gpuData_->copyToDevice(*flattenedData_);

  // Save best placement
  FlattenedData best_flattened = *flattenedData_;
  DetailedHPWL hpwlObj(network_);
  hpwlObj.init(mgr_, nullptr);
  int currHpwl = hpwlObj.curr();
  int fail_count = 0;

  for (int lsmc_iter = 0; lsmc_iter < max_lsmc_iters; ++lsmc_iter) {
    printf("[INFO GPU-DPO] LSMC iteration %d/%d\n", lsmc_iter+1, max_lsmc_iters);
    // Apply kick move
    apply_lsmc(*gpuData_, mgr, kick_move);
    
    // Run script commands (MIS, GS, RO, etc)
    boost::char_separator<char> separators(" \r\t\n", ";");
    boost::tokenizer<boost::char_separator<char>> tokens(params_.script_, separators);
    std::vector<std::string> args;
    for (auto temp : tokens) {
      if (temp.back() == ';') {
        while (!temp.empty() && temp.back() == ';') temp.resize(temp.size() - 1);
        if (!temp.empty()) args.push_back(temp);
        doDetailedCommand(args, *gpuData_);
        args.clear();
      } else {
        args.push_back(temp);
      }
    }
    doDetailedCommand(args, *gpuData_);

    // Copy data back to host to measure HPWL
    gpuData_->copyToHost(*flattenedData_);
    uint64_t hpwl_x, hpwl_y;
    int newHpwl = Utility::hpwl(network_, hpwl_x, hpwl_y);
    printf("[INFO GPU-DPO] LSMC HPWL after iteration %d: %d (best: %d)\n", lsmc_iter+1, (int)newHpwl, currHpwl);

    if (newHpwl < currHpwl) {
      currHpwl = newHpwl;
      best_flattened = *flattenedData_;
      fail_count = 0;
    } else {
      // Revert to best placement
      *flattenedData_ = best_flattened;
      gpuData_->copyToDevice(*flattenedData_);
      fail_count++;
      if (fail_count >= max_failures) {
        printf("[INFO GPU-DPO] Breaking LSMC loop after %d consecutive failures to improve HPWL.\n", fail_count);
        break;
      }
    }
  }

  // Copy best placement to device and host
  *flattenedData_ = best_flattened;
  gpuData_->copyToDevice(*flattenedData_);
  gpuData_->copyToHost(*flattenedData_);
  flattenedData_->populateNetwork(*network_, *mgr_);
  gpuData_->freeData();
  delete gpuData_;

  // Orientation and checks as before
  DetailedOrient orienter(arch_, network_);
  orienter.run(mgr_, "orient -f");
  mgr.checkRegionAssignment();
  mgr.checkRowAlignment();
  mgr.checkSiteAlignment();
  mgr.checkOverlapInSegments();
  mgr.checkEdgeSpacingInSegments();

  if (mgr.getDisallowOneSiteGaps()) {
    std::vector<std::vector<int>> oneSiteViolations;
    int temp_move_limit = mgr.getMoveLimit();
    mgr.setMoveLimit(10000);
    mgr.getOneSiteGapViolationsPerSegment(oneSiteViolations, true);
    for (int i = 0; i < oneSiteViolations.size(); i++) {
      if (!oneSiteViolations[i].empty()) {
        std::string violating_node_ids = "[";
        for (int nodeId : oneSiteViolations[i]) {
          violating_node_ids += std::to_string(nodeId)
                                + ",]"[nodeId == oneSiteViolations[i].back()];
        }
        mgr_->getLogger()->warn(
            DPL,
            323,
            "One site gap violation in segment {:d} nodes: {}",
            i,
            violating_node_ids);
      }
    }
    mgr.setMoveLimit(temp_move_limit);
  }

  return true;
}

//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
void Detailed::doDetailedCommand(std::vector<std::string>& args, GpuData& db_)
{
  if (args.empty()) {
    return;
  }

  // The first argument is always the command.

  auto logger = mgr_->getLogger();

  // Print something about what command will run.
  std::string command;
  if (strcmp(args[0].c_str(), "mis") == 0) {
    command = "independent set matching";
  } else if (strcmp(args[0].c_str(), "gs") == 0) {
    command = "global swaps";
  } else if (strcmp(args[0].c_str(), "vs") == 0) {
    command = "vertical swaps";
  } else if (strcmp(args[0].c_str(), "ro") == 0) {
    command = "reordering";
  } else if (strcmp(args[0].c_str(), "orient") == 0) {
    command = "orienting";
  } else if (strcmp(args[0].c_str(), "default") == 0) {
    command = "random improvement";
  } else if (strcmp(args[0].c_str(), "disallow_one_site_gaps") == 0) {
    command = "disallow_one_site_gaps";
  } else {
    logger->error(DPL, 341, "Unknown algorithm {:s}.", args[0]);
  }
  logger->info(DPL, 303, "Running algorithm for {:s}.", command);

  if (strcmp(args[0].c_str(), "mis") == 0) {
    DetailedMis mis(arch_, network_);
    mis.run(mgr_, db_, args);
  } else if (strcmp(args[0].c_str(), "gs") == 0) {
    DetailedGlobalSwap gs(arch_, network_);
    gs.run(mgr_, db_, args);
  } else if (strcmp(args[0].c_str(), "vs") == 0) {
    DetailedVerticalSwap vs(arch_, network_);
    vs.run(mgr_, args);
  } else if (strcmp(args[0].c_str(), "ro") == 0) {
    DetailedReorderer ro(arch_, network_);
    ro.run(mgr_, db_, args);
    deviceOpsDone = true;
  } else if (strcmp(args[0].c_str(), "orient") == 0) {
    DetailedOrient orienter(arch_, network_);
    orienter.run(mgr_, args);
  } else if (strcmp(args[0].c_str(), "default") == 0) {
    DetailedRandom random(arch_, network_);
    random.run(mgr_, args);
  } else {
    return;
  }

  // Different checks which are useful for debugging.
  // mgr_->checkRegionAssignment();
  // mgr_->checkRowAlignment();
  // mgr_->checkSiteAlignment();
  // mgr_->checkOverlapInSegments();
  // mgr_->checkEdgeSpacingInSegments();
}

}  // namespace dpl
