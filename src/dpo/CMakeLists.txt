###########################################################################
## BSD 3-Clause License
##
## Copyright (c) 2021, Andrew Kennings
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of source code must retain the above copyright notice, this
##   list of conditions and the following disclaimer.
##
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
##
## * Neither the name of the copyright holder nor the names of its
##   contributors may be used to endorse or promote products derived from
##   this software without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
###########################################################################

include("openroad")
set(CMAKE_CUDA_STANDARD_REQUIRED TRUE)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --extended-lambda --expt-relaxed-constexpr -Wno-redundant-decls")
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler=-Wno-redundant-decls")
find_package(OpenMP REQUIRED)
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -Xcompiler=${OpenMP_CXX_FLAGS}")
set(THREADS_PREFER_PTHREAD_FLAG ON)
set(CUDA_NVCC_FLAGS "${CUDA_NVCC_FLAGS}" --expt-relaxed-constexpr)
find_package(Eigen3 REQUIRED)
set(CMAKE_C_COMPILER "g++")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -ggdb -O3 -DIL_STD -ldl")
set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS} -g -ggdb -O3 -DIL_STD -ldl") 
set(CMAKE_THREAD_LIBS_INIT "-lpthread")
set(CMAKE_HAVE_THREADS_LIBRARY 1)
set(CMAKE_USE_PTHREADS_INIT 1)
set(CMAKE_CUDA_SEPARABLE_COMPILATION ON)

swig_lib(NAME         dpo
         NAMESPACE    dpo
         I_FILE       src/Optdp.i
         SCRIPTS      src/Optdp.tcl
)

# https://github.com/The-OpenROAD-Project/OpenROAD/issues/1186
find_package(LEMON NAMES LEMON lemon REQUIRED)

# find_package(Torch REQUIRED)

target_sources(dpo
  PRIVATE
    src/Optdp.cpp
    src/MakeOptdp.cpp
    src/architecture.cxx
    src/color.cxx
    src/network.cxx
    src/router.cxx
    src/utility.cxx
    src/legalize_shift.cxx
    src/detailed.cxx
    src/detailed_manager.cxx
    src/detailed_mis.cxx
    src/detailed_reorder.cxx
    src/detailed_vertical.cxx
    src/detailed_displacement.cxx
    src/detailed_hpwl.cxx
    src/detailed_abu.cxx
    src/detailed_random.cxx
    src/detailed_orient.cxx
    src/detailed_global.cu
    src/detailed_db.cxx
    src/detailed_hpwl.cu
)

target_include_directories(dpo
  PUBLIC
    include
    ${LEMON_INCLUDE_DIRS}
)

target_link_libraries(dpo
  PRIVATE
    odb
    OpenSTA
    utl_lib
    dpl_lib
    OpenMP::OpenMP_CXX
    "${TORCH_LIBRARIES}"
)

messages(
  TARGET dpo
)

set_property(TARGET dpo 
             PROPERTY CUDA_SEPARABLE_COMPILATION ON)      
set_target_properties(dpo PROPERTIES CUDA_RESOLVE_DEVICE_SYMBOLS ON)
set_target_properties(dpo PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
set_target_properties(dpo PROPERTIES POSITION_INDEPENDENT_CODE ON)


# Set CUDA host compiler and link executable
set(CMAKE_CUDA_HOST_COMPILER /home/tool/gcc/gcc-10.3.0/bin/g++) # replace with your host compiler
set(CMAKE_CUDA_LINK_EXECUTABLE "<CMAKE_CUDA_COMPILER> <FLAGS> <CMAKE_CUDA_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>")

if (NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
  set(CMAKE_CUDA_ARCHITECTURES 80 86 CACHE STRING "CUDA architectures" FORCE)
endif()
message(STATUS "CMAKE_CUDA_ARCHITECTURES: ${CMAKE_CUDA_ARCHITECTURES}")

message(STATUS "GPU is enabled")
# find_package(CUDA) should be replaced by "FindCUDAToolkit" for CMAKE verison >= 3.17. 
# See https://cmake.org/cmake/help/latest/module/FindCUDAToolkit.html. 
# find_package(CUDA) or FindCUDA is deprecated since vision 3.10.
find_package(CUDAToolkit)
if (CUDAToolkit_FOUND)
  message(STATUS "CUDA is found")
  enable_language(CUDA)
  target_link_libraries(dpo
    PRIVATE
      CUDA::cudart
      CUDA::cublas
      CUDA::cusparse
      CUDA::cusolver
      CUDA::cufft
      CUDA::curand
  )  
else()
  message(STATUS "CUDA is not found")
endif()
################################################################


add_custom_target(optdp_tags etags -o TAGS
  ${OPTDP_SRC}
  ${OPTDP_HOME}/include/dpo/*.h
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

if (Python3_FOUND AND BUILD_PYTHON)
  swig_lib(NAME          dpo_py
           NAMESPACE     dpo
           LANGUAGE      python
           I_FILE        src/Optdp-py.i
           SWIG_INCLUDES ${PROJECT_SOURCE_DIR}/include/dpo
                         ${ODB_HOME}/src/swig/common
                         ${ODB_HOME}/src/swig/python
           SCRIPTS       ${CMAKE_CURRENT_BINARY_DIR}/dpo_py.py
  )

  target_include_directories(dpo_py
    PUBLIC
      include
      include/dpo
  )

  target_link_libraries(dpo_py
    PUBLIC
      dpo
      odb
  )

endif()

add_subdirectory(test)
