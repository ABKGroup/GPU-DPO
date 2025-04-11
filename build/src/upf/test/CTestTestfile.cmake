# CMake generated Testfile for 
# Source directory: /home/jsliang/GPU-DPO/src/upf/test
# Build directory: /home/jsliang/GPU-DPO/build/src/upf/test
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(upf.levelshifter.tcl "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(upf.levelshifter.tcl PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=levelshifter;TEST_EXT=tcl;TEST_TYPE=tcl;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest tcl upf log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/upf/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;83;or_integration_test_single;/home/jsliang/GPU-DPO/src/upf/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/upf/test/CMakeLists.txt;0;")
add_test(upf.write.tcl "/usr/bin/bash" "/home/jsliang/GPU-DPO/test/regression_test.sh")
set_tests_properties(upf.write.tcl PROPERTIES  ENVIRONMENT "OPENROAD_EXE=/home/jsliang/GPU-DPO/build/src/openroad;TEST_NAME=write;TEST_EXT=tcl;TEST_TYPE=tcl;TEST_CHECK_LOG=True;TEST_CHECK_PASSFAIL=False" LABELS "IntegrationTest tcl upf log_compare" WORKING_DIRECTORY "/home/jsliang/GPU-DPO/src/upf/test" _BACKTRACE_TRIPLES "/home/jsliang/GPU-DPO/src/cmake/testing.cmake;16;add_test;/home/jsliang/GPU-DPO/src/cmake/testing.cmake;83;or_integration_test_single;/home/jsliang/GPU-DPO/src/upf/test/CMakeLists.txt;1;or_integration_tests;/home/jsliang/GPU-DPO/src/upf/test/CMakeLists.txt;0;")
