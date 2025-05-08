// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#include "network.h"

#include <memory>

#include "PlacementDRC.h"
#include "infrastructure/Grid.h"
#include "infrastructure/Objects.h"
#include "odb/db.h"
namespace dpl {

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Node* Network::getNode(odb::dbInst* inst)
{
  auto it = inst_to_node_idx_.find(inst);
  if (it == inst_to_node_idx_.end()) {
    return nullptr;
  }
  return nodes_[it->second].get();
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Node* Network::getNode(odb::dbBTerm* term)
{
  auto it = term_to_node_idx_.find(term);
  if (it == term_to_node_idx_.end()) {
    return nullptr;
  }
  return nodes_[it->second].get();
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Master* Network::getMaster(odb::dbMaster* db_master)
{
  auto it = master_to_idx_.find(db_master);
  if (it == master_to_idx_.end()) {
    return nullptr;
  }
  return masters_[it->second].get();
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
Pin* Network::addPin(odb::dbITerm* term)
{
  auto upin = std::make_unique<Pin>();
  Pin* ptr = upin.get();
  auto mTerm = term->getMTerm();
  auto master = mTerm->getMaster();
  // Due to old bookshelf, my offsets are from the
  // center of the cell whereas in DEF, it's from
  // the bottom corner.
  auto ww = mTerm->getBBox().dx();
  auto hh = mTerm->getBBox().dy();
  auto xx = mTerm->getBBox().xCenter();
  auto yy = mTerm->getBBox().yCenter();
  auto dx = xx - ((int) master->getWidth() / 2);
  auto dy = yy - ((int) master->getHeight() / 2);

  upin->setId((int) pins_.size());
  upin->setOffsetX(DbuX{dx});
  upin->setOffsetY(DbuY{dy});
  upin->setPinHeight(DbuY{hh});
  upin->setPinWidth(DbuX{ww});
  upin->setPinLayer(0);  // Set to zero since not currently used.
  pins_.emplace_back(std::move(upin));
  return ptr;
}
Pin* Network::addPin(odb::dbBTerm* term)
{
  auto upin = std::make_unique<Pin>();
  Pin* ptr = upin.get();
  upin->setId((int) pins_.size());
  pins_.emplace_back(std::move(upin));
  return ptr;
}
void Network::connect(Pin* pin, Node* node)
{
  pin->setNode(node);
  node->addPin(pin);
}
void Network::connect(Pin* pin, Edge* edge)
{
  pin->setEdge(edge);
  edge->addPin(pin);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::addEdge(odb::dbNet* net)
{
  // Just allocate an edge, append it and give it the id
  // that corresponds to its index.
  const int id = (int) edges_.size();
  auto uedge = std::make_unique<Edge>();
  uedge->setId(id);
  Edge* edge = uedge.get();
  ////////////////////////
  net_to_edge_idx_[net] = id;
  // Name of edge.
  setEdgeName(id, net->getName().c_str());

  for (auto iterm : net->getITerms()) {
    if (!iterm->getInst()->getMaster()->isCoreAutoPlaceable()) {
      continue;
    }
    Pin* ptr = addPin(iterm);
    connect(ptr, getNode(iterm->getInst()));
    connect(ptr, edge);
  }
  for (auto bterm : net->getBTerms()) {
    Pin* ptr = addPin(bterm);
    connect(ptr, getNode(bterm));
    connect(ptr, edge);
  }

  ////////////////////////
  edges_.emplace_back(std::move(uedge));
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
namespace {
/**
 * @brief Calculates the difference between the passed parent_segment and the
 * vector segs The parent segment containts all the segments in the segs vector.
 * This function computes the difference between the parent segment and the
 * child segments. It first sorts the segs vector and merges intersecting ones.
 * Then it calculates the difference and returns a list of segments.
 */
std::vector<Rect> difference(const Rect& parent_segment,
                             const std::vector<Rect>& segs)
{
  if (segs.empty()) {
    return {parent_segment};
  }
  bool is_horizontal = parent_segment.yMin() == parent_segment.yMax();
  std::vector<Rect> sorted_segs = segs;
  // Sort segments by start coordinate
  std::sort(
      sorted_segs.begin(),
      sorted_segs.end(),
      [is_horizontal](const Rect& a, const Rect& b) {
        return (is_horizontal ? a.xMin() < b.xMin() : a.yMin() < b.yMin());
      });
  // Merge overlapping segments
  auto prev_seg = sorted_segs.begin();
  auto curr_seg = prev_seg;
  for (++curr_seg; curr_seg != sorted_segs.end();) {
    if (curr_seg->intersects(*prev_seg)) {
      prev_seg->merge(*curr_seg);
      curr_seg = sorted_segs.erase(curr_seg);
    } else {
      prev_seg = curr_seg++;
    }
  }
  // Get the difference
  const int start
      = is_horizontal ? parent_segment.xMin() : parent_segment.yMin();
  const int end = is_horizontal ? parent_segment.xMax() : parent_segment.yMax();
  int current_pos = start;
  std::vector<Rect> result;
  for (const Rect& seg : sorted_segs) {
    int seg_start = is_horizontal ? seg.xMin() : seg.yMin();
    int seg_end = is_horizontal ? seg.xMax() : seg.yMax();
    if (seg_start > current_pos) {
      if (is_horizontal) {
        result.emplace_back(current_pos,
                            parent_segment.yMin(),
                            seg_start,
                            parent_segment.yMax());
      } else {
        result.emplace_back(parent_segment.xMin(),
                            current_pos,
                            parent_segment.xMax(),
                            seg_start);
      }
    }
    current_pos = seg_end;
  }
  // Add the remaining end segment if it exists
  if (current_pos < end) {
    if (is_horizontal) {
      result.emplace_back(
          current_pos, parent_segment.yMin(), end, parent_segment.yMax());
    } else {
      result.emplace_back(
          parent_segment.xMin(), current_pos, parent_segment.xMax(), end);
    }
  }

  return result;
}

Rect getBoundarySegment(const Rect& bbox,
                        const odb::dbMasterEdgeType::EdgeDir dir)
{
  Rect segment(bbox);
  switch (dir) {
    case odb::dbMasterEdgeType::RIGHT:
      segment.set_xlo(bbox.xMax());
      break;
    case odb::dbMasterEdgeType::LEFT:
      segment.set_xhi(bbox.xMin());
      break;
    case odb::dbMasterEdgeType::TOP:
      segment.set_ylo(bbox.yMax());
      break;
    case odb::dbMasterEdgeType::BOTTOM:
      segment.set_yhi(bbox.yMin());
      break;
  }
  return segment;
}

std::pair<int, int> getMasterPwrs(odb::dbMaster* master)
{
  int maxPwr = std::numeric_limits<int>::min();
  int minPwr = std::numeric_limits<int>::max();
  int maxGnd = std::numeric_limits<int>::min();
  int minGnd = std::numeric_limits<int>::max();

  bool isVdd = false;
  bool isGnd = false;
  for (odb::dbMTerm* mterm : master->getMTerms()) {
    if (mterm->getSigType() == odb::dbSigType::POWER) {
      isVdd = true;
      for (odb::dbMPin* mpin : mterm->getMPins()) {
        // Geometry or box?
        const int y = mpin->getBBox().yCenter();
        minPwr = std::min(minPwr, y);
        maxPwr = std::max(maxPwr, y);
      }
    } else if (mterm->getSigType() == odb::dbSigType::GROUND) {
      isGnd = true;
      for (odb::dbMPin* mpin : mterm->getMPins()) {
        // Geometry or box?
        const int y = mpin->getBBox().yCenter();
        minGnd = std::min(minGnd, y);
        maxGnd = std::max(maxGnd, y);
      }
    }
  }
  int topPwr = Architecture::Row::Power_UNK;
  int botPwr = Architecture::Row::Power_UNK;
  if (isVdd && isGnd) {
    topPwr = (maxPwr > maxGnd) ? Architecture::Row::Power_VDD
                               : Architecture::Row::Power_VSS;
    botPwr = (minPwr < minGnd) ? Architecture::Row::Power_VDD
                               : Architecture::Row::Power_VSS;
  }
  return {topPwr, botPwr};
}

}  // namespace

Master* Network::addMaster(odb::dbMaster* db_master,
                           const Grid* grid,
                           const PlacementDRC* drc_engine)
{
  const auto it = master_to_idx_.find(db_master);
  if (it != master_to_idx_.end()) {
    return masters_[it->second].get();
  }
  auto umaster = std::make_unique<Master>();
  auto master = umaster.get();
  const int id = masters_.size();
  masters_.emplace_back(std::move(umaster));
  master_to_idx_[db_master] = id;
  Rect bbox;
  db_master->getPlacementBoundary(bbox);
  master->setBBox(bbox);
  master->setMultiRow(grid->isMultiHeight(db_master));
  auto master_pwrs = getMasterPwrs(db_master);
  master->setTopPowerType(master_pwrs.first);
  master->setBottomPowerType(master_pwrs.second);
  master->clearEdges();
  if (!drc_engine->hasCellEdgeSpacingTable()) {
    return master;
  }
  if (db_master->getType()
      == odb::dbMasterType::CORE_SPACER) {  // Skip fillcells
    return master;
  }
  std::map<odb::dbMasterEdgeType::EdgeDir, std::vector<Rect>> typed_segs;
  int num_rows = grid->gridHeight(db_master).v;
  for (auto edge : db_master->getEdgeTypes()) {
    auto dir = edge->getEdgeDir();
    Rect edge_rect = getBoundarySegment(bbox, dir);
    if (dir == odb::dbMasterEdgeType::TOP
        || dir == odb::dbMasterEdgeType::BOTTOM) {
      if (edge->getRangeBegin() != -1) {
        edge_rect.set_xlo(edge_rect.xMin() + edge->getRangeBegin());
        edge_rect.set_xhi(edge_rect.xMin() + edge->getRangeEnd());
      }
    } else {
      auto dy = edge_rect.dy();
      auto row_height = dy / num_rows;
      auto half_row_height = row_height / 2;
      if (edge->getCellRow() != -1) {
        edge_rect.set_ylo(edge_rect.yMin()
                          + (edge->getCellRow() - 1) * row_height);
        edge_rect.set_yhi(
            std::min(edge_rect.yMax(), edge_rect.yMin() + row_height));
      } else if (edge->getHalfRow() != -1) {
        edge_rect.set_ylo(edge_rect.yMin()
                          + (edge->getHalfRow() - 1) * half_row_height);
        edge_rect.set_yhi(
            std::min(edge_rect.yMax(), edge_rect.yMin() + half_row_height));
      }
    }
    typed_segs[dir].push_back(edge_rect);
    const auto edge_type_idx = drc_engine->getEdgeTypeIdx(edge->getEdgeType());
    if (edge_type_idx != -1) {
      // consider only edge types defined in the spacing table
      master->addEdge(dpl::MasterEdge(edge_type_idx, edge_rect));
    }
  }
  const auto default_edge_type_idx = drc_engine->getEdgeTypeIdx("DEFAULT");
  if (default_edge_type_idx == -1) {
    return master;
  }
  // Add the remaining DEFAULT un-typed segments
  for (size_t dir_idx = 0; dir_idx <= 3; dir_idx++) {
    const auto dir = (odb::dbMasterEdgeType::EdgeDir) dir_idx;
    const auto parent_seg = getBoundarySegment(bbox, dir);
    const auto default_segs = difference(parent_seg, typed_segs[dir]);
    for (const auto& seg : default_segs) {
      master->addEdge(dpl::MasterEdge(default_edge_type_idx, seg));
    }
  }
  return master;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::addNode(odb::dbInst* inst)
{
  Node ndi;
  const int id = nodes_.size();
  ndi.setId(id);
  setNodeName(ndi.getId(), inst->getName().c_str());
  ndi.setDbInst(inst);
  ndi.setType(Node::CELL);
  auto master = getMaster(inst->getMaster());
  ndi.setMaster(master);
  ndi.setFixed(inst->isFixed());
  ndi.setPlaced(inst->isFixed());

  ndi.setOrient(odb::dbOrientType::R0);
  ndi.setHeight(DbuY{(int) inst->getMaster()->getHeight()});
  ndi.setWidth(DbuX{(int) inst->getMaster()->getWidth()});
  ndi.setOrigLeft(DbuX{inst->getBBox()->xMin() - core_.xMin()});
  ndi.setOrigBottom(DbuY{inst->getBBox()->yMin() - core_.yMin()});
  ndi.setLeft(ndi.getOrigLeft());
  ndi.setBottom(ndi.getOrigBottom());
  ndi.setBottomPower(master->getBottomPowerType());
  ndi.setTopPower(master->getTopPowerType());
  nodes_.emplace_back(std::make_unique<Node>(ndi));
  inst_to_node_idx_[inst] = id;
  ++cells_cnt_;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::addNode(odb::dbBTerm* bterm)
{
  // Just allocate a node, append it and give it the id
  // that corresponds to its index.
  Node ndi;
  const int id = nodes_.size();
  ndi.setId(id);
  setNodeName(ndi.getId(), bterm->getName().c_str());

  // Fill in data.
  ndi.setType(Node::TERMINAL);
  ndi.setFixed(true);
  ndi.setOrient(odb::dbOrientType::R0);

  DbuX ww(bterm->getBBox().xMax() - bterm->getBBox().xMin());
  DbuY hh(bterm->getBBox().yMax() - bterm->getBBox().yMax());

  ndi.setHeight(hh);
  ndi.setWidth(ww);
  ndi.setOrigLeft(DbuX{bterm->getBBox().xMin() - core_.xMin()});
  ndi.setOrigBottom(DbuY{bterm->getBBox().yMin() - core_.yMin()});
  ndi.setLeft(ndi.getOrigLeft());
  ndi.setBottom(ndi.getOrigBottom());

  // Not relevant for terminal.
  ndi.setBottomPower(Architecture::Row::Power_UNK);
  ndi.setTopPower(Architecture::Row::Power_UNK);
  term_to_node_idx_[bterm] = id;
  nodes_.emplace_back(std::make_unique<Node>(ndi));
  ++terminals_cnt_;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::createAndAddBlockage(const odb::Rect& bounds)
{
  blockages_.emplace_back(bounds);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::addFillerNode(const DbuX left,
                            const DbuY bottom,
                            const DbuX width,
                            const DbuY height)
{
  Node ndi;
  const int id = (int) nodes_.size();
  ndi.setFixed(true);
  ndi.setType(Node::FILLER);
  ndi.setId(id);
  ndi.setHeight(height);
  ndi.setWidth(width);
  ndi.setBottom(bottom);
  ndi.setLeft(left);
  nodes_.emplace_back(std::make_unique<Node>(ndi));
  setNodeName(id, "FILLER_" + std::to_string(filler_cnt_++));
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::clear()
{
  nodes_.clear();
  masters_.clear();
  edges_.clear();
  pins_.clear();
  blockages_.clear();
  edgeNames_.clear();
  nodeNames_.clear();
  inst_to_node_idx_.clear();
  term_to_node_idx_.clear();
  master_to_idx_.clear();
  net_to_edge_idx_.clear();
  cells_cnt_ = 0;
  terminals_cnt_ = 0;
  filler_cnt_ = 0;
  numMovableNodes_ = 0;
  numTerminalNodes_ = 0;
  numFillerNodes_ = 0;
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::reorderAndReindexNodes()
{
  // do this to ensure that when iterating through nodes,
  // map the first group to movable nodes
  // map the second group to fixed/terminal nodes
  // map the last group to filler nodes
  std::vector<Node*> movableNodes;
  std::vector<Node*> terminalNodes;
  std::vector<Node*> fillerNodes;

  // save mapping from old node id to Node*
  std::unordered_map<int, Node*> oldIdToNode;
  for (Node* node : nodes_) {
    oldIdToNode[node->getId()] = node;
  }

  for (Node* node : nodes_) {
    if (node->getType() == Node::CELL && !node->isFixed()) {
      movableNodes.push_back(node);
    } else if (node->getType() == Node::TERMINAL) {
      terminalNodes.push_back(node);
    } else if (node->getType() == Node::FILLER) {
      fillerNodes.push_back(node);
    } else {
      terminalNodes.push_back(node);  // add all other fixed nodes to terminal
    }
  }

  setNumMovableNodes(movableNodes.size());
  setNumTerminalNodes(terminalNodes.size());
  setNumFillerNodes(fillerNodes.size());

  nodes_.clear();
  nodes_.insert(nodes_.end(), movableNodes.begin(), movableNodes.end());
  nodes_.insert(nodes_.end(), terminalNodes.begin(), terminalNodes.end());
  nodes_.insert(nodes_.end(), fillerNodes.begin(), fillerNodes.end());

  std::unordered_map<int, std::string> newNodeNames;
  for (int newId = 0; newId < static_cast<int>(nodes_.size()); newId++) {
    Node* node = nodes_[newId];
    int oldId = node->getId();    // current ID before old assignment is still old ID
    node->setId(newId);           // assign new ID
    auto it = nodeNames_.find(oldId);
    if (it != nodeNames_.end()) {
      newNodeNames[newId] = it->second;
    }
  }

  nodeNames_ = std::move(newNodeNames);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void Network::sanityCheckAndPrintStats() {
  int numMovable = 0;
  int numTerminals = 0;
  int numFillers = 0;

  // count types and verify IDs match index
  for (size_t i = 0; i < nodes_.size(); i++) {
    const Node* node = nodes_[i];
    if (node->getId() != static_cast<int>(i)) {
      std::cerr << "[INFO GPU-DPO] Error: Node ID mismatch: expected " << i << ", found " << node->getId() << "\n";
    }

    if (node->getType() == Node::CELL && !node->getFixed()) {
      numMovable++;
    } else if (node->getType() == Node::TERMINAL) {
      numTerminals++;
    } else if (node->getType() == Node::FILLER) {
      numFillers++;
    } else {
      std::cerr << "[INFO GPU-DPO] Error: Unknown node type in node " << i << "\n";
    }
  }

  std::cout << "[INFO GPU-DPO] === Network Node Summary ===\n";
  std::cout << "Total Nodes     : " << nodes_.size() << "\n";
  std::cout << "Movable Nodes   : " << getNumMovableNodes() << "\n";
  std::cout << "Terminal Nodes  : " << getNumTerminalNodes() << "\n";
  std::cout << "Filler Nodes    : " << getNumFillerNodes() << "\n";
  assert(nodes_.size() == numMovable + numTerminals + numFillers);

  // Check pins
  for (int i = 0; i < pins_.size(); i++) {
    const Pin* pin = pins_[i];
    const Node* node = pin->getNode();
    if (node != nodes_[node->getId()]) {
      std::cerr << "[INFO GPU-DPO] Error: Pin " << i << " points to node with ID " << node->getId()
                << ", but nodes_[" << node->getId() << "] != pin->getNode()\n";
    }
  }

  // Check nets
  for (int i = 0; i < edges_.size(); i++) {
    const Edge* edge = edges_[i];
    for (const Pin* pin : edge->getPins()) {
      if (pin == nullptr || pin->getNode() == nullptr) {
        std::cerr << "[INFO GPU-DPO] Error: Null pin or node in edge " << i << "\n";
      }
    }
  }

  std::cout << "[INFO GPU-DPO] Sanity check completed.\n";
}

}  // namespace dpl
