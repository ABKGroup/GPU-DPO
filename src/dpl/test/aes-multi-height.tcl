# ibex (low utilization)
source "helpers.tcl"
source /home/jsliang/asap7_read_lef.tcl
read_def /home/jsliang/aes_multi_height.def  
detailed_placement
check_placement
improve_placement
check_placement
