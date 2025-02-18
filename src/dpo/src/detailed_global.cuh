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

#pragma once

#include <vector>
#include <unordered_map>

#include "detailed_generator.h"
#include "rectangle.h"

namespace dpo {
class Architecture;
class DetailedMgr;
class Edge;
class Network;
class RoutingParams;

// CLASSES ===================================================================
class DetailedGlobalSwapCUDA : public DetailedGenerator
{
 public:
  DetailedGlobalSwapCUDA(Architecture* arch, Network* network, RoutingParams* rt);
  DetailedGlobalSwapCUDA();

  // Interfaces for scripting.
  void run(DetailedMgr* mgrPtr, const std::string& command);
  void run(DetailedMgr* mgrPtr, std::vector<std::string>& args);

  // Interface for move generation.
  bool generate(DetailedMgr* mgr, std::vector<Node*>& candidates) override;
  void stats() override;
  void init(DetailedMgr* mgr) override;

 private:
  void globalSwapCUDA();  // tries to avoid overlap.
  bool calculateEdgeBB(Edge* ed, Node* nd, Rectangle& bbox);
  bool getRange(Node*, Rectangle&);
  double delta(Node* ndi, double new_x, double new_y);
  double delta(Node* ndi, Node* ndj);

  bool generate(Node* ndi);

  // CUDA functions.
  void compute_search_bins(int begin, int end);
  void compute_search_bins(Node* ndi);

  // Standard stuff.
  DetailedMgr* mgr_;
  Architecture* arch_;
  Network* network_;
  RoutingParams* rt_;

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

  // GPU stuff.
  int numThreads_;
  int numBlocks_;
  int maxThreadsPerBlock_;

};

}  // namespace dpo
