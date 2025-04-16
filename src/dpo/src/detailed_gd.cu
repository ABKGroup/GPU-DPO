#include <algorithm>
#include "include/cuda_fp16.h"

template <typename T>
inline __device__ T RsqrtFunc(T x) {
  return rsqrt(x);
}

template <>
inline __device__ half RsqrtFunc(half x) {
  return hrsqrt(x);
}

template <typename T>
inline __device__ T AbsFunc(T x) {
  return abs(x);
}

template <>
inline __device__ half AbsFunc(half x) {
  return abs(__half2float(x));
}

template <typename T>
inline __device__ T MaxFunc(T x, T y) {
  return max(x, y);
}

template <>
inline __device__ half MaxFunc(half x, half y) {
  return max(__half2float(x), __half2float(y));
}

template <typename T>
inline __device__ T SgnFunc(T x) {
  return static_cast<T>(x != 0 ? (x > 0 ? 1 : -1) : 0);
}

template <>
inline __device__ half SgnFunc(half x) {
  return __float2half(__half2float(x) != 0 ? (__half2float(x) > 0 ? 1 : -1) : 0);
}

// TODO: change the input elements to the cell locations
template <typename T>
__global__ void CalApplyProximalGradientDescentKernel(const size_t input_elements, T *var, const T *alpha, const T *l1,
                                                      const T *l2, const T *delta, T *output) {
  if (l1[0] > static_cast<T>(0.0)) {
    for (size_t pos = blockIdx.x * blockDim.x + threadIdx.x; pos < static_cast<int>(input_elements);
         pos += gridDim.x * blockDim.x) {
      auto prox_v = var[pos];
      prox_v -= delta[pos] * alpha[0];
      var[pos] = SgnFunc(prox_v) * MaxFunc(AbsFunc(prox_v) - alpha[0] * l1[0], static_cast<T>(0.0)) /
                 (static_cast<T>(1) + l2[0] * alpha[0]);
    }
  } else {
    for (size_t pos = blockIdx.x * blockDim.x + threadIdx.x; pos < static_cast<int>(input_elements);
         pos += gridDim.x * blockDim.x) {
      auto prox_v = var[pos];
      prox_v -= delta[pos] * alpha[0];
      var[pos] = prox_v / (static_cast<T>(1) + l2[0] * alpha[0]);
    }
  }
}

template <typename T>
cudaError_t CalApplyProximalGradientDescent(const size_t input_elements, T *var, const T *alpha, const T *l1,
                                            const T *l2, const T *delta, T *output, const uint32_t &device_id,
                                            cudaStream_t cuda_stream) {
  CalApplyProximalGradientDescentKernel<<<CUDA_BLOCKS(device_id, input_elements), CUDA_THREADS(device_id), 0,
                                          cuda_stream>>>(input_elements, var, alpha, l1, l2, delta, output);
  return GetCudaStatus();
}