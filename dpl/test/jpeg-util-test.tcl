set improve_placement_cmd "improve_placement"
cd /home//GPU-DPO/src/dpl/test
source "helpers.tcl"
source /home//asap7_read_lef.tcl
read_def /home//jpeg_util_test/jpeg_90.def
detailed_placement  
check_placement
improve_placement
improve_placement
improve_placement
improve_placement
improve_placement