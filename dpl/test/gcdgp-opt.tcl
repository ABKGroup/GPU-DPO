# gcd (low utilization)
source "helpers.tcl"
read_lef Nangate45/Nangate45.lef
read_def gcd.gp.def
improve_placement
check_placement
