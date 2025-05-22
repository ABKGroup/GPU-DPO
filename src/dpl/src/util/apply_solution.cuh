#pragma once

#include "adjust_pos.cuh"
#include "infrastructure/GpuData.cuh"
#include <cassert>
#include <cstdio>

namespace dpl {

__global__ void copy_orig_cost_kernel(const int* cost_matrices, const char* stop_flags, const int set_size, int* costs) {
  int i = blockIdx.x;  // set

  if (stop_flags[i]) {
    auto cost_matrix = cost_matrices + i * set_size * set_size;
    auto cost = costs + i * set_size;
    for (int j = threadIdx.x; j < set_size; j += blockDim.x) {
      cost[j] = cost_matrix[j * set_size + j];
    }
  }
}

__global__ void copy_solution_cost_kernel(
  const int* cost_matrices, const char* stop_flags, const int* solutions, const int set_size, int* costs) {
  int i = blockIdx.x;  // set

  if (stop_flags[i]) {
    auto cost_matrix = cost_matrices + i * set_size * set_size;
    auto cost = costs + i * set_size;
    auto solution = solutions + i * set_size;
    for (int j = threadIdx.x; j < set_size; j += blockDim.x) {
      int sol_k = solution[j];
      cost[j] = cost_matrix[j * set_size + sol_k];
    }
  }
}

template <typename T, int BlockDim>
__global__ void block_reduce_sum(T* costs, const char* stop_flags, int batch_size, int set_size) {
  int bid = blockIdx.x;  // set
  int tid = threadIdx.x;

  if (stop_flags[bid]) {
    typedef cub::BlockReduce<T, BlockDim> BlockReduce;
    __shared__ typename BlockReduce::TempStorage temp_storage;
    int thread_data[1];

    thread_data[0] = costs[bid * set_size + tid];

    __syncthreads();

    int aggregate = BlockReduce(temp_storage).Sum(thread_data);

    __syncthreads();

    if (tid == 0) {
      costs[bid * set_size] = aggregate;
    }
  }
}

void compute_costs(const char* stop_flags, const int batch_size, const int set_size, int* costs) {
  switch (set_size) {
    case 2: block_reduce_sum<int, 2><<<batch_size, 2>>>(costs, stop_flags, batch_size, set_size); break;
    case 4: block_reduce_sum<int, 4><<<batch_size, 4>>>(costs, stop_flags, batch_size, set_size); break;
    case 8: block_reduce_sum<int, 8><<<batch_size, 8>>>(costs, stop_flags, batch_size, set_size); break;
    case 16: block_reduce_sum<int, 16><<<batch_size, 16>>>(costs, stop_flags, batch_size, set_size); break;
    case 32: block_reduce_sum<int, 32><<<batch_size, 32>>>(costs, stop_flags, batch_size, set_size); break;
    case 64: block_reduce_sum<int, 64><<<batch_size, 64>>>(costs, stop_flags, batch_size, set_size); break;
    case 128: block_reduce_sum<int, 128><<<batch_size, 128>>>(costs, stop_flags, batch_size, set_size); break;
    case 256: block_reduce_sum<int, 256><<<batch_size, 256>>>(costs, stop_flags, batch_size, set_size); break;
    case 512: block_reduce_sum<int, 512><<<batch_size, 512>>>(costs, stop_flags, batch_size, set_size); break;
    case 1024: block_reduce_sum<int, 1024><<<batch_size, 1024>>>(costs, stop_flags, batch_size, set_size); break;
    default:
      printf("[INFO GPU-DPO] unsupported set size %d\n", set_size);
  }
}

__global__ void print_copy_costs_kernel(const int* costs, int batch_size, int set_size) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    for (int i = 0; i < batch_size; ++i) {
      printf("[%d] orig/solution_costs ", i);
      for (int j = 0; j < set_size; ++j) {
        printf("%d ", (int)costs[i * set_size + j]);
      }
      printf("\n");
    }
  }
}

void compute_orig_cost(
  const int* cost_matrices, const char* stop_flags, const int batch_size, const int set_size, int* costs) {
  copy_orig_cost_kernel<<<batch_size, set_size>>>(cost_matrices, stop_flags, set_size, costs);
  compute_costs(stop_flags, batch_size, set_size, costs);
}

void compute_solution_cost(const int* cost_matrices,
                           const int* solutions,
                           const char* stop_flags,
                           const int batch_size,
                           const int set_size,
                           int* costs) {
  copy_solution_cost_kernel<<<batch_size, set_size>>>(cost_matrices, stop_flags, solutions, set_size, costs);
  compute_costs(stop_flags, batch_size, set_size, costs);
}

__global__ void store_orig_pos_kernel(GpuData db, IndependentSetMatchingState state) {
  int i = blockIdx.x;
  const int* __restrict__ independent_set = state.independent_sets + i * state.set_size;
  auto orig_x = state.orig_x + i * state.set_size;
  auto orig_y = state.orig_y + i * state.set_size;
  auto orig_seg = state.orig_seg + i * state.set_size;
  auto orig_spaces = state.orig_spaces + i * state.set_size;
  for (int j = threadIdx.x; j < state.set_size; j += blockDim.x) {
    int node_id = independent_set[j];
    if (node_id < db.num_movable_nodes) {
      assert(node_id >= 0);
      orig_x[j] = db.x[node_id];
      orig_y[j] = db.y[node_id];
      orig_seg[j] = db.node2segs[node_id];
      orig_spaces[j] = state.spaces[node_id];
    }
  }
}

__global__ void move_nodes_kernel(GpuData db, IndependentSetMatchingState state) {
  int i = blockIdx.x;
  int idx = i * state.set_size;

  if (state.stop_flags[i]) {
    if (state.orig_costs[idx] <= state.solution_costs[idx]) {
      const int* __restrict__ independent_set = state.independent_sets + i * state.set_size;
      const int* __restrict__ solution = state.solutions + i * state.set_size;
      const int* __restrict__ orig_x = state.orig_x + i * state.set_size;
      const int* __restrict__ orig_y = state.orig_y + i * state.set_size;
      const int* __restrict__ orig_seg = state.orig_seg + i * state.set_size;
      const Space* __restrict__ orig_spaces = state.orig_spaces + i * state.set_size;

      for (int j = threadIdx.x; j < state.set_size; j += blockDim.x) {
        int node_id = independent_set[j];
        int sol_k = solution[j];
        if (node_id < db.num_movable_nodes) {
          auto node_width = db.node_size_x[node_id];
          auto& x = db.x[node_id];
          auto& y = db.y[node_id];
          auto& seg = db.node2segs[node_id];
          auto& space = state.spaces[node_id];
          if (j != sol_k) {
            // Check if proposed move is within displacement bounds
            // int dx = ::abs(orig_x[sol_k] - db.init_x[node_id]);
            // int dy = ::abs(orig_y[sol_k] - db.init_y[node_id]);

            //if (dx <= db.max_displacement_x && dy <= db.max_displacement_y) {
            atomicAdd(state.device_num_moved, 1);
            auto const& orig_space = orig_spaces[sol_k];
            x = orig_x[sol_k];
            bool ret = adjust_pos(x, node_width, orig_space);
            if (!ret) {
              printf("[INFO GPU-DPO] ERROR: ism adjust_pos, node_width: %d, orig_space(%d, %d)\n",
                    node_width, orig_space.xl, orig_space.xh);
            }
            assert(ret);
            y = orig_y[sol_k];
            seg = orig_seg[sol_k];
            space = orig_space;
            //}
          }
        }
      }
    }
  }
}

__global__ void print_orig_and_solution_costs_kernel(IndependentSetMatchingState state) {
  if (blockIdx.x == 0 && threadIdx.x == 0) {
    for (int i = 0; i < state.num_independent_sets; ++i) {
      int stop = state.stop_flags[i];
      printf("[INFO GPU-DPO] [%d] orig_costs %g, solution_costs %g, delta %g, stop_flag %d\n",
             i,
             (float)state.orig_costs[i * state.set_size],
             (float)state.solution_costs[i * state.set_size],
             (float)(state.solution_costs[i * state.set_size] - state.orig_costs[i * state.set_size]),
             stop);
    }
  }
}

void apply_solution(GpuData& db, IndependentSetMatchingState& state) {
  compute_orig_cost(
    state.cost_matrices, state.stop_flags, state.num_independent_sets, state.set_size, state.orig_costs);
  compute_solution_cost(state.cost_matrices,
                        state.solutions,
                        state.stop_flags,
                        state.num_independent_sets,
                        state.set_size,
                        state.solution_costs);

  store_orig_pos_kernel<<<state.num_independent_sets, state.set_size>>>(db, state);
  move_nodes_kernel<<<state.num_independent_sets, state.set_size>>>(db, state);
  checkCuda(cudaMemcpy(&state.num_moved, state.device_num_moved, sizeof(int), cudaMemcpyDeviceToHost));
}

}  // namespace dpl