#pragma once

#include "adjust_pos.cuh"
#include "infrastructure/GpuData.cuh"
#include "reduce_min.cuh"
#include "optimization/detailed_mis.cuh"

namespace dpl {

#define MAX_NODE_DEGREE 32

template <typename T>
struct SharedBox {
  T xl;
  T yl;
  T xh;
  T yh;
};

__global__ void compute_cost_matrix_kernel(GpuData db, IndependentSetMatchingState state) {
  int i = blockIdx.y;  // set
  int j = blockIdx.x;  // node in set
  const int* __restrict__ independent_set = state.independent_sets + i * state.set_size;
  auto cost_matrix = state.cost_matrices + i * state.cost_matrix_size + j * state.set_size;
  __shared__ int node_id;
  __shared__ int node_width;
  __shared__ SharedBox<int> net_boxes[MAX_NODE_DEGREE];
  __shared__ int node2pin_id_bgn;
  __shared__ int node2pin_id_end;
  if (threadIdx.x == 0) {
    node_id = independent_set[j];
    node_width = cuda::numeric_limits<int>::max();
    if (node_id < db.num_movable_nodes) {
      node_width = db.node_size_x[node_id];

      node2pin_id_bgn = db.flat_node2pin_start_map[node_id];
      node2pin_id_end = db.flat_node2pin_start_map[node_id + 1];
      node2pin_id_end = min(node2pin_id_bgn + MAX_NODE_DEGREE, node2pin_id_end);

      int idx = 0;
      for (int node2pin_id = node2pin_id_bgn; node2pin_id < node2pin_id_end; ++node2pin_id, ++idx) {
        int node_pin_id = db.flat_node2pin_map[node2pin_id];
        int net_id = db.pin2net_map[node_pin_id];
        auto& box = net_boxes[idx];
        box.xl = db.xh;
        box.yl = db.yh;
        box.xh = db.xl;
        box.yh = db.yl;
        if (db.net_mask[net_id]) {
          int net2pin_id_bgn = db.flat_net2pin_start_map[net_id];
          int net2pin_id_end = db.flat_net2pin_start_map[net_id + 1];
          for (int net2pin_id = net2pin_id_bgn; net2pin_id < net2pin_id_end; ++net2pin_id) {
            int net_pin_id = db.flat_net2pin_map[net2pin_id];
            int other_node_id = db.pin2node_map[net_pin_id];
            if (other_node_id != node_id) {
              int xxl = db.x[other_node_id] + db.node_size_x[other_node_id] / 2 + db.pin_offset_x[net_pin_id];
              int yyl = db.y[other_node_id] + db.node_size_y[other_node_id] / 2 + db.pin_offset_y[net_pin_id];
              box.xl = min(box.xl, xxl);
              box.xh = max(box.xh, xxl);
              box.yl = min(box.yl, yyl);
              box.yh = max(box.yh, yyl);
            }
          }
        }
      }
    }
  }

  __syncthreads();

  for (int k = threadIdx.x; k < state.set_size; k += blockDim.x) {
    int pos_id = independent_set[k];
    auto& cost = cost_matrix[k];
    if (node_id < db.num_movable_nodes && pos_id < db.num_movable_nodes) {
      int target_x = db.x[pos_id];
      int target_y = db.y[pos_id];
      auto const& target_space = state.spaces[pos_id];
      int target_hpwl = 0;
      
      // Must span the same number of rows (same height) and must be voltage compatible
      if (db.node_bottom_power[node_id] != db.node_bottom_power[pos_id]
          || db.node_top_power[node_id] != db.node_top_power[pos_id] 
          || db.node_size_y[node_id] != db.node_size_y[pos_id]) {
        cost = BIG_NEGATIVE;
        continue;
      }

      // Must exchange node with the same size node
      if (db.use_same_size 
          && (db.node_size_x[node_id] != db.node_size_x[pos_id] || 
              db.node_size_y[node_id] != db.node_size_y[pos_id])) {
        cost = BIG_NEGATIVE;
        continue;
      }

      if (adjust_pos(target_x, node_width, target_space)) {
        // check if the node is not in the fence region
        if (db.num_regions && !db.inside_fence(node_id, target_x, target_y)) {
          cost = BIG_NEGATIVE;
        } 
        else {
          int idx = 0;
          for (int node2pin_id = node2pin_id_bgn; node2pin_id < node2pin_id_end; ++node2pin_id, ++idx) {
            int node_pin_id = db.flat_node2pin_map[node2pin_id];
            int net_id = db.pin2net_map[node_pin_id];
            auto const& box = net_boxes[idx];
            if (db.net_mask[net_id]) {
              int xxl = target_x + db.node_size_x[pos_id] / 2 + db.pin_offset_x[node_pin_id];
              int yyl = target_y + db.node_size_y[pos_id] / 2 + db.pin_offset_y[node_pin_id];
              int bxl = min(box.xl, xxl);
              int bxh = max(box.xh, xxl);
              int byl = min(box.yl, yyl);
              int byh = max(box.yh, yyl);
              target_hpwl += (bxh - bxl) + (byh - byl);
            }
          }
          cost = target_hpwl;
        }
      } else {
        cost = BIG_NEGATIVE;
      }
    } else {
      cost = BIG_NEGATIVE;
    }
  }
}

__global__ void postprocess_cost_matrix_kernel(GpuData db, IndependentSetMatchingState state) {
  int i = blockIdx.y;
  int j = blockIdx.x;
  const int* __restrict__ independent_set = state.independent_sets + i * state.set_size;
  auto cost_matrix = state.cost_matrices + i * state.cost_matrix_size + j * state.set_size;
  auto max_cost = state.cost_matrices_copy[i * state.cost_matrix_size];
  for (int k = threadIdx.x; k < state.set_size; k += blockDim.x) {
    int node_id = independent_set[j];
    int pos_id = independent_set[k];
    auto& cost = cost_matrix[k];
    if (node_id < db.num_movable_nodes && pos_id < db.num_movable_nodes) {
      if (cost >= 0) {
        cost = max_cost - cost;
      }
    } else if (j == k) {
      cost = max_cost;
    }
  }
}

template <typename T>
__global__ void print_cost_matrix_kernel(const T* cost_matrix, int set_size) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    printf("[%dx%d]\n", set_size, set_size);
    for (int r = 0; r < set_size; ++r) {
      for (int c = 0; c < set_size; ++c) {
        auto cost = cost_matrix[r * set_size + c];
        if (cost == BIG_NEGATIVE) {
          printf("X ");
        } else {
          printf("%g ", (double)cost);
        }
      }
      printf("\n");
    }
    printf("\n");
  }
}

__global__ void print_max_cost_kernel(IndependentSetMatchingState state) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    printf("[%d]\n", state.num_independent_sets);
    for (int i = 0; i < state.num_independent_sets; ++i) {
      printf("%g ", (double)state.cost_matrices_copy[i * state.cost_matrix_size]);
    }
    printf("\n");
  }
}

__global__ void check_cost_matrices_kernel(IndependentSetMatchingState state) {
  unsigned int tid = threadIdx.x;
  unsigned int bid = blockIdx.x;
  if (tid == 0 && bid == 0) {
    for (int i = 0; i < state.num_independent_sets; ++i) {
      for (int j = 0; j < state.cost_matrix_size; ++j) {
        auto cost = state.cost_matrices[i * state.cost_matrix_size + j];
        assert(cost == cuda::numeric_limits<int>::lowest() || cost >= 0);
      }
    }
  }
}

template <typename T>
struct CompareCost {
  __host__ __device__ bool operator()(T cost1, T cost2) const { return cost1 > cost2; }
};

void cost_matrix_construction(const GpuData& db, IndependentSetMatchingState& state) {
  dim3 grid(state.set_size, state.num_independent_sets, 1);
  compute_cost_matrix_kernel<<<grid, state.set_size>>>(db, state);

  checkCuda(cudaMemcpy(state.cost_matrices_copy,
                       state.cost_matrices,
                       sizeof(int) * state.num_independent_sets * state.cost_matrix_size,
                       cudaMemcpyDeviceToDevice));
  int ref = 0;
  reduce_2d(state.cost_matrices_copy,
            state.num_independent_sets,
            state.cost_matrix_size,
            ref,
            CompareCost<int>());

  postprocess_cost_matrix_kernel<<<grid, state.set_size>>>(db, state);
}

}  // namespace dpl
