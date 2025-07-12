set improve_placement_cmd "improve_placement"
# append improve_placement_cmd " -kick_move 0"
# append improve_placement_cmd " -run_mis 0"
# append improve_placement_cmd " -run_reorder 0"
cd /home/GPU-DPO/src/dpl/test
source "helpers.tcl"
source /home/asap7_read_lef.tcl
read_def "xxx"
# needs to be legalized first
detailed_placement  
check_placement
# eval $improve_placement_cmd 
# check_placement