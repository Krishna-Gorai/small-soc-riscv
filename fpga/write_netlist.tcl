# Write the post-route functional netlist for gate-level simulation.
#   vivado -mode batch -source write_netlist.tcl        (from fpga/, after build.tcl)
set root [file normalize [file dirname [info script]]/..]
set out  $root/fpga/build
open_checkpoint $out/zcu104_top_routed.dcp
write_verilog -mode funcsim -force $out/zcu104_top_funcsim.v
puts "NETLIST DONE"
