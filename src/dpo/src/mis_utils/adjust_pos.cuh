#pragma once

#include "../detailed_db_cuda.cuh"

namespace dpo {

template <typename T>
__host__ __device__ bool adjust_pos(T& x, T width, const Space<T>& space) {
    x = min(x, space.xh - width);
    x = max(x, space.xl);
    return width + space.xl <= space.xh;
}

}  // namespace dpo