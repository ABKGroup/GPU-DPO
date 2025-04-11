add_test([=[HTreeBuilderTest.Instantiates]=]  /home/jsliang/GPU-DPO/build/src/cts/test/cts_unittest [==[--gtest_filter=HTreeBuilderTest.Instantiates]==] --gtest_also_run_disabled_tests)
set_tests_properties([=[HTreeBuilderTest.Instantiates]=]  PROPERTIES WORKING_DIRECTORY /home/jsliang/GPU-DPO/src/cts/test SKIP_REGULAR_EXPRESSION [==[\[  SKIPPED \]]==])
set(  cts_unittest_TESTS HTreeBuilderTest.Instantiates)
