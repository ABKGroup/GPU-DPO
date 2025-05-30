// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2021-2025, The OpenROAD Authors

#pragma once

#include <cuda.h>
#include <cuda_runtime.h>

#include "util/PitchNestedVector.cuh"
#include "util/cudaUtils.cuh"
#include "FlattenedData.h"

#include <cassert>
#include <climits>
#include <cmath>
#include <cstdio>
#include <omp.h>

#define MAX_NET_DEGREE 40   // an estimation

namespace dpl {

template <typename T1, typename T2>
__device__ inline void device_swap(T1& a, T2& b) {
  T1 tmp = a;
  a = b;
  b = tmp;
}

inline __host__ __device__ int floorDiv(int a, int b) {
  int q = a / b;
  int r = a % b;
  if ((r != 0) && ((r < 0) != (b < 0))) q--;
  return q;
}

inline __host__ __device__ int ceilDiv(int a, int b) {
  int q = a / b;
  int r = a % b;
  if ((r != 0) && ((r > 0) == (b > 0))) q++;
  return q;
}

inline __host__ __device__ int roundDiv(int a, int b) {
  return (a + (b > 0 ? b / 2 : -((b < 0 ? -b : b) / 2))) / b;
}

// defines a horizontal space in a row
struct Space {
  int xl;
  int xh;
};

// =============================================================
// Used in CUB reduction to track best (min) cost and index
struct ItemWithIndex {
  int value;
  int index;
};

struct ReduceMinOP {
  __host__ __device__ ItemWithIndex operator()(const ItemWithIndex& a, const ItemWithIndex& b) const {
      return (a.value < b.value) ? a : b;
  }
};

struct Box {
  int xl;
  int yl;
  int xh;
  int yh;
  __host__ __device__ Box() {
    xl = cuda::numeric_limits<int>::max();
    yl = cuda::numeric_limits<int>::max();
    xh = cuda::numeric_limits<int>::lowest();
    yh = cuda::numeric_limits<int>::lowest();
  }
  __host__ __device__ Box(int xxl, int yyl, int xxh, int yyh) 
      : xl(xxl), yl(yyl), xh(xxh), yh(yyh) 
  {
  }

  __host__ __device__ int center_x() const { return (xl + xh) / 2; }
  __host__ __device__ int center_y() const { return (yl + yh) / 2; }
};

struct RowMapIndex {
  int row_id;
  int sub_id;
};

struct BinMapIndex {
  int bin_id;
  int sub_id;
};

// this db acts like the network and architecture of the design
// here we manage the tasks of the detailed placement operators too
// includes: edge spacing check, site alignment, overlap check, etc.
class GpuData {
public:
  int* x = nullptr;
  int* y = nullptr;
  int* init_x = nullptr;
  int* init_y = nullptr;
  int* node_size_x = nullptr;
  int* node_size_y = nullptr;
  int* node_top_power = nullptr;
  int* node_bottom_power = nullptr;
  int* node2segs = nullptr;

  int* pin_offset_x = nullptr;
  int* pin_offset_y = nullptr;

  int* flat_node2pin_start_map = nullptr;
  int* flat_node2pin_map = nullptr;
  int* pin2node_map = nullptr;

  int* flat_net2pin_start_map = nullptr;
  int* flat_net2pin_map = nullptr;
  int* pin2net_map = nullptr;

  int* flat_region_boxes_start = nullptr;
  int* flat_region_boxes = nullptr;
  int* node2fence_region_map = nullptr;

  int* net_mask = nullptr;

  int* node_left_padding = nullptr;
  int* node_right_padding = nullptr;

  int xl;
  int yl;
  int xh;
  int yh;

  int num_sites_x;
  int num_sites_y;
  int row_height;
  int site_width;
  int site_spacing;
  int row_left;

  int max_displacement_x;
  int max_displacement_y;

  int num_nets;
  int num_movable_nodes;
  int num_nodes;
  int num_pins;
  int num_regions;
  int region_boxes_size;

  int num_threads;

  int num_bins_x;
  int num_bins_y;
  float bin_size_x;
  float bin_size_y;

  bool use_same_size;

  GpuData() = default;

  void copyToDevice(const FlattenedData& db) {
    allocateCopyCuda(x, db.x.data(), db.num_nodes);
    allocateCopyCuda(y, db.y.data(), db.num_nodes);
    allocateCopyCuda(init_x, db.init_x.data(), db.num_nodes);
    allocateCopyCuda(init_y, db.init_y.data(), db.num_nodes);
    allocateCopyCuda(node_size_x, db.node_size_x.data(), db.num_nodes);
    allocateCopyCuda(node_size_y, db.node_size_y.data(), db.num_nodes);
    allocateCopyCuda(node2segs, db.node2segs.data(), db.num_nodes);
    allocateCopyCuda(pin_offset_x, db.pin_offset_x.data(), db.num_pins);
    allocateCopyCuda(pin_offset_y, db.pin_offset_y.data(), db.num_pins);
    allocateCopyCuda(flat_node2pin_start_map, db.flat_node2pin_start_map.data(), db.num_nodes + 1);
    allocateCopyCuda(flat_node2pin_map, db.flat_node2pin_map.data(), db.num_pins);
    allocateCopyCuda(pin2node_map, db.pin2node_map.data(), db.num_pins);
    allocateCopyCuda(flat_net2pin_start_map, db.flat_net2pin_start_map.data(), db.num_nets + 1);
    allocateCopyCuda(flat_net2pin_map, db.flat_net2pin_map.data(), db.num_pins);
    allocateCopyCuda(pin2net_map, db.pin2net_map.data(), db.num_pins);
    allocateCopyCuda(net_mask, db.net_mask.data(), db.num_nets);
    allocateCopyCuda(flat_region_boxes_start, db.flat_region_boxes_start.data(), db.num_regions + 1);
    allocateCopyCuda(flat_region_boxes, db.flat_region_boxes.data(), db.region_boxes_size);
    allocateCopyCuda(node2fence_region_map, db.node2fence_region_map.data(), db.num_nodes);
    allocateCopyCuda(node_left_padding, db.node_left_padding.data(), db.num_nodes);
    allocateCopyCuda(node_right_padding, db.node_right_padding.data(), db.num_nodes);
    allocateCopyCuda(node_top_power, db.node_top_power.data(), db.num_nodes);
    allocateCopyCuda(node_bottom_power, db.node_bottom_power.data(), db.num_nodes);

    xl = db.xl;
    xh = db.xh;
    yl = db.yl;
    yh = db.yh;
    row_height = db.row_height;
    site_width = db.site_width;
    site_spacing = db.site_spacing;
    row_left = db.row_left;

    max_displacement_x = db.max_displacement_x;
    max_displacement_y = db.max_displacement_y;

    num_sites_x = db.num_sites_x;
    num_sites_y = db.num_sites_y;
    num_threads = db.num_threads;

    num_nodes = db.num_nodes;
    num_movable_nodes = db.num_movable_nodes;
    num_nets = db.num_nets;
    num_pins = db.num_pins;
    num_regions = db.num_regions;
    region_boxes_size = db.region_boxes_size;

    use_same_size = db.use_same_size;
  }

  void copyToHost(FlattenedData& db) {
    copyBackToCpu(x, db.x.data(), num_nodes);
    copyBackToCpu(y, db.y.data(), num_nodes);
    copyBackToCpu(init_x, db.init_x.data(), num_nodes);
    copyBackToCpu(init_y, db.init_y.data(), num_nodes);
    copyBackToCpu(node_size_x, db.node_size_x.data(), num_nodes);
    copyBackToCpu(node_size_y, db.node_size_y.data(), num_nodes);
    copyBackToCpu(node2segs, db.node2segs.data(), num_nodes);
    copyBackToCpu(pin_offset_x, db.pin_offset_x.data(), num_pins);
    copyBackToCpu(pin_offset_y, db.pin_offset_y.data(), num_pins);
    copyBackToCpu(flat_node2pin_start_map, db.flat_node2pin_start_map.data(), num_nodes + 1);
    copyBackToCpu(flat_node2pin_map, db.flat_node2pin_map.data(), num_pins);
    copyBackToCpu(pin2node_map, db.pin2node_map.data(), num_pins);
    copyBackToCpu(flat_net2pin_start_map, db.flat_net2pin_start_map.data(), num_nets + 1);
    copyBackToCpu(flat_net2pin_map, db.flat_net2pin_map.data(), num_pins);
    copyBackToCpu(pin2net_map, db.pin2net_map.data(), num_pins);
    copyBackToCpu(net_mask, db.net_mask.data(), num_nets);
    copyBackToCpu(flat_region_boxes_start, db.flat_region_boxes_start.data(), num_regions + 1);
    copyBackToCpu(flat_region_boxes, db.flat_region_boxes.data(), region_boxes_size);
    copyBackToCpu(node2fence_region_map, db.node2fence_region_map.data(), num_nodes);

    db.xl = xl;
    db.xh = xh;
    db.yl = yl;
    db.yh = yh;
    db.row_height = row_height;
    db.site_width = site_width;
    db.site_spacing = site_spacing;
    db.row_left = row_left;

    db.num_sites_x = num_sites_x;
    db.num_sites_y = num_sites_y;
    db.num_threads = num_threads;

    db.num_nodes = num_nodes;
    db.num_movable_nodes = num_movable_nodes;
    db.num_nets = num_nets;
    db.num_pins = num_pins;
    db.num_regions = num_regions;
    db.region_boxes_size = region_boxes_size;
  }

  void freeData() {
    cudaFree(x);
    cudaFree(y);
    cudaFree(init_x);
    cudaFree(init_y);
    cudaFree(node_size_x);
    cudaFree(node_size_y);
    cudaFree(node2segs);
    cudaFree(pin_offset_x);
    cudaFree(pin_offset_y);
    cudaFree(flat_node2pin_start_map);
    cudaFree(flat_node2pin_map);
    cudaFree(pin2node_map);
    cudaFree(flat_net2pin_start_map);
    cudaFree(flat_net2pin_map);
    cudaFree(pin2net_map);
    cudaFree(net_mask);
    cudaFree(flat_region_boxes_start);
    cudaFree(flat_region_boxes);
    cudaFree(node2fence_region_map);
    cudaFree(node_left_padding);
    cudaFree(node_right_padding);
    cudaFree(node_bottom_power);
    cudaFree(node_top_power);
  }

  void set_num_bins(int num_bins_x_, int num_bins_y_) {
    num_bins_x = num_bins_x_;
    num_bins_y = num_bins_y_;
    bin_size_x = (xh - xl) / num_bins_x_;
    bin_size_y = (yh - yl) / num_bins_y_;
  }

  inline __device__ int pos2bin_x(int xx) const {
    int bx = floorDiv((xx - xl), bin_size_x);
    bx = max(bx, 0);
    bx = min(bx, num_bins_x - 1);
    return bx;
  }

  inline __device__ int pos2bin_y(float yy) const {
    int by = floorDiv((yy - yl), bin_size_y);
    by = max(by, 0);
    by = min(by, num_bins_y - 1);
    return by;
  }

  inline __device__ int align2site(int xx) const {
    return (int)floorDiv((xx - xl), site_width) * site_width + xl;
  }

  inline __device__ Space align2site(Space space) const {
    space.xl = ceilDiv((space.xl - xl), site_width) * site_width + xl;
    space.xh = floorDiv((space.xh - xl), site_width) * site_width + xl;
    return space;
  }

  inline __device__ void shift_box_to_layout(Box& box) const {
    box.xl = max(box.xl, xl);
    box.xl = min(box.xl, xh);
    box.xh = max(box.xh, xl);
    box.xh = min(box.xh, xh);
    box.yl = max(box.yl, yl);
    box.yl = min(box.yl, yh);
    box.yh = max(box.yh, yl);
    box.yh = min(box.yh, yh);
  }

  __device__ Box compute_optimal_region(int node_id, const int* xx, const int* yy, const int* size_x, const int* size_y) const {
    Box box(xh, yh, xl, yl);
    for (int node2pin_id = flat_node2pin_start_map[node_id]; node2pin_id < flat_node2pin_start_map[node_id + 1]; ++node2pin_id) {
      int node_pin_id = flat_node2pin_map[node2pin_id];
      int net_id = pin2net_map[node_pin_id];
      if (net_mask[net_id]) {
        for (int net2pin_id = flat_net2pin_start_map[net_id]; net2pin_id < flat_net2pin_start_map[net_id + 1]; ++net2pin_id) {
          int net_pin_id = flat_net2pin_map[net2pin_id];
          int other_node_id = pin2node_map[net_pin_id];
          if (node_id != other_node_id) {
            box.xl = min(box.xl, xx[other_node_id] - pin_offset_x[net_pin_id]);
            box.xh = max(box.xh, xx[other_node_id] - pin_offset_x[net_pin_id]);
            box.yl = min(box.yl, yy[other_node_id] - pin_offset_y[net_pin_id]);
            box.yh = max(box.yh, yy[other_node_id] - pin_offset_y[net_pin_id]);
          }
        }
      }
    }
    shift_box_to_layout(box);
    return box;
  }
  
  __device__ int compute_net_hpwl(int net_id, const int* xx, const int* yy) const {
    if (flat_net2pin_start_map[net_id + 1] - flat_net2pin_start_map[net_id] <= 1) {
      return 0;
    }
    Box box(xh, yh, xl, yl);
    for (int net2pin_id = flat_net2pin_start_map[net_id]; net2pin_id < flat_net2pin_start_map[net_id + 1]; ++net2pin_id) {
      int net_pin_id = flat_net2pin_map[net2pin_id];
      int other_node_id = pin2node_map[net_pin_id];
      box.xl = min(box.xl, xx[other_node_id] + (int)(0.5 * node_size_x[other_node_id]) + pin_offset_x[net_pin_id]);
      box.xh = max(box.xh, xx[other_node_id] + (int)(0.5 * node_size_x[other_node_id]) + pin_offset_x[net_pin_id]);
      box.yl = min(box.yl, yy[other_node_id] + (int)(0.5 * node_size_y[other_node_id]) + pin_offset_y[net_pin_id]);
      box.yh = max(box.yh, yy[other_node_id] + (int)(0.5 * node_size_y[other_node_id]) + pin_offset_y[net_pin_id]);
    }
    if (box.xl == xh || box.yl == yh) {
      return 0;
    }
    return (box.xh - box.xl) + (box.yh - box.yl);
  }

  __device__ bool inside_fence(int node_id, int xx, int yy) const {
    int node_xl = xx;
    int node_yl = yy;
    int node_xh = node_xl + node_size_x[node_id];
    int node_yh = node_yl + node_size_y[node_id];

    bool legal_flag = true;
    int region_id = node2fence_region_map[node_id];
    if (region_id < num_regions) {
      int box_bgn = flat_region_boxes_start[region_id];
      int box_end = flat_region_boxes_start[region_id + 1];
      int node_area = (node_xh - node_xl) * (node_yh - node_yl);
      for (int box_id = box_bgn; box_id < box_end; ++box_id) {
        int box_offset = box_id * 4;
        int box_xl = flat_region_boxes[box_offset];
        int box_xh = flat_region_boxes[box_offset + 1];
        int box_yl = flat_region_boxes[box_offset + 2];
        int box_yh = flat_region_boxes[box_offset + 3];

        int dx = max(min(node_xh, box_xh) - max(node_xl, box_xl), (int)0);
        int dy = max(min(node_yh, box_yh) - max(node_yl, box_yl), (int)0);
        int overlap = dx * dy;
        if (overlap > 0) {
          node_area -= overlap;
        }
      }
      if (node_area > 0) {
        legal_flag = false;
      }
    }
    return legal_flag;
  }

  std::vector<std::vector<int>> reorder_row_map(
    const int* host_x, const int* host_y, const int* host_node_size_x, const int* host_node_size_y, std::vector<std::vector<int>>& row2node_map, int sort_coord) {
    if (sort_coord < 0 || sort_coord > 2) sort_coord = 0;

    std::vector<std::vector<int>> row2node_map_helper;
    row2node_map_helper.resize(row2node_map.size());
    for (int i = 0; i < row2node_map.size(); ++i) {
      row2node_map_helper[i] = row2node_map[i];
    }

    for (int i = 0; i < row2node_map.size(); ++i) {
      auto& row2nodes = row2node_map_helper[i];
      if (!row2nodes.empty()) {
        switch (sort_coord) {
          case 0:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1] + host_node_size_x[node_id1] / 2;
              int x2 = host_x[node_id2] + host_node_size_x[node_id2] / 2;
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          case 1:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1];
              int x2 = host_x[node_id2];
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          case 2:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1] + host_node_size_x[node_id1];
              int x2 = host_x[node_id2] + host_node_size_x[node_id2];
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          default:
            break;
        }
      }
    }
    return row2node_map_helper;
  }

  void make_row2node_map(const int* host_x,
                         const int* host_y,
                         const int* host_node_size_x,
                         const int* host_node_size_y,
                         int host_num_nodes,
                         std::vector<std::vector<int>>& row2node_map,
                         int sort_coord = 0) {
    if (sort_coord < 0 || sort_coord > 2) sort_coord = 0;
    for (int i = 0; i < host_num_nodes; ++i) {
      int node_yl = host_y[i];
      int node_yh = node_yl + host_node_size_y[i];

      int row_idxl = floorDiv(node_yl - yl, row_height);
      int row_idxh = ceilDiv(node_yh - yl, row_height);
      row_idxl = max(row_idxl, 0);
      row_idxh = min(row_idxh, num_sites_y);

      for (int row_id = row_idxl; row_id < row_idxh; ++row_id) {
        int row_yl = yl + row_id * row_height;
        int row_yh = row_yl + row_height;

        if (node_yl < row_yh && node_yh > row_yl) {
          row2node_map[row_id].push_back(i);
        }
      }
    }

#pragma omp parallel for num_threads(num_threads) schedule(dynamic, 1)
    for (int i = 0; i < num_sites_y; ++i) {
      auto& row2nodes = row2node_map[i];
      std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
        int x1 = host_x[node_id1];
        int x2 = host_x[node_id2];
        return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
      });
      if (!row2nodes.empty()) {
        for (int j = 1; j < row2nodes.size(); ++j) {
          int node_id1 = row2nodes.at(j - 1);
          int node_id2 = row2nodes.at(j);
          if (node_id1 >= num_movable_nodes && node_id2 >= num_movable_nodes) {
            int xl1 = host_x[node_id1];
            int xl2 = host_x[node_id2];
            int width1 = host_node_size_x[node_id1];
            int width2 = host_node_size_x[node_id2];
            int xh1 = xl1 + width1;
            int xh2 = xl2 + width2;
            if (xh1 >= xh2 && !row2nodes.empty()) {
              row2nodes.erase(row2nodes.begin() + j);
              --j;
            }
          }
        }

        switch (sort_coord) {
          case 0:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1] + host_node_size_x[node_id1] / 2;
              int x2 = host_x[node_id2] + host_node_size_x[node_id2] / 2;
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          case 1:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1];
              int x2 = host_x[node_id2];
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          case 2:
            std::sort(row2nodes.begin(), row2nodes.end(), [&](int node_id1, int node_id2) {
              int x1 = host_x[node_id1] + host_node_size_x[node_id1];
              int x2 = host_x[node_id2] + host_node_size_x[node_id2];
              return x1 < x2 || (x1 == x2 && node_id1 < node_id2);
            });
            break;
          default:
            break;
        }
      }
    }
  }

  void make_row2node_map_with_spaces(const int* host_x,
                                     const int* host_y,
                                     const int* host_node_size_x,
                                     const int* host_node_size_y,
                                     std::vector<std::vector<int>>& row2node_map,
                                     std::vector<RowMapIndex>& node2row_map,
                                     std::vector<Space>& spaces,
                                     int sort_coord = 0) {
    make_row2node_map(host_x, host_y, host_node_size_x, host_node_size_y, num_nodes + 2, row2node_map, sort_coord);

    std::vector<std::vector<int>> row2node_map_helper = reorder_row_map(host_x, host_y, host_node_size_x, host_node_size_y, row2node_map, sort_coord);

    for (int i = 0; i < num_sites_y; ++i) {
      for (unsigned int j = 0; j < row2node_map[i].size(); ++j) {
        int node_id = row2node_map[i][j];
        if (node_id < num_movable_nodes) {
          RowMapIndex& row_id = node2row_map[node_id];
          row_id.row_id = i;
          row_id.sub_id = j;
        }
      }
    }

    for (int i = 0; i < num_sites_y; ++i) {
      for (unsigned int j = 0; j < row2node_map[i].size(); ++j) {
        int node_id = row2node_map[i][j];
        if (node_id < num_movable_nodes) {
          assert(j);
          int j_helper = std::find(row2node_map_helper[i].begin(), row2node_map_helper[i].end(), node_id) - row2node_map_helper[i].begin();
          int left_node_id = row2node_map[i][j_helper - 1];

          spaces[node_id].xl = host_x[left_node_id] + host_node_size_x[left_node_id];
          assert(j + 1 < row2node_map[i].size());
          int right_node_id = row2node_map[i][j + 1];
          spaces[node_id].xh = host_x[right_node_id];
        }
      }
    }
  }

  void make_bin2node_map(const int* host_x,
                         const int* host_y,
                         const int* host_node_size_x,
                         const int* host_node_size_y,
                         std::vector<std::vector<int>>& bin2node_map,
                         std::vector<BinMapIndex>& node2bin_map) {
    for (int i = 0; i < num_movable_nodes; ++i) {
      int node_id = i;
      int node_x = host_x[node_id] + host_node_size_x[node_id] / 2;
      int node_y = host_y[node_id] + host_node_size_y[node_id] / 2;

      int bx = min(max((int)floorDiv(node_x - xl, bin_size_x), 0), num_bins_x - 1);
      int by = min(max((int)floorDiv(node_y - yl, bin_size_y), 0), num_bins_y - 1);
      int bin_id = bx * num_bins_y + by;
      int sub_id = bin2node_map.at(bin_id).size();
      bin2node_map.at(bin_id).push_back(node_id);
    }
    for (int bin_id = 0; bin_id < bin2node_map.size(); ++bin_id) {
      for (int sub_id = 0; sub_id < bin2node_map[bin_id].size(); ++sub_id) {
        int node_id = bin2node_map[bin_id][sub_id];
        BinMapIndex& bm_idx = node2bin_map.at(node_id);
        bm_idx.bin_id = bin_id;
        bm_idx.sub_id = sub_id;
      }
    }
  }
};

int compute_total_hpwl(const GpuData& db, const int* xx, const int* yy, int* net_hpwls);

} // namespace dpl