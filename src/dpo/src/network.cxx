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
#include "network.h"

namespace dpo {

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Node::Node() = default;
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool Node::adjustCurrOrient(const unsigned newOri)
{
  // Change the orientation of the cell, but leave the lower-left corner
  // alone.  This means changing the locations of pins and possibly
  // changing the edge types as well as the height and width.
  unsigned curOri = currentOrient_;
  if (newOri == curOri) {
    return true;
  }

  if (curOri == Orientation_E || curOri == Orientation_FE
      || curOri == Orientation_FW || curOri == Orientation_W) {
    if (newOri == Orientation_N || curOri == Orientation_FN
        || curOri == Orientation_FS || curOri == Orientation_S) {
      // Rotate the cell counter-clockwise by 90 degrees.
      for (Pin* pin : pins_) {
        const double dx = pin->getOffsetX();
        const double dy = pin->getOffsetY();
        pin->setOffsetX(-dy);
        pin->setOffsetY(dx);
      }
      std::swap(h_, w_);
      if (curOri == Orientation_E) {
        curOri = Orientation_N;
      } else if (curOri == Orientation_FE) {
        curOri = Orientation_FS;
      } else if (curOri == Orientation_FW) {
        curOri = Orientation_FN;
      } else {
        curOri = Orientation_S;
      }
    }
  } else {
    if (newOri == Orientation_E || curOri == Orientation_FE
        || curOri == Orientation_FW || curOri == Orientation_W) {
      // Rotate the cell clockwise by 90 degrees.
      for (Pin* pin : pins_) {
        const double dx = pin->getOffsetX();
        const double dy = pin->getOffsetY();
        pin->setOffsetX(dy);
        pin->setOffsetY(-dx);
      }
      std::swap(h_, w_);
      if (curOri == Orientation_N) {
        curOri = Orientation_E;
      } else if (curOri == Orientation_FS) {
        curOri = Orientation_FE;
      } else if (curOri == Orientation_FN) {
        curOri = Orientation_FW;
      } else {
        curOri = Orientation_W;
      }
    }
  }
  // Both the current and new orientations should be {N, FN, FS, S} or {E, FE,
  // FW, W}.
  int mX = 1;
  int mY = 1;
  bool changeEdgeTypes = false;
  if (curOri == Orientation_E || curOri == Orientation_FE
      || curOri == Orientation_FW || curOri == Orientation_W) {
    const bool test1 = (curOri == Orientation_E || curOri == Orientation_FW);
    const bool test2 = (newOri == Orientation_E || newOri == Orientation_FW);
    if (test1 != test2) {
      mX = -1;
    }
    const bool test3 = (curOri == Orientation_E || curOri == Orientation_FE);
    const bool test4 = (newOri == Orientation_E || newOri == Orientation_FE);
    if (test3 != test4) {
      changeEdgeTypes = true;
      mY = -1;
    }
  } else {
    const bool test1 = (curOri == Orientation_N || curOri == Orientation_FS);
    const bool test2 = (newOri == Orientation_N || newOri == Orientation_FS);
    if (test1 != test2) {
      changeEdgeTypes = true;
      mX = -1;
    }
    const bool test3 = (curOri == Orientation_N || curOri == Orientation_FN);
    const bool test4 = (newOri == Orientation_N || newOri == Orientation_FN);
    if (test3 != test4) {
      mY = -1;
    }
  }

  for (Pin* pin : pins_) {
    pin->setOffsetX(pin->getOffsetX() * mX);
    pin->setOffsetY(pin->getOffsetY() * mY);
  }
  if (changeEdgeTypes) {
    std::swap(etl_, etr_);
  }
  currentOrient_ = newOri;
  return true;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Pin::Pin() = default;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Network::~Network()
{
  // Delete edges.
  for (auto edge : edges_) {
    delete edge;
  }
  edges_.clear();
  edgeNames_.clear();

  // Delete cells.
  for (auto node : nodes_) {
    delete node;
  }
  nodes_.clear();
  nodeNames_.clear();

  // Delete pins.
  for (auto pin : pins_) {
    delete pin;
  }
  pins_.clear();
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Edge* Network::createAndAddEdge()
{
  // Just allocate an edge, append it and give it the id
  // that corresponds to its index.
  const int id = (int) edges_.size();
  Edge* ptr = new Edge();
  ptr->setId(id);
  edges_.push_back(ptr);
  return ptr;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Node* Network::createAndAddNode()
{
  // Just allocate a node, append it and give it the id
  // that corresponds to its index.
  const int id = (int) nodes_.size();
  Node* ptr = new Node();
  ptr->setId(id);
  nodes_.push_back(ptr);
  return ptr;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::createAndAddBlockage(const odb::Rect& bounds)
{
  blockages_.emplace_back(bounds);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Node* Network::createAndAddFillerNode(const int left,
                                      const int bottom,
                                      const int width,
                                      const int height)
{
  Node* ndi = new Node();
  const int id = (int) nodes_.size();
  ndi->setFixed(Node::FIXED_XY);
  ndi->setType(Node::FILLER);
  ndi->setId(id);
  ndi->setHeight(height);
  ndi->setWidth(width);
  ndi->setBottom(bottom);
  ndi->setLeft(left);
  nodes_.push_back(ndi);
  return getNode(id);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Pin* Network::createAndAddPin()
{
  Pin* ptr = new Pin();
  ptr->setId((int) pins_.size());
  pins_.push_back(ptr);
  return ptr;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Pin* Network::createAndAddPin(Node* nd, Edge* ed)
{
  Pin* ptr = createAndAddPin();
  ptr->node_ = nd;
  ptr->edge_ = ed;
  ptr->node_->pins_.push_back(ptr);
  ptr->edge_->pins_.push_back(ptr);
  return ptr;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::reorderAndReindexNodes() 
{
  // do this to ensure that when iterating through nodes,
  // map the first group to movable_nodes
  // map the second group to terminal nodes (and misc fixed nodes)
  // map the last group to filler nodes
  std::vector<Node*> movable_nodes;
  std::vector<Node*> terminal_nodes;
  std::vector<Node*> filler_nodes;

  // Save mapping from old node ID to Node*
  std::unordered_map<int, Node*> old_id_to_node;
  for (Node* node : nodes_) {
    old_id_to_node[node->getId()] = node;
  }

  for (Node* node : nodes_) {
    if (node->getType() == Node::CELL && !node->isFixed()) {
      movable_nodes.push_back(node);
    } else if (node->getType() == Node::TERMINAL) {
      terminal_nodes.push_back(node);
    } else if (node->getType() == Node::FILLER) {
      filler_nodes.push_back(node);
    } else {
      terminal_nodes.push_back(node); // add all other nodes to terminal (general fixed nodes) for now
    }
  }

  setNumMovableNodes(movable_nodes.size());
  setNumTerminalNodes(terminal_nodes.size());
  setNumFillerNodes(filler_nodes.size());

  nodes_.clear();
  nodes_.insert(nodes_.end(), movable_nodes.begin(), movable_nodes.end());
  nodes_.insert(nodes_.end(), terminal_nodes.begin(), terminal_nodes.end());
  nodes_.insert(nodes_.end(), filler_nodes.begin(), filler_nodes.end());

  std::unordered_map<int, std::string> new_nodeNames;
  for (int new_id = 0; new_id < static_cast<int>(nodes_.size()); ++new_id) {
    Node* node = nodes_[new_id];
    int old_id = node->getId();  // current ID before reassignment is still old ID
    node->setId(new_id);         // assign new ID
    auto it = nodeNames_.find(old_id);
    if (it != nodeNames_.end()) {
      new_nodeNames[new_id] = it->second;
    }
  }

  nodeNames_ = std::move(new_nodeNames);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::sanityCheckAndPrintStats() {
  int num_movable = 0;
  int num_terminals = 0;
  int num_fillers = 0;

  // Count types and verify IDs match index
  for (size_t i = 0; i < nodes_.size(); ++i) {
    const Node* node = nodes_[i];
    if (node->getId() != static_cast<int>(i)) {
      std::cerr << "[INFO GPU-DPO] Error: Node ID mismatch: expected " << i << ", found " << node->getId() << "\n";
    }

    if (node->getType() == Node::CELL) {
      ++num_movable;
    } else if (node->getType() == Node::TERMINAL) {
      ++num_terminals;
    } else if (node->getType() == Node::FILLER) {
      ++num_fillers;
    } else {
      std::cerr << "[INFO GPU-DPO] Error: Unknown node type in node " << i << "\n";
    }
  }

  std::cout << "[INFO GPU-DPO] === Network Node Summary ===\n";
  std::cout << "Total Nodes     : " << nodes_.size() << "\n";
  std::cout << "Movable Nodes   : " << getNumMovableNodes() << "\n";
  std::cout << "Terminal Nodes  : " << getNumTerminalNodes() << "\n";
  std::cout << "Filler Nodes    : " << getNumFillerNodes() << "\n";
  assert(nodes_.size() == num_movable + num_terminals + num_fillers);

  // Check pins
  for (int i = 0; i < pins_.size(); ++i) {
    const Pin* pin = pins_[i];
    const Node* node = pin->getNode();
    if (node != nodes_[node->getId()]) {
      std::cerr << "[INFO GPU-DPO] Error: Pin " << i << " points to node with ID " << node->getId()
                << ", but nodes_[" << node->getId() << "] != pin->getNode()\n";
    }
  }

  // Check nets
  for (int i = 0; i < edges_.size(); ++i) {
    const Edge* edge = edges_[i];
    for (const Pin* pin : edge->getPins()) {
      if (pin == nullptr || pin->getNode() == nullptr) {
        std::cerr << "[INFO GPU-DPO] Error: Null pin or node in edge " << i << "\n";
      }
    }
  }

  std::cout << "[INFO GPU-DPO] Error: Sanity check completed.\n";
}

}  // namespace dpo
