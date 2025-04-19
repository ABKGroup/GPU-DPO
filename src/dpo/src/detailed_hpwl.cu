#include <cuda.h>
#include <cuda_runtime.h>
#include <thrust/device_ptr.h>
#include <thrust/reduce.h>

#include "detailed_db_cuda.cuh"

namespace dpo {

__global__ void compute_total_hpwl_kernel(DetailedPlaceData db, const float* xx, const float* yy, double* net_hpwls) {
    for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < db.num_nets; i += blockDim.x * gridDim.x) {
        net_hpwls[i] = db.compute_net_hpwl(i, xx, yy);
    }
}

float compute_total_hpwl(const DetailedPlaceData& db, const float* xx, const float* yy, double* net_hpwls) {
    compute_total_hpwl_kernel<<<ceilDiv(db.num_nets, 512), 512>>>(db, xx, yy, net_hpwls);
    // auto hpwl = thrust::reduce(thrust::device, net_hpwls, net_hpwls+db.num_nets);

    double* d_out = NULL;
    // Determine temporary device storage requirements
    void* d_temp_storage = NULL;
    size_t temp_storage_bytes = 0;
    cub::DeviceReduce::Sum(d_temp_storage, temp_storage_bytes, net_hpwls, d_out, db.num_nets);
    // Allocate temporary storage
    checkCuda(cudaMalloc(&d_temp_storage, temp_storage_bytes));
    checkCuda(cudaMalloc(&d_out, sizeof(double)));
    // Run sum-reduction
    cub::DeviceReduce::Sum(d_temp_storage, temp_storage_bytes, net_hpwls, d_out, db.num_nets);
    // copy d_out to hpwl
    double hpwl = 0;
    checkCuda(cudaMemcpy(&hpwl, d_out, sizeof(double), cudaMemcpyDeviceToHost));
    cudaFree(d_temp_storage);
    cudaFree(d_out);

    return float(hpwl);
}

} // namespace dpo