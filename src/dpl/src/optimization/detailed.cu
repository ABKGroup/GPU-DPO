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

void updateFlattenedDataAndCopyToGPU(DetailedMgr* mgr, GpuData* gpuData)
{
  Network* network = mgr->getNetwork();
  int num_nodes = network->getNumNodes();
  std::vector<int> node_x(num_nodes);
  std::vector<int> node_y(num_nodes);
  std::vector<int> node_size_x(num_nodes);
  std::vector<int> node_size_y(num_nodes);
  std::vector<int> node2segs(num_nodes);
  for (int i = 0; i < num_nodes; ++i) {
    Node* node = network->getNode(i);
    node_x[i] = node->getLeft().v;
    node_y[i] = node->getBottom().v;
    node_size_x[i] = node->getWidth().v;
    node_size_y[i] = node->getHeight().v;
    if (mgr->getNumReverseCellToSegs(i) > 0) {
      node2segs[i] = mgr->getReverseCellToSegs(i)[0]->getSegId();
    } else {
      node2segs[i] = -1;
    }
  }
  cudaMemcpy(gpuData->x, node_x.data(), sizeof(int) * num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(gpuData->y, node_y.data(), sizeof(int) * num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(gpuData->node_size_x, node_size_x.data(), sizeof(int) * num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(gpuData->node_size_y, node_size_y.data(), sizeof(int) * num_nodes, cudaMemcpyHostToDevice);
  cudaMemcpy(gpuData->node2segs, node2segs.data(), sizeof(int) * num_nodes, cudaMemcpyHostToDevice);
}

void apply_lsmc(DetailedMgr* mgr, int kick_move) {
  // Here, we apply large stage Markov chain descent.
  // Kick move is a percentage of movable design instances.
  // We perturb the initial placement by kick move percent
  Network* network = mgr->getNetwork();
  Architecture* arch = mgr->getArchitecture();

  std::vector<Node*> candidates = mgr->getSingleHeightCells();

  int num_movable = (int)candidates.size();
  if (num_movable < 1) return;

  int num_moves = (int)((kick_move / 100.0) * candidates.size());
  if (num_moves > num_movable) num_moves = num_movable;

  DetailedGlobalSwap gs(arch, network);

  int num_success = 0;
  for (int m = 0; m < num_moves; ++m) {
    int idx = mgr->getRandom(num_movable); 
    Node* node = candidates[idx];
    std::vector<Node*> single_node_vec = {node};
    if (gs.generate(mgr, single_node_vec)) {
      mgr->acceptMove();
      num_success++;
    } else {
      mgr->rejectMove();
    }
  }
  printf("[INFO GPU-DPO] Performed %d global swap moves on randomly selected nodes.\n", num_success);

  DetailedHPWL hpwlObj(network);
  hpwlObj.init(mgr, nullptr);
  int curr_hpwl = hpwlObj.curr();
  std::cout << "[INFO GPU-DPO] The initial HPWL after the kick move is " << curr_hpwl << std::endl;
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

  int max_lsmc_moves = 5;
  int kick_move = 5;
  int max_lsmc_failures = 5;
  bool perform_lsmc = false;

  // Copy the data from host to device
  GpuData* gpuData_ = new GpuData();

  cudaFree(0);  // triggers context initialization

  auto start = std::chrono::high_resolution_clock::now();
  gpuData_->copyToDevice(*flattenedData_);
  auto end = std::chrono::high_resolution_clock::now();
  double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();
  std::cout << "[INFO GPU-DPO] Copy to device time: " << elapsed_ms << " ms\n";

  // Parse the script string and run each command.
  boost::char_separator<char> separators(" \r\t\n", ";");
  boost::tokenizer<boost::char_separator<char>> tokens(params_.script_,
                                                       separators);
  std::vector<std::string> args;

  // first initial descent
  for (auto temp : tokens) {
    if (temp.back() == ';') {
      while (!temp.empty() && temp.back() == ';') {
        temp.resize(temp.size() - 1);
      }
      if (!temp.empty()) {
        args.push_back(temp);
      }
      // Command ended by a semi-colon.
      doDetailedCommand(args, *gpuData_);
      args.clear();
      // Copy data back to host once done
      if (deviceOpsDone && !dataCopiedBack) {
        auto start = std::chrono::high_resolution_clock::now();
        gpuData_->copyToHost(*flattenedData_);
        auto end = std::chrono::high_resolution_clock::now();
        double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();
        std::cout << "[INFO GPU-DPO] Copy to host time: " << elapsed_ms << " ms\n";
        flattenedData_->populateNetwork(*network_, *mgr_);
        dataCopiedBack = true;
      }
    } else {
      args.push_back(temp);
    }
  }
  // Last command; possible if no ending semi-colon.
  doDetailedCommand(args, *gpuData_);

  // Note: If cell orientation was not the last script
  // command run, then we should/need to perform
  // orientation to ensure the cells are properly
  // oriented for their respective row assignments.
  // We do not need to do flipping though.
  {
    DetailedOrient orienter(arch_, network_);
    orienter.run(mgr_, "orient -f");
  }

  // record the initial descent hpwl
  DetailedHPWL hpwlObj(network_);
  hpwlObj.init(mgr_, nullptr);
  int initial_hpwl = hpwlObj.curr();
  std::cout << "[INFO GPU-DPO] The initial HPWL after the first descent is " << initial_hpwl << std::endl;
  
  // Save initial placement and segment info
  // std::vector<int> curr_x(network_->getNumNodes());
  // std::vector<int> curr_y(network_->getNumNodes());
  // std::vector<int> curr_node2segs(network_->getNumNodes());

  // for (int i = 0; i < num_movable_nodes; i++) {
  //   Node node = network_->getNode(i);
  //   curr_x[i] = node->getLeft();
  //   curr_y[i] = node->getBottom();
  //   curr_node2segs = node->getSegId();
  // }
  
  int previous_hpwl = initial_hpwl;
  int failures = 0;
  const double IMPROVEMENT_THRESHOLD = 0.001; // 1% improvement threshold
  
  // Data currently resides in the CPU at the start of the first LSMC move
  for (int i = 0; i < max_lsmc_moves; i++) {
    deviceOpsDone = false;
    dataCopiedBack = false;

    std::vector<int> saved_x(network_->getNumNodes());
    std::vector<int> saved_y(network_->getNumNodes());
    std::vector<int> saved_node2segs(network_->getNumNodes());
    for (int n = 0; n < network_->getNumNodes(); ++n) {
      Node* node = network_->getNode(n);
      if (arch_->isSingleHeightCell(node)) {
        saved_x[n] = node->getLeft().v;
        saved_y[n] = node->getBottom().v;
        if (mgr_->getNumReverseCellToSegs(n) > 0) {
          saved_node2segs[n] = mgr_->getReverseCellToSegs(n)[0]->getSegId();
        } else {
          saved_node2segs[n] = -1;
        }
      }
    }

    // Check if we should perform the LSMC move
    if (perform_lsmc) {
      apply_lsmc(&mgr, kick_move);
      perform_lsmc = false;
    }

    // Copy node locations and seg IDs to the GPU
    updateFlattenedDataAndCopyToGPU(mgr_, gpuData_);

    // Attempt to descend again
    for (auto temp : tokens) {
      if (temp.back() == ';') {
        while (!temp.empty() && temp.back() == ';') {
          temp.resize(temp.size() - 1);
        }
        if (!temp.empty()) {
          args.push_back(temp);
        }
        // Command ended by a semi-colon.
        doDetailedCommand(args, *gpuData_);
        args.clear();
        if (deviceOpsDone && !dataCopiedBack) {
          auto start = std::chrono::high_resolution_clock::now();
          gpuData_->copyToHost(*flattenedData_);
          auto end = std::chrono::high_resolution_clock::now();
          double elapsed_ms = std::chrono::duration<double, std::milli>(end - start).count();
          std::cout << "[INFO GPU-DPO] Copy to host time: " << elapsed_ms << " ms\n";
          flattenedData_->populateNetwork(*network_, *mgr_);
          dataCopiedBack = true;
        }
      } else {
        args.push_back(temp);
      }
    }
    // Last command; possible if no ending semi-colon.
    doDetailedCommand(args, *gpuData_);

    // Note: If cell orientation was not the last script
    // command run, then we should/need to perform
    // orientation to ensure the cells are properly
    // oriented for their respective row assignments.
    // We do not need to do flipping though.
    {
      DetailedOrient orienter(arch_, network_);
      orienter.run(mgr_, "orient -f");
    }

    // Check the hpwl
    int new_hpwl = hpwlObj.curr();
    double improvement = (double)(previous_hpwl - new_hpwl) / previous_hpwl;

    std::cout << "[INFO GPU-DPO] LSMC iteration " << i
            << ": HPWL = " << new_hpwl
            << ", improvement = " << (improvement * 100.0) << "%\n";

    if (new_hpwl > previous_hpwl) {
      std::cout << "[INFO GPU-DPO] HPWL worsened after LSMC descent. Reverting to previous placement.\n";
      for (int n = 0; n < network_->getNumNodes(); ++n) {
        Node* node = network_->getNode(n);
        if (arch_->isSingleHeightCell(node)) {
          node->setLeft(DbuX{saved_x[n]});
          node->setBottom(DbuY{saved_y[n]});
          int num_segs = mgr_->getNumReverseCellToSegs(n);
          for (int s = num_segs - 1; s >= 0; --s) {
            DetailedSeg* seg = mgr_->getReverseCellToSegs(n)[s];
            mgr_->removeCellFromSegment(node, seg->getSegId());
          }
          if (saved_node2segs[n] != -1) {
            mgr_->addCellToSegment(node, saved_node2segs[n]);
          }
        }
      }
      new_hpwl = hpwlObj.curr();
      std::cout << "[INFO GPU-DPO] HPWL after revert: " << new_hpwl << "\n";
      improvement = (double)(previous_hpwl - new_hpwl) / previous_hpwl;
    }

    // If the new hpwl has low improvement, enable LSMC flag
    if (improvement < IMPROVEMENT_THRESHOLD) {
      failures++;
      std::cout << "[INFO GPU-DPO] Improvement below threshold (" << (IMPROVEMENT_THRESHOLD * 100.0)
                << "%). Failures: " << failures << "/" << max_lsmc_failures << "\n";
      perform_lsmc = true;
    }
    else {
      failures = 0;
      perform_lsmc = false;
    }

    previous_hpwl = new_hpwl;

    if (failures >= max_lsmc_failures) {
      std::cout << "[INFO GPU-DPO] Reached maximum allowed LSMC failures. Stopping LSMC loop.\n";
      break;
    }
  }

  gpuData_->freeData();
  
  // Final HPWL evaluation
  int final_hpwl = hpwlObj.curr();
  double total_improvement = (double)(initial_hpwl - final_hpwl) / initial_hpwl;
  std::cout << "[INFO GPU-DPO] Total improvement: " << (total_improvement * 100.0) << "%" << std::endl;

  // Different checks which are useful for debugging.
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

  // clean up
  delete gpuData_;

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
    deviceOpsDone = true;
  } else if (strcmp(args[0].c_str(), "vs") == 0) {
    DetailedVerticalSwap vs(arch_, network_);
    vs.run(mgr_, args);
  } else if (strcmp(args[0].c_str(), "ro") == 0) {
    DetailedReorderer ro(arch_, network_);
    ro.run(mgr_, args);
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
