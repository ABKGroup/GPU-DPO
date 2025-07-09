#pragma once

#include "infrastructure/GpuData.cuh"

namespace dpl {

template <typename T>
__host__ __device__ bool adjust_pos(T& x, T width, const Space& space) {
  x = min(x, space.xh - width);
  x = max(x, space.xl);
  return width + space.xl <= space.xh;
}

}  // namespace dpl