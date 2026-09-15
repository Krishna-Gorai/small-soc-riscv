# Non-project Vivado flow: RTL -> bitstream for the ZCU104.
#   vivado -mode batch -source build.tcl          (from the fpga/ directory)
# Outputs land in fpga/build/: zcu104_top.bit, utilisation/timing/power reports.
set root  [file normalize [file dirname [info script]]/..]
set rtl   $root/rtl
set out   $root/fpga/build
file mkdir $out

read_verilog [glob $rtl/*.v]
read_verilog $root/fpga/zcu104_top.v
read_xdc     $root/fpga/zcu104.xdc

# program image: $readmemh("program.hex") resolves relative to the RTL directory
set_property verilog_dir $rtl [current_fileset]

synth_design -top zcu104_top -part xczu7ev-ffvc1156-2-e
opt_design
place_design
phys_opt_design
route_design

report_utilization      -file $out/utilization.rpt -hierarchical -hierarchical_depth 2
report_timing_summary   -file $out/timing.rpt
report_power            -file $out/power.rpt
report_drc              -file $out/drc.rpt
write_checkpoint -force $out/zcu104_top_routed.dcp
write_bitstream  -force $out/zcu104_top.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "BUILD DONE: WNS = $wns ns"
