set improve_placement_cmd "improve_placement"
# append improve_placement_cmd " -kick_move 0"
# append improve_placement_cmd " -run_mis 0"
# append improve_placement_cmd " -run_reorder 0"
source "helpers.tcl"
source ~/asap7_read_lef.tcl
read_def ~/aes_multi_height.def  
# needs to be legalized first
detailed_placement  
check_placement
# eval $improve_placement_cmd 
# check_placement