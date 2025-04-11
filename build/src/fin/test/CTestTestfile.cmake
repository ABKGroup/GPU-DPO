# CMake generated Testfile for 
# Source directory: /home/jsliang/GPU-DPO/src/fin/test
# Build directory: /home/jsliang/GPU-DPO/build/src/fin/test
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(fin.gcd_fill.tcl "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(fin.gcd_fill.tcl PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=gcd_fill;TEST_EXT=tcl;TEST_TYPE=tcl;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest tcl fin log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/fin/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;83;or_integration_test_single;/home/jsliang/GPU-DPO/src/fin/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/fin/test/CMakeLists.txt;0;")
add_test(fin.gcd_fill.py "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(fin.gcd_fill.py PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=gcd_fill;TEST_EXT=py;TEST_TYPE=python;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest python fin log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/fin/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;85;or_integration_test_single;/home/jsliang/GPU-DPO/src/fin/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/fin/test/CMakeLists.txt;0;")
