#include "detailed_global.h"

#include <boost/tokenizer.hpp>
#include <vector>
#include <iostream>

#include "detailed_hpwl.h"
#include "detailed_manager.h"
#include "rectangle.h"
#include "utl/Logger.h"

#define MAX_NODE_DEGREE 20
#define MAX_NET_DEGREE 100

namespace dpo {

using utl::DPO;

DetailedGlobalSwap::DetailedGlobalSwap(Architecture* arch,
                                    Network* network,
                                    RoutingParams* rt)
: DetailedGenerator("global swap"),
    mgr_(nullptr),
    arch_(arch),
    network_(network),
    rt_(rt),
    skipNetsLargerThanThis_(100),
    traversal_(0),
    attempts_(0),
    moves_(0),
    swaps_(0)
{
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
DetailedGlobalSwap::DetailedGlobalSwap()
    : DetailedGlobalSwap(nullptr, nullptr, nullptr)
{
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::run(DetailedMgr* mgrPtr, DetailedPlaceData& db, const std::string& command)
{
  // A temporary interface to allow for a string which we will decode to create
  // the arguments.
  boost::char_separator<char> separators(" \r\t\n;");
  boost::tokenizer<boost::char_separator<char>> tokens(command, separators);
  std::vector<std::string> args;
  for (const auto& token : tokens) {
    args.push_back(token);
  }
  run(mgrPtr, db, args);
}

template <typename T1, typename T2>
__device__ inline void device_swap(T1& a, T2& b) {
  T1 tmp = a;
  a = b;
  b = tmp;
}

template <typename T>
struct __align__(16) SwapCandidate {
  T cost;
  T node_xl[2][2];  ///< [0][] for node, [1][] for target node, [][0] for old,
                    ///< [][1] for new
  T node_yl[2][2];
  int node_id[2];  ///< [0] for node, [1] for target node
};

struct SearchBinInfo {
  int cx;
  int cy;
};

template <typename T>
struct __align__(16) NetPinPair {
  int net_id;
  T pin_offset_x;
  T pin_offset_y;
};

template <typename T>
struct __align__(16) NodePinPair {
  int node_id;
  T pin_offset_x;
  T pin_offset_y;
};

template <typename T>
struct SwapState {
  int* ordered_nodes = nullptr;

  Space<T>* spaces = nullptr;

  PitchNestedVector<int> row2node_map;
  RowMapIndex* node2row_map = nullptr;

  PitchNestedVector<int> bin2node_map;
  BinMapIndex* node2bin_map = nullptr;

  // PitchNestedVector<NetPinPair<T> > node2netpin_map;
  PitchNestedVector<int> node2net_map;
  PitchNestedVector<NodePinPair<T>> net2nodepin_map;

  int* search_bins = nullptr;
  int search_bin_strategy;  ///< how to compute search bins for eahc cell: 0 for
                            ///< cell bin, 1 for optimal region

  SwapCandidate<T>* candidates;

  double*
      net_hpwls;  ///< HPWL for each net, use integer to get consistent values
  unsigned char* node_markers;  ///< markers for cells

  int batch_size;
  int max_num_candidates_per_row;
  int max_num_candidates;
  int max_num_candidates_all;

  int pair_hpwl_computing_strategy;  ///< 0: for the original node2pin_map and
                                     ///< net2pin_map; 1: for node2net_map and
                                     ///< net2node_map, which requires
                                     ///< additional memory
};

template <typename T>
struct ItemWithIndex {
  T value;
  int index;
};

template <typename T>
struct ReduceMinOP {
  __host__ __device__ ItemWithIndex<T> operator()(
      const ItemWithIndex<T>& a, const ItemWithIndex<T>& b) const {
    return (a.value < b.value) ? a : b;
  }
};

template <typename T, int ThreadsPerBlock = 128>
__global__ void reduce_min_2d_cub(SwapCandidate<T>* candidates,
                                  int max_num_elements) {
  typedef cub::BlockReduce<ItemWithIndex<T>, ThreadsPerBlock> BlockReduce;

  __shared__ typename BlockReduce::TempStorage temp_storage;

  auto row_candidates = candidates + blockIdx.x * max_num_elements;

  ItemWithIndex<T> thread_data;

  thread_data.value = cuda::numeric_limits<float>::max();
  thread_data.index = 0;
  for (int col = threadIdx.x; col < max_num_elements; col += ThreadsPerBlock) {
    T cost = row_candidates[col].cost;
    if (cost < thread_data.value) {
      thread_data.value = cost;
      thread_data.index = col;
    }
  }

  __syncthreads();

  // Compute the block-wide max for thread0
  ItemWithIndex<T> aggregate = BlockReduce(temp_storage).Reduce(thread_data, ReduceMinOP<T>(), max_num_elements);

  __syncthreads();

  if (threadIdx.x == 0) {
    row_candidates[0] = row_candidates[aggregate.index];
  }
}

inline __device__ float compute_pair_hpwl_general(const int* __restrict__ flat_node2pin_start_map,
                                                  const int* __restrict__ flat_node2pin_map,
                                                  const int* __restrict__ pin2net_map,
                                                  const float xh,
                                                  const float yh,
                                                  const float xl,
                                                  const float yl,
                                                  const int* __restrict__ net_mask,
                                                  const int* __restrict__ flat_net2pin_start_map,
                                                  const int* __restrict__ flat_net2pin_map,
                                                  const int* __restrict__ pin2node_map,
                                                  const float* __restrict__ x,
                                                  const float* __restrict__ y,
                                                  const float* __restrict__ pin_offset_x,
                                                  const float* __restrict__ pin_offset_y,
                                                  int node_id,
                                                  float node_xl,
                                                  float node_yl,
                                                  int target_node_id,
                                                  float target_node_xl,
                                                  float target_node_yl,
                                                  int skip_node_id) {
  float cost = 0;
  int node2pin_id = flat_node2pin_start_map[node_id];
  const int node2pin_id_end = flat_node2pin_start_map[node_id + 1];
  for (; node2pin_id < node2pin_id_end; ++node2pin_id) {
    int node_pin_id = flat_node2pin_map[node2pin_id];
    int net_id = pin2net_map[node_pin_id];
    Box<float> box(xh, yh, xl, yl);
    int flag = net_mask[net_id];
    int net2pin_id = flat_net2pin_start_map[net_id];
    const int net2pin_id_end = flat_net2pin_start_map[net_id + 1] * flag;
    for (; net2pin_id < net2pin_id_end; ++net2pin_id) {
      int net_pin_id = flat_net2pin_map[net2pin_id];
      int other_node_id = pin2node_map[net_pin_id];
      float xxl = x[other_node_id] /*+ 0.5 * node_size_x[other_node_id]*/;
      float yyl = y[other_node_id] /*+ 0.5 * node_size_y[other_node_id]*/;
      flag &= (other_node_id != skip_node_id);
      int cond1 = (other_node_id == node_id);
      int cond2 = (other_node_id == target_node_id);
      xxl =
          cond1 * node_xl + cond2 * target_node_xl + (!(cond1 || cond2)) * xxl;
      yyl =
          cond1 * node_yl + cond2 * target_node_yl + (!(cond1 || cond2)) * yyl;
      // xxl+px
      xxl += pin_offset_x[net_pin_id];
      // yyl+py
      yyl += pin_offset_y[net_pin_id];
      box.xl = min(box.xl, xxl);
      box.xh = max(box.xh, xxl);
      box.yl = min(box.yl, yyl);
      box.yh = max(box.yh, yyl);
    }
    cost += (box.xh - box.xl + box.yh - box.yl) * flag;
    
  }
  return cost;
}

inline __device__ float compute_pair_hpwl_general_fast(PitchNestedVector<int>& node2net_map,
                                                       PitchNestedVector<NodePinPair<float>>& net2nodepin_map,
                                                       const float xh,
                                                       const float yh,
                                                       const float xl,
                                                       const float yl,
                                                       const int* __restrict__ net_mask,
                                                       const float* __restrict__ x,
                                                       const float* __restrict__ y,
                                                       int node_id,
                                                       float node_xl,
                                                       float node_yl,
                                                       int target_node_id,
                                                       float target_node_xl,
                                                       float target_node_yl,
                                                       int skip_node_id) {
  float cost = 0;
  auto node2nets = node2net_map(node_id);
  for (int i = 0; i < node2net_map.size(node_id); ++i) {
    int net_id = node2nets[i];
    int flag = net_mask[net_id];
    auto net2nodepins = net2nodepin_map(net_id);
    Box<float> box(xh, yh, xl, yl);

    int end = net2nodepin_map.size(net_id) * flag;
    for (int j = 0; j < end; ++j) {
      NodePinPair<float>& node_pin_pair = net2nodepins[j];
      int other_node_id = node_pin_pair.node_id;

      flag &= (other_node_id != skip_node_id);

      float xxl = x[other_node_id] /*+ 0.5 * node_size_x[other_node_id]*/;
      float yyl = y[other_node_id] /*+ 0.5 * node_size_y[other_node_id]*/;
      int cond1 = (other_node_id == node_id);
      int cond2 = (other_node_id == target_node_id);
      xxl = cond1 * node_xl + cond2 * target_node_xl + (!(cond1 || cond2)) * xxl;
      yyl = cond1 * node_yl + cond2 * target_node_yl + (!(cond1 || cond2)) * yyl;

      xxl += node_pin_pair.pin_offset_x;
      yyl += node_pin_pair.pin_offset_y;
      box.xl = min(box.xl, xxl);
      box.xh = max(box.xh, xxl);
      box.yl = min(box.yl, yyl);
      box.yh = max(box.yh, yyl);
    }
    cost += (box.xh - box.xl + box.yh - box.yl) * flag;
  }
  return cost;
}

__device__ float compute_pair_hpwl(const DetailedPlaceData& db,
                                   const SwapState<float>& state,
                                   int node_id,
                                   float node_xl,
                                   float node_yl,
                                   int target_node_id,
                                   float target_node_xl,
                                   float target_node_yl) {
  float cost = 0;
  for (int node2pin_id = db.flat_node2pin_start_map[node_id];
       node2pin_id < db.flat_node2pin_start_map[node_id + 1];
       ++node2pin_id) {
    int node_pin_id = db.flat_node2pin_map[node2pin_id];
    int net_id = db.pin2net_map[node_pin_id];
    Box<float> box(db.xh, db.yh, db.xl, db.yl);
    if (db.net_mask[net_id]) {
      for (int net2pin_id = db.flat_net2pin_start_map[net_id];
           net2pin_id < db.flat_net2pin_start_map[net_id + 1];
           ++net2pin_id) {
        int net_pin_id = db.flat_net2pin_map[net2pin_id];
        int other_node_id = db.pin2node_map[net_pin_id];
        int cond1 = (other_node_id == node_id);
        int cond2 = (other_node_id == target_node_id);
        float xxl = cond1 * node_xl + cond2 * target_node_xl +
                    (!(cond1 || cond2)) * (/*0.5 * db.node_size_x[other_node_id]*/ + db.x[other_node_id]);
        float yyl = cond1 * node_yl + cond2 * target_node_yl +
                    (!(cond1 || cond2)) * (/*0.5 * db.node_size_y[other_node_id]*/ + db.y[other_node_id]);
        float px = db.pin_offset_x[net_pin_id];
        float py = db.pin_offset_y[net_pin_id];
        box.xl = min(box.xl, xxl + px);
        box.xh = max(box.xh, xxl + px);
        box.yl = min(box.yl, yyl + py);
        box.yh = max(box.yh, yyl + py);
      }
      cost += box.xh - box.xl + box.yh - box.yl;
    }
  }

  for (int node2pin_id = db.flat_node2pin_start_map[target_node_id];
       node2pin_id < db.flat_node2pin_start_map[target_node_id + 1];
       ++node2pin_id) {
    int node_pin_id = db.flat_node2pin_map[node2pin_id];
    int net_id = db.pin2net_map[node_pin_id];
    Box<float> box(db.xh, db.yh, db.xl, db.yl);
    if (db.net_mask[net_id]) {
      for (int net2pin_id = db.flat_net2pin_start_map[net_id];
           net2pin_id < db.flat_net2pin_start_map[net_id + 1];
           ++net2pin_id) {
        int net_pin_id = db.flat_net2pin_map[net2pin_id];
        int other_node_id = db.pin2node_map[net_pin_id];
        int cond1 = (other_node_id == node_id);
        if (cond1) {
          box.xl = box.yl = box.xh = box.yh = 0;
          break;
        }
        int cond2 = (other_node_id == target_node_id);
        float xxl = cond1 * node_xl + cond2 * target_node_xl +
                    (!(cond1 || cond2)) * (/*0.5 * db.node_size_x[other_node_id]*/ + db.x[other_node_id]);
        float yyl = cond1 * node_yl + cond2 * target_node_yl +
                    (!(cond1 || cond2)) * (/*0.5 * db.node_size_y[other_node_id]*/ + db.y[other_node_id]);
        float px = db.pin_offset_x[net_pin_id];
        float py = db.pin_offset_y[net_pin_id];
        box.xl = min(box.xl, xxl + px);
        box.xh = max(box.xh, xxl + px);
        box.yl = min(box.yl, yyl + py);
        box.yh = max(box.yh, yyl + py);
      }
      cost += box.xh - box.xl + box.yh - box.yl;
    }
  }

  return cost;
}

__device__ float compute_positions_hint(const DetailedPlaceData& db,
                                        const SwapState<float>& state,
                                        SwapCandidate<float>& cand,
                                        float node_xl,
                                        float node_yl,
                                        float node_width,
                                        const Space<float>& space) {
  // case I: two cells are horizontally abutting
  cand.node_xl[0][0] = node_xl;
  cand.node_yl[0][0] = node_yl;
  cand.node_xl[1][0] = db.x[cand.node_id[1]];
  cand.node_yl[1][0] = db.y[cand.node_id[1]];
  float target_node_width = db.node_size_x[cand.node_id[1]];
  auto target_space = db.align2site(state.spaces[cand.node_id[1]]);
  int cond = (space.xh >= target_space.xl);
  cond &= (target_space.xh >= space.xl);
  cond &= (cand.node_yl[0][0] == cand.node_yl[1][0]);
  if (cond) {
    // case I: abutting, not exactly abutting, there might be space
    // between two cells, this is a generalized case
    cond = (space.xl < target_space.xl);
    cand.node_xl[0][1] = cand.node_xl[1][0] + (target_node_width - node_width) * cond;
    cand.node_xl[1][1] = cand.node_xl[0][0] - (target_node_width - node_width) * (!cond);
  } else {
    // case II: not abutting
    cond = (space.xh < target_node_width + space.xl);
    cond |= (target_space.xh < node_width + target_space.xl);
    if (cond) {
      // some large number
      return cuda::numeric_limits<float>::max();
    }
    cand.node_xl[0][1] = cand.node_xl[1][0] + (target_node_width - node_width) / 2;
    cand.node_xl[1][1] = cand.node_xl[0][0] + (node_width - target_node_width) / 2;
    cand.node_xl[0][1] = db.align2site(cand.node_xl[0][1]);
    cand.node_xl[0][1] = max(cand.node_xl[0][1], target_space.xl);
    cand.node_xl[0][1] = min(cand.node_xl[0][1], target_space.xh - node_width);
    cand.node_xl[1][1] = db.align2site(cand.node_xl[1][1]);
    cand.node_xl[1][1] = max(cand.node_xl[1][1], space.xl);
    cand.node_xl[1][1] = min(cand.node_xl[1][1], space.xh - target_node_width);
  }
  cand.node_yl[0][1] = cand.node_yl[1][0];
  cand.node_yl[1][1] = cand.node_yl[0][0];

  return 0;
}

__global__ void compute_search_bins(DetailedPlaceData db, SwapState<float> state, int begin, int end) {
  for (int node_id = begin + blockIdx.x * blockDim.x + threadIdx.x; node_id < end;
       node_id += blockDim.x * gridDim.x) {
    // compute optimal region
    Box<float> opt_box = (state.search_bin_strategy)
      ? db.compute_optimal_region(node_id, db.x, db.y, db.node_size_x, db.node_size_y)
      : Box<float>(db.x[node_id],
                   db.y[node_id],
                   db.x[node_id] + db.node_size_x[node_id],
                   db.y[node_id] + db.node_size_y[node_id]);
    int cx = db.pos2bin_x(opt_box.center_x());
    int cy = db.pos2bin_y(opt_box.center_y());
    state.search_bins[node_id] = cx * db.num_bins_y + cy;
  }
}

__global__ void reset_state(DetailedPlaceData db, SwapState<float> state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    SwapCandidate<float>& cand = state.candidates[i];
    cand.cost = 0;
    cand.node_id[0] = cuda::numeric_limits<int>::max();
    cand.node_id[1] = cuda::numeric_limits<int>::max();
    cand.node_xl[0][0] = 0;
    cand.node_xl[0][1] = 0;
    cand.node_yl[0][0] = 0;
    cand.node_yl[0][1] = 0;
    cand.node_xl[1][0] = 0;
    cand.node_xl[1][1] = 0;
    cand.node_yl[1][0] = 0;
    cand.node_yl[1][1] = 0;
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_movable_nodes; i += blockDim.x * gridDim.x) {
    state.node_markers[i] = 0;
  }
}

__global__ void check_state(DetailedPlaceData db, SwapState<float> state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_movable_nodes;
       i += blockDim.x * gridDim.x) {
    const BinMapIndex& bm_idx = state.node2bin_map[i];
    if (state.bin2node_map(bm_idx.bin_id, bm_idx.sub_id) != i) {
      printf("[E] node %d @ (%g, %g), bin [%d, %d], found %d\n", i,
             (float)db.x[i], (float)db.y[i], bm_idx.bin_id, bm_idx.sub_id,
             state.bin2node_map(bm_idx.bin_id, bm_idx.sub_id));
      assert(0);
    }
  }
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    SwapCandidate<float>& cand = state.candidates[i];
    if (cand.cost < 0 && (cand.node_id[0] >= db.num_movable_nodes ||
                          cand.node_id[1] >= db.num_movable_nodes)) {
      printf("[E] node %d, target_node %d, cost %g\n", cand.node_id[0],
             cand.node_id[1], (float)cand.cost);
      assert(0);
    }
    if (cand.cost < 0) {
      if (db.x[cand.node_id[0]] != cand.node_xl[0][0]) {
        printf("[E] node %d x %g node_xl %g\n", cand.node_id[0],
               (float)db.x[cand.node_id[0]], (float)cand.node_xl[0][0]);
      }
      if (db.y[cand.node_id[0]] != cand.node_yl[0][0]) {
        printf("[E] node %d y %g node_yl %g\n", cand.node_id[0],
               (float)db.y[cand.node_id[0]], (float)cand.node_yl[0][0]);
      }
      if (db.x[cand.node_id[1]] != cand.node_xl[1][0]) {
        printf("[E] node %d x %g target_node_xl %g\n", cand.node_id[1],
               (float)db.x[cand.node_id[1]], (float)cand.node_xl[1][0]);
      }
      if (db.y[cand.node_id[1]] != cand.node_yl[1][0]) {
        printf("[E] node %d y %g target_node_yl %g\n", cand.node_id[1],
               (float)db.y[cand.node_id[1]], (float)cand.node_yl[1][0]);
      }
      assert(db.x[cand.node_id[0]] == cand.node_xl[0][0]);
      assert(db.y[cand.node_id[0]] == cand.node_yl[0][0]);
      assert(db.x[cand.node_id[1]] == cand.node_xl[1][0]);
      assert(db.y[cand.node_id[1]] == cand.node_yl[1][0]);
    }
  }
}

__global__ void __launch_bounds__(256, 4)
    collect_candidates(DetailedPlaceData db, SwapState<float> state, int idx_bgn,
                       int idx_end) {
  // assume following inequality
  assert(gridDim.y == (idx_end-idx_bgn));
  assert(gridDim.x == 5);
  __shared__ int node_id;
  __shared__ float node_xl, node_yl, node_width;
  __shared__ Space<float> space;
  __shared__ int max_num_candidates;
  __shared__ int bin_id;
  __shared__ const int* __restrict__ bin2nodes;
  __shared__ int num_nodes_in_bin;
  __shared__ float step_size;
  __shared__ int iters;
  __shared__ int block_offset;
  if (threadIdx.x == 0) {
    node_id = state.ordered_nodes[blockIdx.y + idx_bgn];
    node_xl = db.x[node_id];
    node_yl = db.y[node_id];
    node_width = db.node_size_x[node_id];
    space = db.align2site(state.spaces[node_id]);
    max_num_candidates = state.max_num_candidates / 5;

    block_offset =
        blockIdx.y * state.max_num_candidates + blockIdx.x * max_num_candidates;
    bin_id = state.search_bins[node_id];
    int bx = bin_id / db.num_bins_y;
    int by = bin_id - bx * db.num_bins_y;
    if (blockIdx.x == 1)  // left bin
    {
      if (bx > 0) {
        bin_id -= db.num_bins_y;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 2)  // bottom bin
    {
      if (by > 0) {
        bin_id -= 1;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 3)  // right bin
    {
      if (bx + 1 < db.num_bins_x) {
        bin_id += db.num_bins_y;
      } else {
        bin_id = -1;
      }
    } else if (blockIdx.x == 4)  // top bin
    {
      if (by + 1 < db.num_bins_y) {
        bin_id += 1;
      } else {
        bin_id = -1;
      }
    }
    // else is center bin

    if (bin_id >= 0) {
      bin2nodes = state.bin2node_map(bin_id);
      num_nodes_in_bin =
          state.bin2node_map.size(bin_id) *
          (db.node_size_y[node_id] ==
           db.row_height);  // only consider single-row height cell
      step_size = max((float)num_nodes_in_bin / (float)max_num_candidates, (float)1);
      iters = min(max_num_candidates, num_nodes_in_bin);
    }
  }
  __syncthreads();
  SwapCandidate<float> cand;
  cand.node_id[0] = node_id;
  if (bin_id >= 0) {
    for (int i = threadIdx.x; i < iters; i += blockDim.x) {
      cand.node_id[1] = bin2nodes[int(i * step_size)];
      int cond = (cand.node_id[0] != cand.node_id[1]);
      cond &= (db.node_size_y[cand.node_id[1]] == db.row_height);
      if (cond) {
        // target_cost - orig_cost
        // cand.cost = compute_positions(db, state, cand);
        cand.cost = compute_positions_hint(db, state, cand, node_xl, node_yl,
                                           node_width, space);
        cond = (cand.cost == 0);
        if (cond) {
          state.candidates[block_offset + i] = cand;
        }
      }
    }
  }
}

__global__ void reset_candidate_costs(DetailedPlaceData db,
                                      SwapState<float> state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    state.candidates[i].cost = cuda::numeric_limits<float>::max();
  }
}

__global__ void check_candidate_costs(DetailedPlaceData db,
                                      SwapState<float> state) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x;
       i < state.max_num_candidates_all; i += blockDim.x * gridDim.x) {
    auto const& cand = state.candidates[i];
    if (cand.cost < 0) {
      assert(cand.node_id[0] < db.num_movable_nodes &&
             cand.node_id[1] < db.num_movable_nodes);
    }
  }
}

__global__ void __launch_bounds__(256, 4)
    compute_candidate_cost(DetailedPlaceData db, SwapState<float> state) {
  extern __shared__ unsigned char cost_proxy[];
  __shared__ int num_candidates;
  float* cost = reinterpret_cast<float*>(cost_proxy);
  if (threadIdx.x == 0) {
    num_candidates = (state.max_num_candidates_all << 2);
  }
  __syncthreads();
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < num_candidates;
       i += blockDim.x * gridDim.x) {
    SwapCandidate<float>& cand = state.candidates[i >> 2];
    int node_id_flag = ((threadIdx.x & 2) >> 1);
    int offset = (threadIdx.x & 1);
    int skip_node_id = cand.node_id[0] + INT_MIN * (!node_id_flag);
    if (cand.node_id[0] < db.num_movable_nodes &&
        cand.node_id[1] < db.num_movable_nodes) {
      int cost1 =
          (state.pair_hpwl_computing_strategy)
              ? compute_pair_hpwl_general_fast(
                    state.node2net_map, state.net2nodepin_map, db.xh, db.yh,
                    db.xl, db.yl, db.net_mask, db.x, db.y,
                    cand.node_id[node_id_flag],
                    cand.node_xl[node_id_flag][offset],
                    cand.node_yl[node_id_flag][offset],
                    cand.node_id[!node_id_flag],
                    cand.node_xl[!node_id_flag][offset],
                    cand.node_yl[!node_id_flag][offset], skip_node_id)
              : compute_pair_hpwl_general(
                    db.flat_node2pin_start_map, db.flat_node2pin_map,
                    db.pin2net_map, db.xh, db.yh, db.xl, db.yl, db.net_mask,
                    db.flat_net2pin_start_map, db.flat_net2pin_map,
                    db.pin2node_map, db.x, db.y, db.pin_offset_x,
                    db.pin_offset_y, cand.node_id[node_id_flag],
                    cand.node_xl[node_id_flag][offset],
                    cand.node_yl[node_id_flag][offset],
                    cand.node_id[!node_id_flag],
                    cand.node_xl[!node_id_flag][offset],
                    cand.node_yl[!node_id_flag][offset], skip_node_id);
      cost[threadIdx.x] = cost1;
    } else {
      cost[threadIdx.x] = 0;
    }
  }
  __syncthreads();
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < num_candidates;
       i += blockDim.x * gridDim.x) {
    SwapCandidate<float>& cand = state.candidates[i >> 2];
    if ((threadIdx.x & 3) == 3)
    {
      // consider FENCE region
      if (db.num_regions &&
          ((cand.node_id[0] < db.num_movable_nodes &&
            !db.inside_fence(cand.node_id[0], cand.node_xl[0][1],
                             cand.node_yl[0][1])) ||
           (cand.node_id[1] < db.num_movable_nodes &&
            !db.inside_fence(cand.node_id[1], cand.node_xl[1][1],
                             cand.node_yl[1][1])))) {
        cand.cost = cuda::numeric_limits<float>::max(); // cost is infinite if not in fence
      } else {
        cand.cost = cost[threadIdx.x] - cost[threadIdx.x - 1] +
                    cost[threadIdx.x - 2] - cost[threadIdx.x - 3];  // else cost is difference of prev and next
      }
    }
  }
}

/// only allow 1 block
__global__ void apply_candidates(DetailedPlaceData db, SwapState<float> state, int num_candidates) {
  for (int i = 0; i < num_candidates; ++i) {
    const SwapCandidate<float>& best_cand = state.candidates[i * state.max_num_candidates];

    if (best_cand.cost < 0 &&
        !(state.node_markers[best_cand.node_id[0]] || state.node_markers[best_cand.node_id[1]])) {
      float node_width = db.node_size_x[best_cand.node_id[0]];
      float target_node_width = db.node_size_x[best_cand.node_id[1]];
      Space<float>& space = state.spaces[best_cand.node_id[0]];
      Space<float>& target_space = state.spaces[best_cand.node_id[1]];

      if (best_cand.node_xl[0][1] >= target_space.xl && best_cand.node_xl[0][1] + node_width <= target_space.xh &&
          best_cand.node_xl[1][1] >= space.xl && best_cand.node_xl[1][1] + target_node_width <= space.xh) {
        state.node_markers[best_cand.node_id[0]] = 1;
        state.node_markers[best_cand.node_id[1]] = 1;

        BinMapIndex& bin_id = state.node2bin_map[best_cand.node_id[0]];
        BinMapIndex& target_bin_id = state.node2bin_map[best_cand.node_id[1]];
        RowMapIndex& row_id = state.node2row_map[best_cand.node_id[0]];
        RowMapIndex& target_row_id = state.node2row_map[best_cand.node_id[1]];
        int* row2nodes = state.row2node_map(row_id.row_id);
        int* target_row2nodes = state.row2node_map(target_row_id.row_id);

        db.x[best_cand.node_id[0]] = best_cand.node_xl[0][1];
        db.y[best_cand.node_id[0]] = best_cand.node_yl[0][1];
        db.x[best_cand.node_id[1]] = best_cand.node_xl[1][1];
        db.y[best_cand.node_id[1]] = best_cand.node_yl[1][1];
        int& bin2node_map_node_id = state.bin2node_map(bin_id.bin_id, bin_id.sub_id);
        int& bin2node_map_target_node_id = state.bin2node_map(target_bin_id.bin_id, target_bin_id.sub_id);
        device_swap(bin2node_map_node_id, bin2node_map_target_node_id);
        device_swap(bin_id, target_bin_id);

        {
          int neighbor_node_id = row2nodes[row_id.sub_id - 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space<float>& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xh = min(neighbor_space.xh, best_cand.node_xl[1][1]);
          }
          neighbor_node_id = row2nodes[row_id.sub_id + 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space<float>& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xl = max(neighbor_space.xl, best_cand.node_xl[1][1] + target_node_width);
          }
          neighbor_node_id = target_row2nodes[target_row_id.sub_id - 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space<float>& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xh = min(neighbor_space.xh, best_cand.node_xl[0][1]);
          }
          neighbor_node_id = target_row2nodes[target_row_id.sub_id + 1];
          if (neighbor_node_id < db.num_movable_nodes) {
            Space<float>& neighbor_space = state.spaces[neighbor_node_id];
            neighbor_space.xl = max(neighbor_space.xl, best_cand.node_xl[0][1] + node_width);
          }
        }

        if ((best_cand.node_yl[0][0] == best_cand.node_yl[1][0]) && (space.xh >= target_space.xl) &&
            (target_space.xh >= space.xl)) {
          if (best_cand.node_xl[0][0] < best_cand.node_xl[1][0]) {
            space.xh = target_space.xh;
            target_space.xl = space.xl;
            space.xl = best_cand.node_xl[1][1] + target_node_width;
            target_space.xh = best_cand.node_xl[0][1];
          } else {
            target_space.xh = space.xh;
            space.xl = target_space.xl;
            target_space.xl = best_cand.node_xl[0][1] + node_width;
            space.xh = best_cand.node_xl[0][1];
          }
        } else {
          device_swap(space, target_space);
        }

        device_swap(row2nodes[row_id.sub_id], target_row2nodes[target_row_id.sub_id]);
        device_swap(row_id, target_row_id);
      }
    }
  }
}


/// generate array from 0 to n-1
__global__ void iota(int* ptr, int n) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; i += blockDim.x * gridDim.x) {
    ptr[i] = i;
  }
}

void global_swap(DetailedPlaceData& db, SwapState<float>& state) {
  compute_search_bins<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state, 0, db.num_movable_nodes);
  checkCuda(cudaDeviceSynchronize());

  for (int i = 0; i < db.num_movable_nodes; i += state.batch_size) {
    // all results are stored in state.candidates
    int idx_bgn = i;
    int idx_end = min(i + state.batch_size, db.num_movable_nodes);
    reset_state<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state);
    dim3 grid(5, (idx_end - idx_bgn), 1);
    collect_candidates<<<grid, 256>>>(db, state, idx_bgn, idx_end);
    reset_candidate_costs<<<ceilDiv(state.max_num_candidates_all, 256), 256>>>(db, state);
    compute_candidate_cost<<<ceilDiv(state.max_num_candidates_all, 64), 64 * 4, 64 * 4 * sizeof(float)>>>(db, state);

    //check_state<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(db, state);
    //check_candidate_costs<<<ceilDiv(state.max_num_candidates_all, 256), 256>>>(
    //    db, state);

    // reduce min and apply
    reduce_min_2d_cub<float, 256><<<idx_end - idx_bgn, 256>>>(state.candidates, state.max_num_candidates);
    // must use single thread
    apply_candidates<<<1, 1>>>(db, state, idx_end - idx_bgn);
  }
}

__global__ void initNode2NetMap_kernel(PitchNestedVector<int> node2net_map, DetailedPlaceData db, const int num_nodes) {
  const int node_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (node_id >= num_nodes) {
    return;
  }
  int num_elements = 0;
  int beg = db.flat_node2pin_start_map[node_id];
  int end = min((int)db.flat_node2pin_start_map[node_id + 1], beg + MAX_NODE_DEGREE);
  for (int node2pin_id = beg; node2pin_id < end; ++node2pin_id, ++num_elements) {
    if (num_elements < MAX_NODE_DEGREE)  // only consider MAX_NODE_DEGREE pins
    {
      int node_pin_id = db.flat_node2pin_map[node2pin_id];
      int net_id = db.pin2net_map[node_pin_id];
      node2net_map.flat_element_map[node_id * MAX_NODE_DEGREE + num_elements] = net_id;
    }
  }
  node2net_map.dim2_sizes[node_id] = num_elements;
}

void initNode2NetMap(PitchNestedVector<int>& node2net_map, DetailedPlaceData& db) {
  // allocate memory
  allocateCuda(node2net_map.flat_element_map, db.num_movable_nodes * MAX_NODE_DEGREE, int);
  allocateCuda(node2net_map.dim2_sizes, db.num_movable_nodes, unsigned int);
  node2net_map.size1 = db.num_movable_nodes;
  node2net_map.size2 = MAX_NODE_DEGREE;
  // init on GPU
  initNode2NetMap_kernel<<<ceilDiv(db.num_movable_nodes, 512), 512>>>(node2net_map, db, db.num_movable_nodes);
  checkCuda(cudaDeviceSynchronize());
}

__global__ void initNet2NodePinMap_kernel(PitchNestedVector<NodePinPair<float>> net2nodepin_map,
                                          DetailedPlaceData db,
                                          const int num_nets) {
  const int net_id = blockIdx.x * blockDim.x + threadIdx.x;
  if (net_id >= num_nets) {
    return;
  }
  int num_elements = 0;
  int beg = db.flat_net2pin_start_map[net_id];
  int end = min((int)db.flat_net2pin_start_map[net_id + 1], beg + MAX_NET_DEGREE);
  for (int net2pin_id = beg; net2pin_id < end; ++net2pin_id, ++num_elements) {
    if (num_elements < MAX_NET_DEGREE)  // only consider MAX_NET_DEGREE pins
    {
      int net_pin_id = db.flat_net2pin_map[net2pin_id];
      float px = db.pin_offset_x[net_pin_id];
      float py = db.pin_offset_y[net_pin_id];
      int node_id = db.pin2node_map[net_pin_id];
      NodePinPair<float>& node_pin_pair =
          net2nodepin_map.flat_element_map[net_id * MAX_NET_DEGREE + num_elements];
      node_pin_pair.node_id = node_id;
      node_pin_pair.pin_offset_x = px;
      node_pin_pair.pin_offset_y = py;
    }
  }
  net2nodepin_map.dim2_sizes[net_id] = num_elements;
}

void initNet2NodePinMap(PitchNestedVector<NodePinPair<float>>& net2nodepin_map, DetailedPlaceData& db) {
  // allocate memory
  allocateCuda(net2nodepin_map.flat_element_map, db.num_nets * MAX_NET_DEGREE, NodePinPair<float>);
  allocateCuda(net2nodepin_map.dim2_sizes, db.num_nets, unsigned int);
  net2nodepin_map.size1 = db.num_nets;
  net2nodepin_map.size2 = MAX_NET_DEGREE;
  // init on GPU
  initNet2NodePinMap_kernel<<<ceilDiv(db.num_nets, 512), 512>>>(net2nodepin_map, db, db.num_nets);
  checkCuda(cudaDeviceSynchronize());
}

__global__ void compute_num_nodes_in_bins(DetailedPlaceData db, int* node_count_map) {
  for (int node_id = blockIdx.x * blockDim.x + threadIdx.x; node_id < db.num_movable_nodes;
       node_id += blockDim.x * gridDim.x) {
    int bx = db.pos2bin_x(db.x[node_id]);
    int by = db.pos2bin_y(db.y[node_id]);
    int bin_id = bx * db.num_bins_y + by;
    atomicAdd(node_count_map + bin_id, 1);
  }
}

int compute_max_num_nodes_per_bin(const DetailedPlaceData& db) {
  int num_bins = db.num_bins_x * db.num_bins_y;
  int* node_count_map = nullptr;
  allocateCuda(node_count_map, num_bins, int);

  checkCuda(cudaMemset(node_count_map, 0, sizeof(int) * num_bins));
  compute_num_nodes_in_bins<<<ceilDiv(db.num_movable_nodes, 256), 256>>>(db, node_count_map);

  int* d_out = NULL;
  // Determine temporary device storage requirements
  void* d_temp_storage = NULL;
  size_t temp_storage_bytes = 0;
  cub::DeviceReduce::Max(d_temp_storage, temp_storage_bytes, node_count_map, d_out, num_bins);
  // Allocate temporary storage
  checkCuda(cudaMalloc(&d_temp_storage, temp_storage_bytes));
  checkCuda(cudaMalloc(&d_out, sizeof(int)));
  // Run max-reduction
  cub::DeviceReduce::Max(d_temp_storage, temp_storage_bytes, node_count_map, d_out, num_bins);
  // copy d_out to hpwl
  int max_num_nodes_per_bin = 0;
  checkCuda(cudaMemcpy(&max_num_nodes_per_bin, d_out, sizeof(int), cudaMemcpyDeviceToHost));
  cudaFree(d_temp_storage);
  cudaFree(d_out);
  cudaFree(node_count_map);

  return max_num_nodes_per_bin;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::run(DetailedMgr* mgrPtr,
                              DetailedPlaceData& db, 
                              std::vector<std::string>& args)
{
  // Given the arguments, figure out which routine to run to do the reordering.
  mgr_ = mgrPtr;
  arch_ = mgr_->getArchitecture();
  network_ = mgr_->getNetwork();
  rt_ = mgr_->getRoutingParams();

  // these should be passed in as options at some point
  int num_bins_x = 256;  
  int num_bins_y = 256; 
  int batch_size = 8;   

  db.set_num_bins(num_bins_x, num_bins_y);
  printf("[INFO GPU-DPO] bins %dx%d, bin sizes %gx%g, die size %g, %g, %g, %g\n",
         db.num_bins_x,
         db.num_bins_y,
         (float)db.bin_size_x,
         (float)db.bin_size_y,
         (float)db.xl,
         (float)db.yl,
         (float)db.xh,
         (float)db.yh);

  SwapState<float> state;

  state.batch_size = batch_size;
  int max_num_nodes_per_bin = compute_max_num_nodes_per_bin(db);
  state.max_num_candidates = max_num_nodes_per_bin * 5;
  state.max_num_candidates_all = state.batch_size * state.max_num_candidates;
  printf("[INFO GPU-DPO] batch_size = %d, max_num_nodes_per_bin = %d, "
         "max_num_candidates = %d, max_num_candidates_all = %d\n",
         state.batch_size,
         max_num_nodes_per_bin,
         state.max_num_candidates,
         state.max_num_candidates_all);
  state.search_bin_strategy = 1;
  // use fast mode for small designs, because extra memory is required
  long estimate_memory_usage = db.num_nodes * MAX_NODE_DEGREE * sizeof(int)                 // size of node2net_map
                                + db.num_nets * MAX_NET_DEGREE * sizeof(NodePinPair<float>)  // size of net2nodepin_map
      ;
  if (estimate_memory_usage < 4e9) {  // use 4GB as a switch threshold
    printf("[INFO GPU-DPO] estimate_memory_usage = %ld, use fast pair HPWL "
           "computation strategy requires additional memory\n",
           estimate_memory_usage);
    state.pair_hpwl_computing_strategy = 1;
  } else {
    printf("[INFO GPU-DPO] estimate_memory_usage = %ld, use general pair HPWL\n", estimate_memory_usage);
    state.pair_hpwl_computing_strategy = 0;
  }

  // fix random seed
  std::srand(1000);

  // allocate temporary memory to CPU, add dummy cells for xl and xh
  std::vector<float> host_x(db.num_nodes + 2);
  std::vector<float> host_y(db.num_nodes + 2);
  std::vector<float> host_node_size_x(db.num_nodes + 2);
  std::vector<float> host_node_size_y(db.num_nodes + 2);
  host_x[db.num_nodes] = db.xl - 1;
  host_y[db.num_nodes] = db.yl;
  host_node_size_x[db.num_nodes] = 1;
  host_node_size_y[db.num_nodes] = db.yh - db.yl;
  host_x[db.num_nodes + 1] = db.xh;
  host_y[db.num_nodes + 1] = db.yl;
  host_node_size_x[db.num_nodes + 1] = 1;
  host_node_size_y[db.num_nodes + 1] = db.yh - db.yl;
  checkCuda(cudaMemcpy(host_x.data(), db.x, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(cudaMemcpy(host_y.data(), db.y, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(
      cudaMemcpy(host_node_size_x.data(), db.node_size_x, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));
  checkCuda(
      cudaMemcpy(host_node_size_y.data(), db.node_size_y, sizeof(float) * db.num_nodes, cudaMemcpyDeviceToHost));

  // distribute cells to rows on host, copy cell locations from device to host
  std::vector<std::vector<int>> host_row2node_map(db.num_sites_y);
  std::vector<RowMapIndex> host_node2row_map(db.num_movable_nodes);
  std::vector<Space<float>> host_spaces(db.num_movable_nodes);
  db.make_row2node_map_with_spaces(host_x.data(),
                                    host_y.data(),
                                    host_node_size_x.data(),
                                    host_node_size_y.data(),
                                    host_row2node_map,
                                    host_node2row_map,
                                    host_spaces,
                                    1);
  // distribute movable cells to bins on host, bin map is column-major
  std::vector<std::vector<int>> host_bin2node_map(db.num_bins_x * db.num_bins_y);
  std::vector<BinMapIndex> host_node2bin_map(db.num_movable_nodes);
  db.make_bin2node_map(host_x.data(),
                        host_y.data(),
                        host_node_size_x.data(),
                        host_node_size_y.data(),
                        host_bin2node_map,
                        host_node2bin_map);

  // initialize SwapState
  std::vector<int> host_ordered_nodes;
  host_ordered_nodes.reserve(db.num_movable_nodes);
  // reorder such that a batch of cells are distributed to different bins
  int sub_id_counter = 0;
  while ((int)host_ordered_nodes.size() < db.num_movable_nodes) {
    for (int i = 0; i < state.batch_size; ++i) {
      for (unsigned int j = i; j < host_bin2node_map.size(); j += state.batch_size) {
        auto const& bin2nodes = host_bin2node_map[j];
        if (sub_id_counter < bin2nodes.size()) {
          host_ordered_nodes.push_back(bin2nodes[sub_id_counter]);
        }
      }
    }
    ++sub_id_counter;
  }

  allocateCopyCuda(state.ordered_nodes, host_ordered_nodes.data(), db.num_movable_nodes);
  state.row2node_map.initialize(host_row2node_map);
  allocateCopyCuda(state.node2row_map, host_node2row_map.data(), host_node2row_map.size());
  allocateCopyCuda(state.spaces, host_spaces.data(), host_spaces.size());
  state.bin2node_map.initialize(host_bin2node_map);
  allocateCopyCuda(state.node2bin_map, host_node2bin_map.data(), host_node2bin_map.size());

  allocateCuda(state.candidates, state.max_num_candidates_all, SwapCandidate<float>);
  allocateCuda(state.search_bins, db.num_movable_nodes, int);
  allocateCuda(state.net_hpwls, db.num_nets, typename std::remove_pointer<decltype(state.net_hpwls)>::type);
  allocateCuda(state.node_markers, db.num_movable_nodes, unsigned char);
  checkCuda(cudaMemset(state.node_markers, 0, sizeof(unsigned char) * db.num_movable_nodes));

  if (state.pair_hpwl_computing_strategy) {
    initNode2NetMap(state.node2net_map, db);
    initNet2NodePinMap(state.net2nodepin_map, db);
  }

  int passes = 10;
  double tol = 0.1 / 100;  // 0.1/100 maybe
  for (size_t i = 1; i < args.size(); i++) {
    if (args[i] == "-p" && i + 1 < args.size()) {
      passes = std::atoi(args[++i].c_str());
    } else if (args[i] == "-t" && i + 1 < args.size()) {
      tol = std::atof(args[++i].c_str());
    }
  }

  passes = std::max(passes, 1);   // number of iterations
  tol = std::max(tol, 0.01);      // tolerance (i.e. hpwl stops improving after a certain amount)

  float hpwls[passes + 1];
  hpwls[0] = compute_total_hpwl(db, db.x, db.y, state.net_hpwls);
  printf("[INFO GPU-DPO] initial hpwl = %.3f\n", hpwls[0]);

  for (int p = 1; p <= passes; p++) {
    global_swap(db, state);
    checkCuda(cudaDeviceSynchronize());

    hpwls[p] = compute_total_hpwl(db, db.x, db.y, state.net_hpwls);
    printf("[INFO GPU-DPO] Pass %3d of global swaps; hpwl %.3f => %.3f (imp. %g%%)\n", 
           p, 
           hpwls[0],
           hpwls[p],
           (1.0 - hpwls[p] / (double)hpwls[0]) * 100);
    state.search_bin_strategy = !state.search_bin_strategy;
    
    if ((p & 1) && hpwls[p] - hpwls[p - 1] > -tol * hpwls[0]) {
      break;
    }
  }
  checkCuda(cudaDeviceSynchronize());

  // destroy SwapState
  cudaFree(state.ordered_nodes);
  state.row2node_map.destroy();
  cudaFree(state.node2row_map);
  cudaFree(state.spaces);
  state.bin2node_map.destroy();
  cudaFree(state.node2bin_map);
  cudaFree(state.candidates);
  cudaFree(state.search_bins);
  cudaFree(state.net_hpwls);
  cudaFree(state.node_markers);

  if (state.pair_hpwl_computing_strategy) {
    state.node2net_map.destroy();
    state.net2nodepin_map.destroy();
  }

  checkCuda(cudaDeviceSynchronize());
}

//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::globalSwap()
{
  // Nothing for than random greedy improvement with only a hpwl objective
  // and done such that every candidate cell is considered once!!!

  traversal_ = 0;
  edgeMask_.resize(network_->getNumEdges());
  std::fill(edgeMask_.begin(), edgeMask_.end(), 0);

  mgr_->resortSegments();

  // Get candidate cells.
  std::vector<Node*> candidates = mgr_->getSingleHeightCells();
  mgr_->shuffle(candidates);

  // Wirelength objective.
  DetailedHPWL hpwlObj(network_);
  hpwlObj.init(mgr_, nullptr);  // Ignore orientation.

  double currHpwl = hpwlObj.curr();
  double nextHpwl = 0.;
  // Consider each candidate cell once.
  for (auto ndi : candidates) {
    if (!generate(ndi)) {
      continue;
    }

    double delta = hpwlObj.delta(mgr_->getNMoved(),
                                 mgr_->getMovedNodes(),
                                 mgr_->getCurLeft(),
                                 mgr_->getCurBottom(),
                                 mgr_->getCurOri(),
                                 mgr_->getNewLeft(),
                                 mgr_->getNewBottom(),
                                 mgr_->getNewOri());

    nextHpwl = currHpwl - delta;  // -delta is +ve is less.

    if (nextHpwl <= currHpwl) {
      mgr_->acceptMove();
      currHpwl = nextHpwl;
    } else {
      mgr_->rejectMove();
    }
  }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::getRange(Node* nd, Rectangle& nodeBbox)
{
  // Determines the median location for a node.

  Edge* ed;
  unsigned mid;

  Pin* pin;
  unsigned t = 0;

  double xmin = arch_->getMinX();
  double xmax = arch_->getMaxX();
  double ymin = arch_->getMinY();
  double ymax = arch_->getMaxY();

  xpts_.clear();
  ypts_.clear();
  for (int n = 0; n < nd->getNumPins(); n++) {
    pin = nd->getPins()[n];

    ed = pin->getEdge();

    nodeBbox.reset();

    int numPins = ed->getNumPins();
    if (numPins <= 1) {
      continue;
    }
    if (numPins > skipNetsLargerThanThis_) {
      continue;
    }
    if (!calculateEdgeBB(ed, nd, nodeBbox)) {
      continue;
    }

    // We've computed an interval for the pin.  We need to alter it to work for
    // the cell center. Also, we need to avoid going off the edge of the chip.
    nodeBbox.set_xmin(
        std::min(std::max(xmin, nodeBbox.xmin() - pin->getOffsetX()), xmax));
    nodeBbox.set_xmax(
        std::max(std::min(xmax, nodeBbox.xmax() - pin->getOffsetX()), xmin));
    nodeBbox.set_ymin(
        std::min(std::max(ymin, nodeBbox.ymin() - pin->getOffsetY()), ymax));
    nodeBbox.set_ymax(
        std::max(std::min(ymax, nodeBbox.ymax() - pin->getOffsetY()), ymin));

    // Record the location and pin offset used to generate this point.

    xpts_.push_back(nodeBbox.xmin());
    xpts_.push_back(nodeBbox.xmax());

    ypts_.push_back(nodeBbox.ymin());
    ypts_.push_back(nodeBbox.ymax());

    ++t;
    ++t;
  }

  // If, for some weird reason, we didn't find anything connected, then
  // return false to indicate that there's nowhere to move the cell.
  if (t <= 1) {
    return false;
  }

  // Get the median values.
  mid = t >> 1;

  std::sort(xpts_.begin(), xpts_.end());
  std::sort(ypts_.begin(), ypts_.end());

  nodeBbox.set_xmin(xpts_[mid - 1]);
  nodeBbox.set_xmax(xpts_[mid]);

  nodeBbox.set_ymin(ypts_[mid - 1]);
  nodeBbox.set_ymax(ypts_[mid]);

  return true;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::calculateEdgeBB(Edge* ed, Node* nd, Rectangle& bbox)
{
  // Computes the bounding box of an edge.  Node 'nd' is the node to SKIP.
  double curX, curY;

  bbox.reset();

  int count = 0;
  for (Pin* pin : ed->getPins()) {
    Node* other = pin->getNode();
    if (other == nd) {
      continue;
    }
    curX = other->getLeft() + 0.5 * other->getWidth() + pin->getOffsetX();
    curY = other->getBottom() + 0.5 * other->getHeight() + pin->getOffsetY();

    bbox.set_xmin(std::min(curX, bbox.xmin()));
    bbox.set_xmax(std::max(curX, bbox.xmax()));
    bbox.set_ymin(std::min(curY, bbox.ymin()));
    bbox.set_ymax(std::max(curY, bbox.ymax()));

    ++count;
  }

  return (count == 0) ? false : true;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
double DetailedGlobalSwap::delta(Node* ndi, double new_x, double new_y)
{
  // Compute change in wire length for moving node to new position.

  double old_wl = 0.;
  double new_wl = 0.;
  double x, y;
  Rectangle old_box, new_box;

  ++traversal_;
  for (int pi = 0; pi < ndi->getPins().size(); pi++) {
    Pin* pini = ndi->getPins()[pi];

    Edge* edi = pini->getEdge();

    int npins = edi->getNumPins();
    if (npins <= 1 || npins >= skipNetsLargerThanThis_) {
      continue;
    }
    if (edgeMask_[edi->getId()] == traversal_) {
      continue;
    }
    edgeMask_[edi->getId()] = traversal_;

    old_box.reset();
    new_box.reset();

    for (Pin* pinj : edi->getPins()) {
      Node* ndj = pinj->getNode();

      x = ndj->getLeft() + 0.5 * ndj->getWidth() + pinj->getOffsetX();
      y = ndj->getBottom() + 0.5 * ndj->getHeight() + pinj->getOffsetY();

      old_box.addPt(x, y);

      if (ndj == ndi) {
        x = new_x + pinj->getOffsetX();
        y = new_y + pinj->getOffsetY();
      }

      new_box.addPt(x, y);
    }
    old_wl += old_box.getWidth() + old_box.getHeight();
    new_wl += new_box.getWidth() + new_box.getHeight();
  }
  return old_wl - new_wl;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
double DetailedGlobalSwap::delta(Node* ndi, Node* ndj)
{
  // Compute change in wire length for swapping the two nodes.

  double old_wl = 0.;
  double new_wl = 0.;
  double x, y;
  Rectangle old_box, new_box;
  Node* nodes[2];
  nodes[0] = ndi;
  nodes[1] = ndj;

  ++traversal_;
  for (int c = 0; c <= 1; c++) {
    Node* ndi = nodes[c];
    for (Pin* pini : ndi->getPins()) {
      Edge* edi = pini->getEdge();

      int npins = edi->getNumPins();
      if (npins <= 1 || npins >= skipNetsLargerThanThis_) {
        continue;
      }
      if (edgeMask_[edi->getId()] == traversal_) {
        continue;
      }
      edgeMask_[edi->getId()] = traversal_;

      old_box.reset();
      new_box.reset();

      for (Pin* pinj : edi->getPins()) {
        Node* ndj = pinj->getNode();

        x = ndj->getLeft() + 0.5 * ndj->getWidth() + pinj->getOffsetX();
        y = ndj->getBottom() + 0.5 * ndj->getHeight() + pinj->getOffsetY();

        old_box.addPt(x, y);

        if (ndj == nodes[0]) {
          ndj = nodes[1];
        } else if (ndj == nodes[1]) {
          ndj = nodes[0];
        }

        x = ndj->getLeft() + 0.5 * ndj->getWidth() + pinj->getOffsetX();
        y = ndj->getBottom() + 0.5 * ndj->getHeight() + pinj->getOffsetY();

        new_box.addPt(x, y);
      }

      old_wl += old_box.getWidth() + old_box.getHeight();
      new_wl += new_box.getWidth() + new_box.getHeight();
    }
  }
  return old_wl - new_wl;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::generate(Node* ndi)
{
  double yi = ndi->getBottom() + 0.5 * ndi->getHeight();
  double xi = ndi->getLeft() + 0.5 * ndi->getWidth();

  // Determine optimal region.
  Rectangle_d bbox;
  if (!getRange(ndi, bbox)) {
    // Failed to find an optimal region.
    return false;
  }
  if (xi >= bbox.xmin() && xi <= bbox.xmax() && yi >= bbox.ymin()
      && yi <= bbox.ymax()) {
    // If cell inside box, do nothing.
    return false;
  }

  // Observe displacement limit.  I suppose there are options.
  // If we cannot move into the optimal region, we could try
  // to move closer to it.  Or, we could just reject if we cannot
  // get into the optimal region.
  int dispX, dispY;
  mgr_->getMaxDisplacement(dispX, dispY);
  Rectangle_d lbox(ndi->getLeft() - dispX,
                   ndi->getBottom() - dispY,
                   ndi->getLeft() + dispX,
                   ndi->getBottom() + dispY);
  if (lbox.xmax() <= bbox.xmin()) {
    bbox.set_xmin(ndi->getLeft());
    bbox.set_xmax(lbox.xmax());
  } else if (lbox.xmin() >= bbox.xmax()) {
    bbox.set_xmin(lbox.xmin());
    bbox.set_xmax(ndi->getLeft());
  } else {
    bbox.set_xmin(std::max(bbox.xmin(), lbox.xmin()));
    bbox.set_xmax(std::min(bbox.xmax(), lbox.xmax()));
  }
  if (lbox.ymax() <= bbox.ymin()) {
    bbox.set_ymin(ndi->getBottom());
    bbox.set_ymax(lbox.ymax());
  } else if (lbox.ymin() >= bbox.ymax()) {
    bbox.set_ymin(lbox.ymin());
    bbox.set_ymax(ndi->getBottom());
  } else {
    bbox.set_ymin(std::max(bbox.ymin(), lbox.ymin()));
    bbox.set_ymax(std::min(bbox.ymax(), lbox.ymax()));
  }

  if (mgr_->getNumReverseCellToSegs(ndi->getId()) != 1) {
    return false;
  }
  int si = mgr_->getReverseCellToSegs(ndi->getId())[0]->getSegId();

  // Position target so center of cell at center of box.
  int xj = (int) std::floor(0.5 * (bbox.xmin() + bbox.xmax())
                            - 0.5 * ndi->getWidth());
  int yj = (int) std::floor(0.5 * (bbox.ymin() + bbox.ymax())
                            - 0.5 * ndi->getHeight());

  // Row and segment for the destination.
  int rj = arch_->find_closest_row(yj);
  yj = arch_->getRow(rj)->getBottom();  // Row alignment.
  int sj = -1;
  for (int s = 0; s < mgr_->getNumSegsInRow(rj); s++) {
    DetailedSeg* segPtr = mgr_->getSegsInRow(rj)[s];
    if (xj >= segPtr->getMinX() && xj <= segPtr->getMaxX()) {
      sj = segPtr->getSegId();
      break;
    }
  }
  if (sj == -1) {
    return false;
  }
  if (ndi->getRegionId() != mgr_->getSegment(sj)->getRegId()) {
    return false;
  }

  if (mgr_->tryMove(ndi, ndi->getLeft(), ndi->getBottom(), si, xj, yj, sj)) {
    ++moves_;
    return true;
  }
  if (mgr_->trySwap(ndi, ndi->getLeft(), ndi->getBottom(), si, xj, yj, sj)) {
    ++swaps_;
    return true;
  }
  return false;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::init(DetailedMgr* mgr)
{
  mgr_ = mgr;
  arch_ = mgr->getArchitecture();
  network_ = mgr->getNetwork();
  rt_ = mgr->getRoutingParams();

  traversal_ = 0;
  edgeMask_.resize(network_->getNumEdges());
  std::fill(edgeMask_.begin(), edgeMask_.end(), 0);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
bool DetailedGlobalSwap::generate(DetailedMgr* mgr,
                                  std::vector<Node*>& candidates)
{
  ++attempts_;

  mgr_ = mgr;
  arch_ = mgr->getArchitecture();
  network_ = mgr->getNetwork();
  rt_ = mgr->getRoutingParams();

  Node* ndi = candidates[mgr_->getRandom(candidates.size())];

  return generate(ndi);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void DetailedGlobalSwap::stats()
{
  mgr_->getLogger()->info(
      DPO,
      334,
      "Generator {:s}, "
      "Cumulative attempts {:d}, swaps {:d}, moves {:5d} since last reset.",
      getName().c_str(),
      attempts_,
      swaps_,
      moves_);
}

}  // namespace dpo
