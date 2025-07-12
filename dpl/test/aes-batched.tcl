# aes (low utilization)
set improve_placement_cmd "improve_placement"
puts "Running detailed placement with the following options:"
if {[info exists ::env(SEED)]} {
  set seed $::env(SEED)
  append improve_placement_cmd " -random_seed $seed"
  puts "Seed: $seed"
}
# displacement is usually set inside the tool
if {[info exists ::env(MAX_DISPLACEMENT)]} {
  set max_displacement $::env(MAX_DISPLACEMENT)
  append improve_placement_cmd " -max_displacement $max_displacement"
  puts "Max displacement: $max_displacement"
}
if {[info exists ::env(WINDOW_SIZE)]} {
  set window_size $::env(WINDOW_SIZE)
  append improve_placement_cmd " -window_size $window_size"
  puts "Local reordering window size: $window_size"
}
if {[info exists ::env(PROBLEM_SIZE)]} {
  set problem_size $::env(PROBLEM_SIZE)
  append improve_placement_cmd " -problem_size $problem_size"
  puts "Maximum independent set matching problem size: $problem_size"
}
if {[info exists ::env(NUM_ITERATIONS)]} {
  set num_iterations $::env(NUM_ITERATIONS)
  append improve_placement_cmd " -num_iterations $num_iterations"
  puts "Maximum number of iterations: $num_iterations"
} 
if {[info exists ::env(KICK_MOVE)]} {
  set kick_move $::env(KICK_MOVE)
  append improve_placement_cmd " -kick_move $kick_move"
  puts "Kick move size: $kick_move percent"
}
if {[info exists ::env(RUN_GS)]} {
  set run_gs $::env(RUN_GS)
  append improve_placement_cmd " -run_gs $run_gs"
  puts "Global swap flag: $run_gs"
} 
if {[info exists ::env(RUN_REORDER)]} {
  set run_reorder $::env(RUN_REORDER)
  append improve_placement_cmd " -run_reorder $run_reorder"
  puts "Local reordering flag: $run_reorder"
}
if {[info exists ::env(RUN_MIS)]} {
  set run_mis $::env(RUN_MIS) 
  append improve_placement_cmd " -run_mis $run_mis"
  puts "Maximum independent set matching flag: $run_mis"
}
if {[info exists ::env(TOLERANCE)]} {
  set tolerance $::env(TOLERANCE)
  append improve_placement_cmd " -tolerance $tolerance"
  puts "Iteration improvement tolerance: $tolerance"
}
puts "Design: aes"
puts "Technology: Nangate45"
puts "Multi-height cells: no"
cd ~/GPU-DPO/src/dpl/test
source "helpers.tcl"
read_lef Nangate45/Nangate45.lef
read_def aes-opt.def
eval $improve_placement_cmd 
check_placement