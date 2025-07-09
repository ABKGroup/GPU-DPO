set improve_placement_cmd "improve_placement"
# append improve_placement_cmd " -kick_move 0"
# append improve_placement_cmd " -run_mis 0"
# append improve_placement_cmd " -run_reorder 0"
cd /home/jsliang/GPU-DPO/src/dpl/test
source "helpers.tcl"
source /home/jsliang/asap7_read_lef.tcl 
read_def /home/memzfs_projects/artnet/sakundu/test/ref_invs/mh_asap7/mempool_group_asap7_mh.def
# needs to be legalized first
detailed_placement  
check_placement
# eval $improve_placement_cmd 
# check_placement
