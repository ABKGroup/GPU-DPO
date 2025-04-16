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
  std::vector<float> node_size_x;
  std::vector<float> node_size_y;

  /* pin info */
  std::vector<float> pin_offset_x;      // same thing as flat_node2pin_map only it stores the pin offsets 
  std::vector<float> pin_offset_y;      // same thing as flat_node2pin_map only it stores the pin offsets 

  std::vector<int> flat_node2pin_start_map;   // ending index bounding the range of pins for each node
  std::vector<int> flat_node2pin_map;   // a list of pin IDs indexed by the node (size of num_nodes)
  std::vector<int> pin2node_map;        // a list of node IDs indexed by the pin (size of num_pins)

  /* net info */
  std::vector<int> flat_net2pin_start_map;
  std::vector<int> flat_net2pin_map;
  std::vector<int> pin2net_map;
  std::vector<int> net_mask;

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
  int num_nodes;
  int num_movable_nodes;
  int num_regions;

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
  void debugNodePins();
  void debugNetPins();

  // Other
  int skipNetsLargerThanThis_;
};

} // namespace dpo