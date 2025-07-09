// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

////////////////////////////////////////////////////////////////////////////////
// Includes.
////////////////////////////////////////////////////////////////////////////////
#include <string>
#include <vector>

#include "infrastructure/architecture.h"
#include "infrastructure/network.h"
#include "infrastructure/FlattenedData.h"

namespace dpl {

////////////////////////////////////////////////////////////////////////////////
// Forward declarations.
////////////////////////////////////////////////////////////////////////////////
class DetailedMgr;
class GpuData;

////////////////////////////////////////////////////////////////////////////////
// Classes.
////////////////////////////////////////////////////////////////////////////////
struct DetailedParams
{
  std::string script_;
  double targetUt_ = 1.0;
};

class Detailed
{
 public:
  explicit Detailed(DetailedParams& params) : params_(params) {}

  bool improve(DetailedMgr& mgr, FlattenedData& flattenedData);

 private:
  void doDetailedCommand(std::vector<std::string>& args, GpuData& gpuData);

  DetailedParams& params_;
  DetailedMgr* mgr_ = nullptr;

  Architecture* arch_ = nullptr;
  Network* network_ = nullptr;

  FlattenedData* flattenedData_ = nullptr;

  bool deviceOpsDone = false;
  bool dataCopiedBack = false;
};

}  // namespace dpl
