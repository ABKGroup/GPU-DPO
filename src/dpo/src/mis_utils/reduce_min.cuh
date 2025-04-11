#pragma once

#include "gpudp/dp/utils.cuh"

namespace dpo {

template <typename T, typename V>
__device__ void warpReduce(/*volatile*/ T* sdata, int tid, V comp) {
    sdata[tid] = sdata[tid + 32 * !comp(sdata[tid], sdata[tid + 32])];
    sdata[tid] = sdata[tid + 16 * !comp(sdata[tid], sdata[tid + 16])];
    sdata[tid] = sdata[tid + 8 * !comp(sdata[tid], sdata[tid + 8])];
    sdata[tid] = sdata[tid + 4 * !comp(sdata[tid], sdata[tid + 4])];
    sdata[tid] = sdata[tid + 2 * !comp(sdata[tid], sdata[tid + 2])];
    sdata[tid] = sdata[tid + 1 * !comp(sdata[tid], sdata[tid + 1])];
}

template <typename T, typename V, unsigned int BlockSize = 256>
__global__ void reduce4(T* globalInputData, T* globalOutputData, int n, T ref, V comp) {
    __shared__ T sdata[BlockSize];

    int tid = threadIdx.x;
    int index = blockIdx.x * (blockDim.x * 2) + threadIdx.x;
    int indexWithOffset = index + blockDim.x;

    if (index >= n)
        sdata[tid] = ref;
    else if (indexWithOffset >= n)
        sdata[tid] = globalInputData[index];
    else {
        // printf("tid = %d, index = %d, indexWithOffset = %d, index+blockDim.x*!comp(globalInputData[index],
        // globalInputData[indexWithOffset]) = %d\n",
        //         tid, index, indexWithOffset, index+blockDim.x*!comp(globalInputData[index],
        //         globalInputData[indexWithOffset])
        //         );
        sdata[tid] = (comp(globalInputData[index], globalInputData[indexWithOffset]))
                         ? globalInputData[index]
                         : globalInputData[indexWithOffset];
    }

    __syncthreads();

    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) {
            sdata[tid] = sdata[tid + s * !comp(sdata[tid], sdata[tid + s])];
        }

        __syncthreads();
    }

    if (tid == 0) {
        globalOutputData[blockIdx.x] = sdata[0];
    }
}

template <typename T, typename V, unsigned int BlockSize = 256>
void reduce(T* fMatrix_Device, int iMatrixSize, const T& ref, const V& comp) {
    for (int i = 1, iNum = iMatrixSize; i < iMatrixSize; i = 2 * i * BlockSize) {
        int iBlockNum = (iNum + (2 * BlockSize) - 1) / (2 * BlockSize);
        reduce4<T, V, BlockSize><<<iBlockNum, BlockSize>>>(fMatrix_Device, fMatrix_Device, iNum, ref, comp);
        iNum = iBlockNum;
    }
}

template <typename T, typename V, unsigned int BlockSize = 256>
void reduce(T* fMatrix_Device, int iMatrixSize, const T& ref, const V& comp, cudaStream_t& stream) {
    for (int i = 1, iNum = iMatrixSize; i < iMatrixSize; i = 2 * i * BlockSize) {
        int iBlockNum = (iNum + (2 * BlockSize) - 1) / (2 * BlockSize);
        reduce4<T, V, BlockSize><<<iBlockNum, BlockSize, 0, stream>>>(fMatrix_Device, fMatrix_Device, iNum, ref, comp);
        iNum = iBlockNum;
    }
}

template <typename T, typename V, unsigned int BlockSize = 256>
__global__ void reduce4_2d(T* globalInputData, T* globalOutputData, int nc, int n, T ref, V comp) {
    __shared__ T sdata[BlockSize];

    // compute indices
    int tid = threadIdx.x;
    int yOffset = blockIdx.y * nc;
    int index = yOffset + blockIdx.x * (blockDim.x * 2) + threadIdx.x;

    int indexWithOffset = index + blockDim.x;

    if (index >= yOffset + n)
        sdata[tid] = ref;
    else if (indexWithOffset >= yOffset + n)
        sdata[tid] = globalInputData[index];
    else {
        // printf("tid = %d, index = %d, indexWithOffset = %d, index+blockDim.x*!comp(globalInputData[index],
        // globalInputData[indexWithOffset]) = %d\n",
        //         tid, index, indexWithOffset, index+blockDim.x*!comp(globalInputData[index],
        //         globalInputData[indexWithOffset])
        //         );
        sdata[tid] = (comp(globalInputData[index], globalInputData[indexWithOffset]))
                         ? globalInputData[index]
                         : globalInputData[indexWithOffset];
    }

    __syncthreads();

    // reduction for data in shared memory
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) {
            sdata[tid] = sdata[tid + s * !comp(sdata[tid], sdata[tid + s])];
        }

        __syncthreads();
    }

    // write data back from shared memory to global memory
    if (tid == 0) {
        globalOutputData[yOffset + blockIdx.x] = sdata[0];
        // printf("globalOutputData[%d] = %g\n", blockIdx.y*nc + blockIdx.x, sdata[0].cost);
    }
}

template <typename T, typename V, unsigned int BlockSize = 256>
void reduce_2d(T* fMatrix_Device, int m, int n, const T& ref, const V& comp) {
    for (int i = 1, iNum = n; i < n; i = 2 * i * BlockSize) {
        int iBlockNum = (iNum + (2 * BlockSize) - 1) / (2 * BlockSize);
        dim3 grid(iBlockNum, m, 1);
        reduce4_2d<T, V, BlockSize><<<grid, BlockSize>>>(fMatrix_Device, fMatrix_Device, n, iNum, ref, comp);
        iNum = iBlockNum;
    }
}

}  // namespace dpo