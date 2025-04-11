add_test([=[BufRemTest.SlackImproves]=]  /home/jsliang/GPU-DPO/build/src/rsz/test/cpp/TestBufRem1 [==[--gtest_filter=BufRemTest.SlackImproves]==] --gtest_also_run_disabled_tests)
set_tests_properties([=[BufRemTest.SlackImproves]=]  PROPERTIES WORKING_DIRECTORY /home/jsliang/GPU-DPO/src/rsz/test/cpp/.. SKIP_REGULAR_EXPRESSION [==[\[  SKIPPED \]]==])
set(  TestBufRem1_TESTS BufRemTest.SlackImproves)
