// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include "dpl/Opendp.h"
#include "odb/util.h"
#include "utl/Logger.h"

// My stuff.
#include "legalize_shift.h"
#include "optimization/detailed.h"
#include "optimization/detailed_manager.h"

namespace dpl {

////////////////////////////////////////////////////////////////
void Opendp::improvePlacement(const int seed,
                              const int max_displacement_x,
                              const int max_displacement_y,
                              const int window_size,
                              const int problem_size,
                              const int num_iterations,
                              const int kick_move,
                              const int run_gs,
                              const int run_reorder,
                              const int run_mis,
                              const float tolerance)
{
  logger_->report("Detailed placement improvement.");

  odb::WireLengthEvaluator eval(db_->getChip()->getBlock());
  const int64_t hpwlBefore = eval.hpwl();

  if (hpwlBefore == 0) {
    logger_->report("Skipping detailed improvement since hpwl is zero.");
    return;
  }

  // Get needed information from DB.
  importDb();
  // TODO: adjustNodesOrient() but it's currently causing an unrelated CI
  // failure
  initGrid();

  const bool disallow_one_site_gaps = !odb::hasOneSiteMaster(db_);

  // A manager to track cells.
  DetailedMgr mgr(arch_.get(), network_.get(), grid_.get(), drc_engine_.get());
  mgr.setLogger(logger_);
  // Various settings.
  mgr.setSeed(seed);
  mgr.setMaxDisplacement(max_displacement_x, max_displacement_y);
  mgr.setDisallowOneSiteGaps(disallow_one_site_gaps);

  // Legalization.  Doesn't particularly do much.  It only
  // populates the data structures required for detailed
  // improvement.  If it errors or prints a warning when
  // given a legal placement, that likely means there is
  // a bug in my code somewhere.
  ShiftLegalizer lg;
  lg.legalize(mgr);

  FlattenedData* flattenedData_ = new FlattenedData(&mgr);
  flattenedData_->createFlattenedData();

  // Detailed improvement.  Runs through a number of different
  // optimizations aimed at wirelength improvement.  The last
  // call to the random improver can be set to consider things
  // like density, displacement, etc. in addition to wirelength.
  // Everything done through a script string.

  std::string num_iterations_opt = " -p " + std::to_string(num_iterations); 
  std::string window_size_opt = " -w " + std::to_string(window_size);
  std::string problem_size_opt = " -s " + std::to_string(problem_size);
  std::string kick_move_opt = " -kick " + std::to_string(kick_move);
  std::string run_gs_opt = " -run " + std::to_string(run_gs);
  std::string run_reorder_opt = " -run " + std::to_string(run_reorder);
  std::string run_mis_opt = " -run " + std::to_string(run_mis);
  std::string tolerance_opt = " -t " + std::to_string(tolerance);
  std::string batch_size_opt = " -b " + std::to_string(32);     // value is hard-coded for now
  std::string bin_size_x_opt = " -bin_x " + std::to_string(16); // value is hard-coded for now 
  std::string bin_size_y_opt = " -bin_y " + std::to_string(16); // value is hard-coded for now

  DetailedParams dtParams;
  dtParams.script_ = "";
  // Maximum independent set matching.
  dtParams.script_ += "mis" + num_iterations_opt + tolerance_opt + batch_size_opt + bin_size_x_opt + bin_size_y_opt + problem_size_opt + run_mis_opt + ";";
  // Global swaps.
  dtParams.script_ += "gs" + num_iterations_opt + tolerance_opt + batch_size_opt + bin_size_x_opt + bin_size_y_opt  + run_gs_opt + ";";
  // Small reordering.
  dtParams.script_ += "ro" + num_iterations_opt + tolerance_opt + bin_size_x_opt + bin_size_y_opt + run_reorder_opt + ";";
  // Vertical swaps.
  dtParams.script_ += "vs -p 10 -t 0.005;";
  // Random moves and swaps with hpwl as a cost function.  Use
  // random moves and hpwl objective right now.
  dtParams.script_ += "default -p 5 -f 20 -gen rng -obj hpwl -cost (hpwl);";

  if (disallow_one_site_gaps) {
    dtParams.script_ += "disallow_one_site_gaps;";
  }
  // Run the script.
  Detailed dt(dtParams);
  dt.improve(mgr, *flattenedData_);

  // Write solution back.
  updateDbInstLocations();

  // Clean up
  delete flattenedData_;

  // Get final hpwl.
  const int64_t hpwlAfter = eval.hpwl();

  const double dbu_micron = db_->getTech()->getDbUnitsPerMicron();

  // Statistics.
  logger_->report("Detailed Improvement Results");
  logger_->report("------------------------------------------");
  logger_->report("Original HPWL         {:10.1f} u", hpwlBefore / dbu_micron);
  logger_->report("Final HPWL            {:10.1f} u", hpwlAfter / dbu_micron);
  const double hpwl_delta = (hpwlAfter - hpwlBefore) / (double) hpwlBefore;
  logger_->report("Delta HPWL            {:10.1f} %", hpwl_delta * 100);
  logger_->report("");
}

////////////////////////////////////////////////////////////////
}  // namespace dpl
