set improve_placement_cmd "improve_placement"
cd /home//GPU-DPO/src/dpl/test
source "helpers.tcl"
source ~/asap7_read_lef.tcl
read_def ~/aes_80.def
detailed_placement  
check_placement
improve_placement
improve_placement
improve_placement
improve_placement
improve_placement