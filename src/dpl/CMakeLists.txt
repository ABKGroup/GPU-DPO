# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2018-2025, The OpenROAD Authors

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
find_package(TCL)
find_package(Boost)
find_package(LEMON NAMES LEMON lemon REQUIRED)
swig_lib(NAME         dpl
         NAMESPACE    dpl
         I_FILE       src/Opendp.i
         SCRIPTS      src/Opendp.tcl
)

add_library(dpl_lib
  src/Opendp.cpp
  src/dbToOpendp.cpp
  src/infrastructure/Grid.cpp
  src/CheckPlacement.cpp
  src/infrastructure/Objects.cpp
  src/infrastructure/Padding.cpp
  src/Place.cpp
  src/FillerPlacement.cpp
  src/DecapPlacement.cpp
  src/OptMirror.cpp
  src/PlacementDRC.cpp

  src/Optdp.cpp
  src/infrastructure/architecture.cxx
  src/util/color.cxx
  src/infrastructure/network.cxx
  src/infrastructure/FlattenedData.cxx
  src/util/utility.cxx
  src/legalize_shift.cxx
  src/optimization/detailed.cxx
  src/optimization/detailed_manager.cxx
  src/optimization/detailed_mis.cu
  src/optimization/detailed_reorder.cu
  src/optimization/detailed_global.cu
  src/optimization/detailed_vertical.cxx
  src/objective/detailed_displacement.cxx
  src/objective/detailed_hpwl.cxx
  src/objective/detailed_hpwl.cu
  src/objective/detailed_abu.cxx
  src/optimization/detailed_random.cxx
  src/optimization/detailed_orient.cxx
  src/util/journal.cxx
)

target_link_libraries(dpl_lib
  PUBLIC
    odb
  PRIVATE
    utl_lib
)

target_include_directories(dpl_lib
  PUBLIC
    include
    ${LEMON_INCLUDE_DIRS}
  PRIVATE
    src
)

target_sources(dpl
  PRIVATE
    src/MakeOpendp.cpp
    src/graphics/Graphics.cpp
    src/graphics/DplObserver.h

)

target_include_directories(dpl
  PUBLIC
    include
  PRIVATE
    src
)

target_link_libraries(dpl
  PRIVATE
    ${TCL_LIBRARY}
    dpl_lib
    gui
    OpenMP::OpenMP_CXX
)

messages(
  TARGET dpl
)

set_property(TARGET dpl 
             PROPERTY CUDA_SEPARABLE_COMPILATION ON)      
set_target_properties(dpl PROPERTIES CUDA_RESOLVE_DEVICE_SYMBOLS ON)
set_target_properties(dpl PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
set_target_properties(dpl PROPERTIES POSITION_INDEPENDENT_CODE ON)

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
  target_link_libraries(dpl
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

add_custom_target(opendp_tags etags -o TAGS
  ${OPENDP_SRC}
  ${OPENDP_HOME}/include/dpl/*.h
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

if (Python3_FOUND AND BUILD_PYTHON)
  swig_lib(NAME          dpl_py
           NAMESPACE     dpl
           LANGUAGE      python
           I_FILE        src/Opendp-py.i
           SWIG_INCLUDES ${PROJECT_SOURCE_DIR}/include/dpl
                         ${ODB_HOME}/src/swig/common
                         ${ODB_HOME}/src/swig/python
           SCRIPTS       ${CMAKE_CURRENT_BINARY_DIR}/dpl_py.py
  )

  target_link_libraries(dpl_py
    PUBLIC
      ${Boost_LIBRARIES}
      dpl_lib
      gui
      odb
  )

endif()

if(ENABLE_TESTS)
  add_subdirectory(test)
endif()
