# Regenerate the Vivado GUI project from the checked-in sources.
#   vivado -mode batch -source create_project.tcl        (from fpga/)
# Creates fpga/vivado/Small_SoC.xpr (git-ignored). Top = zcu104_top for
# synthesis/implementation, tb_soc_top for behavioural simulation.
set root [file normalize [file dirname [info script]]/..]
set prj  $root/fpga/vivado

create_project -force Small_SoC $prj -part xczu7ev-ffvc1156-2-e
set_property board_part xilinx.com:zcu104:part0:1.1 [current_project] 

add_files -fileset sources_1 [glob $root/rtl/*.v]
add_files -fileset sources_1 $root/fpga/zcu104_top.v
add_files -fileset sources_1 $root/rtl/program.hex
add_files -fileset constrs_1 $root/fpga/zcu104.xdc
add_files -fileset sim_1     [list $root/tests/tb/tb_soc_top.v $root/tests/tb/tb_jtag.v]
add_files -fileset sim_1     $root/rtl/program.hex

set_property top zcu104_top [get_filesets sources_1]
set_property top tb_soc_top [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {1000us} -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project written to $prj/Small_SoC.xpr"
