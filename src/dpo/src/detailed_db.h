#include <vector>
#include <iostream>
#include <tuple>
#include <string>

#include "architecture.h"
#include "detailed_manager.h"
#include "network.h"
#include "orientation.h"

namespace dpo {

class DetailedPlaceDB {
public:
  DetailedPlaceDB(Network* network, Architecture* arch, DetailedMgr* mgr);

  ~DetailedPlaceDB();

  void createDetailedPlaceDB();

  Network* network_;
  Architecture* arch_;
  DetailedMgr* mgr_;

  /* node info */
  std::vector<float> init_x;  // original pos (keep it const except committing)
  std::vector<float> init_y;  // original pos (keep it const except committing)
  std::vector<float> x;       // mutable/cached pos (current)
  std::vector<float> y;       // mutable/cached pos (current)
  std::vector<float> node_size_x; // width of the nodes
  std::vector<float> node_size_y; // height of the nodes

  /* pin info */
  std::vector<float> pin_offset_x;  // same thing as flat_node2pin_map only it stores the pin offsets 
  std::vector<float> pin_offset_y;  // same thing as flat_node2pin_map only it stores the pin offsets 

  std::vector<int> flat_node2pin_start_map;   // ending index bounding the range of pins for each node
  std::vector<int> flat_node2pin_map;     // a list of pin IDs indexed by the node (size of num_nodes)
  std::vector<int> pin2node_map;        // a list of node IDs indexed by the pin (size of num_pins)

  /* net info */
  std::vector<int> flat_net2pin_start_map;  // bookmark for start index of each net in flat_net2pin_map
  std::vector<int> flat_net2pin_map;        // pins of each net, pins belonging to same net are abutting
  std::vector<int> pin2net_map;   // maps pin index to net index
  std::vector<int> net_mask;  // whether a net should be considered in wirelength calculation

  /* fence info */
  std::vector<int> flat_region_boxes_start;
  std::vector<float> flat_region_boxes;
  std::vector<int> node2fence_region_map;

  /* chip info */
  float xl;
  float yl;
  float xh;
  float yh;

  /* row info */
  int num_sites_x;
  int num_sites_y;

  int num_pins;
  int num_nets;
  int num_nodes;  // number of nodes, including movable, terminal (fixed), and filler nodes
  int num_movable_nodes;  // number of movable nodes, node id in range of [0, num_movable_nodes)
  int num_terminal_NIs;   // number of filler nodes, node id in range of [num_movable_nodes, num_nodes-num_filler_nodes)
  int num_filler_nodes;   // number of terminal NIs (fixed IO pins), node id in range of [num_nodes-num_filler_nodes, num_nodes) 
  int num_regions;
  int region_boxes_size;

  float site_width;
  float row_height;

  int num_threads;


private:
  void createNodeInfo();
  void createPinInfo();
  void createNetInfo();
  void createFenceInfo();
  void createChipInfo();
  void createRowInfo();
  void compareFlattenedAndNetworkHPWL();

  // Other
  int skipNetsLargerThanThis_ = 100;
};

} // namespace dpo