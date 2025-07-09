# ibex (low utilization)
source "helpers.tcl"
read_lef Nangate45/Nangate45.lef
read_def ibex-opt.gp.def
improve_placement
check_placement
