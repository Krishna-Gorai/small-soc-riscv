# Host-side driver for the Small_SoC JTAG debug port, for the Vivado hardware
# manager (the ZCU104's USB-JTAG, via BSCANE2 USER1 in zcu104_top).
#
#   vivado -mode tcl -source jtag_host.tcl
#   > jtag_open
#   > dbg_halt            ;# stop the core at an instruction boundary
#   > dbg_load ../sw/hello/hello.hex
#   > dbg_reset           ;# core reset, stays halted
#   > dbg_run             ;# release halt
#   > dbg_peek 0x10000004 ;# read the switches
#   > dbg_poke 0x10000000 0xF
#
# Register protocol: see rtl/jtag_dbg.v (66-bit DR: {addr[32], data[32], op[2]}).
# IR values from the xczu7ev BSDL (data/parts/xilinx/zynquplus/public/bsdl):
# 12-bit IR, USER1 = 0x902. Adjust for another device.
set IR_LEN 12
set USER1  0x902

proc jtag_open {} {
    open_hw_manager
    connect_hw_server
    open_hw_target
    # raw JTAG access to the first (only) FPGA in the chain
    set ::hw_jtag [current_hw_target]
    close_hw_target
    open_hw_target -jtag_mode 1
    run_state_hw_jtag reset
    run_state_hw_jtag idle
    scan_ir_hw_jtag $::IR_LEN -tdi $::USER1
}

# one 66-bit DR scan; returns the 66-bit response as a hex string
proc dbg_scan {op addr data} {
    set v [expr {($addr << 34) | (($data & 0xFFFFFFFF) << 2) | $op}]
    return [scan_dr_hw_jtag 66 -tdi [format %x $v]]
}
proc dbg_wait {} {
    for {set i 0} {$i < 100} {incr i} {
        set r [expr 0x[dbg_scan 0 0 0]]
        if {!($r & 1)} { return $r }
    }
    error "debug request timed out"
}
proc dbg_peek {addr} {
    dbg_scan 1 $addr 0
    set r [dbg_wait]
    return [format 0x%08x [expr {($r >> 2) & 0xFFFFFFFF}]]
}
proc dbg_poke {addr data} { dbg_scan 2 $addr $data; dbg_wait; return }
proc dbg_ctrl {halt rst}  { dbg_scan 3 0 [expr {($rst << 1) | $halt}]; dbg_wait; return }
proc dbg_halt  {} { dbg_ctrl 1 0; dbg_status }
proc dbg_run   {} { dbg_ctrl 0 0; dbg_status }
proc dbg_reset {} { dbg_ctrl 1 1; dbg_ctrl 1 0; dbg_status }
proc dbg_status {} {
    set r [dbg_wait]
    puts [format "halted=%d halt_req=%d reset=%d" [expr {($r>>34)&1}] [expr {($r>>35)&1}] [expr {($r>>36)&1}]]
}
# load a $readmemh image (one 32-bit word per line) at address 0 and verify it
proc dbg_load {hexfile {base 0}} {
    set f [open $hexfile r]; set words [split [string trim [read $f]] "\n"]; close $f
    set a $base
    foreach w $words { dbg_poke $a 0x[string trim $w]; incr a 4 }
    set a $base; set bad 0
    foreach w $words {
        if {[expr [dbg_peek $a]] != [expr 0x[string trim $w]]} { incr bad }
        incr a 4
    }
    puts "loaded [llength $words] words, $bad mismatches"
}
