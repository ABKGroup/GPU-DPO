#include <cuda.h>
#include <cuda_runtime.h>

#include "infrastructure/GpuData.cuh"

namespace dpl {

__global__ void computeTotalHpwlKernel(GpuData gd, const int* nodeX_, const int* nodeY_, int* netHpwls) {
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < gd.numNets; i += blockDim.x * gridDim.x) {
    netHpwls[i] = gd.computeNetHpwl(i, nodeX_, nodeY_);
  }
}

int computeTotalHpwl(const GpuData& gd, const int* nodeX_, const int* nodeY_, int* netHpwls) {
  computeTotalHpwlKernel<<<ceilDiv(gd.numNets, 512), 512>>>(gd, nodeX_, nodeY_, netHpwls);

  int* dOut = NULL;
  // Determine temporary device storage requirements
  void* dTempStorage = NULL;
  size_t tempStorageBytes = 0;
  cub::DeviceReduce::Sum(dTempStorage, tempStorageBytes, netHpwls, dOut, gd.numNets);
  // Allocate temporary storage
  checkCuda(cudaMalloc(&dTempStorage, tempStorageBytes));
  checkCuda(cudaMalloc(&dOut, sizeof(int)));
  // Run sum-reduction
  cub::DeviceReduce::Sum(dTempStorage, tempStorageBytes, netHpwls, dOut, gd.numNets);
  // copy d_out to hpwl
  int hpwl = 0;
  checkCuda(cudaMemcpy(&hpwl, dOut, sizeof(int), cudaMemcpyDeviceToHost));
  cudaFree(dTempStorage);
  cudaFree(dOut);

  return hpwl;
}

} // namespace dpl