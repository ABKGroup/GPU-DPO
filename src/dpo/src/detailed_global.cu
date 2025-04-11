#include "detailed_dp_torch.cuh"

namespace dpo {

void globalSwapCUDA(DetailedPlaceDB& db, int num_bins_x=512, int num_bins_y=512, int K=4, int max_iters=100) {
  // printf("Num bins x = %d\n", num_bins_x);
  // printf("Num bins y = %d\n", num_bins_y);
  // printf("K = %d\n", K);
  // printf("Max iters = %d\n", max_iters);
  cudaSetDevice(db.node_size.x)
}
  
} // namespace dpo  