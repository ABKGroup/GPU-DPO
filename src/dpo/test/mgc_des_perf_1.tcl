source "helpers.tcl"
read_lef mgc_des_perf_1/tech.lef
read_lef mgc_des_perf_1/cells.lef
read_def mgc_des_perf_1/after_legalized.ntup.fix.def
improve_placement
check_placement
