# Run the Vivado *project* flow end to end (synth_1 -> impl_1 -> bitstream),
# the same runs the GUI launches; results appear in the GUI's Design Runs.
#   cd fpga && vivado -mode batch -source create_project.tcl   (once)
#   cd fpga && vivado -mode batch -source run_project.tcl
# Reports land in fpga/vivado/Small_SoC.runs/{synth_1,impl_1}/.
set root [file normalize [file dirname [info script]]/..]
open_project $root/fpga/vivado/Small_SoC.xpr
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
puts "SYNTH: [get_property STATUS [get_runs synth_1]]"
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"
open_run impl_1
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "PROJECT BUILD DONE: WNS=$wns"
close_project
