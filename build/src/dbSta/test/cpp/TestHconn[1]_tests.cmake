add_test([=[TestHconn.ConnectionMade]=]  /home/jsliang/GPU-DPO/build/src/dbSta/test/cpp/TestHconn [==[--gtest_filter=TestHconn.ConnectionMade]==] --gtest_also_run_disabled_tests)
set_tests_properties([=[TestHconn.ConnectionMade]=]  PROPERTIES WORKING_DIRECTORY /home/jsliang/GPU-DPO/src/dbSta/test/cpp/.. SKIP_REGULAR_EXPRESSION [==[\[  SKIPPED \]]==])
set(  TestHconn_TESTS TestHconn.ConnectionMade)
