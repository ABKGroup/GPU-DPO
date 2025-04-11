# CMake generated Testfile for 
# Source directory: /home/jsliang/GPU-DPO/src/par/test
# Build directory: /home/jsliang/GPU-DPO/build/src/par/test
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(par.partition_gcd.tcl "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(par.partition_gcd.tcl PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=partition_gcd;TEST_EXT=tcl;TEST_TYPE=tcl;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest tcl par log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/par/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;83;or_integration_test_single;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;0;")
add_test(par.partition_gcd.py "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(par.partition_gcd.py PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=partition_gcd;TEST_EXT=py;TEST_TYPE=python;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest python par log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/par/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;85;or_integration_test_single;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;0;")
add_test(par.read_part.tcl "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(par.read_part.tcl PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=read_part;TEST_EXT=tcl;TEST_TYPE=tcl;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest tcl par log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/par/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;83;or_integration_test_single;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/par/test/CMakeLists.txt;0;")
