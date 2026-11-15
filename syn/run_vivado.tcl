# run_vivado.tcl — synthesise, place and route, then write every report we need.
#
# How to run (Windows): open "Vivado Tcl Shell" from the Start menu, then
#     cd <repository>/syn
#     source run_vivado.tcl
# Takes a few minutes. (spec v2: no FIFO) Results:  syn/reports/summary.txt  (+ full reports in syn/reports/)
#
# Three runs:
#   1. alu_wrap FLAT=0 : shared-adder ALU alone, flip-flops on both sides  -> ALU LUTs, ALU delay
#   2. alu_wrap FLAT=1 : flat ALU (one adder per op), same wrapper          -> for the % comparison
#   3. alu_uart_top    : the whole design on the Nexys 4 pins                -> LUT / FF / Fmax

set part   xc7a100tcsg324-1
set period 10.0
cd [file dirname [file normalize [info script]]]
file mkdir reports
set fh [open reports/summary.txt w]

# Repository layout: design files live in ../rtl, the comparison-only files live here in syn/.
set srcs {../rtl/alu.v alu_flat.v alu_wrap.v ../rtl/fsm.v ../rtl/baud_gen.v ../rtl/sync2.v ../rtl/uart_rx.v ../rtl/uart_tx.v ../rtl/alu_uart_top.v}

# Make sure the sources are loaded before each synth run (harmless if they already are).
proc load_sources {srcs} {
    if {[llength [get_files -quiet */alu.v]] == 0} { read_verilog $srcs }
}

# Pull one number out of the utilization report, e.g. "Slice LUTs" -> 52
proc util_num {rpt name} {
    if {[regexp "\\|\\s*${name}\\*?\\s*\\|\\s*(\\d+)" $rpt -> n]} { return $n }
    return "?"
}

proc write_summary {fh tag period} {
    set rpt  [report_utilization -return_string]
    set path [get_timing_paths -delay_type max -max_paths 1]
    set wns  [get_property SLACK $path]
    set dly  [get_property DATAPATH_DELAY $path]
    set fmax [expr {1000.0 / ($period - $wns)}]
    set line [format "%-26s LUTs %5s  (as logic %5s, as memory %3s)  FFs %5s  CARRY4 %3s | WNS %6.3f ns  worst path %6.3f ns  Fmax %6.1f MHz" \
        $tag [util_num $rpt "Slice LUTs"] [util_num $rpt "LUT as Logic"] [util_num $rpt "LUT as Memory"] \
        [util_num $rpt "Slice Registers"] [util_num $rpt "CARRY4"] $wns $dly $fmax]
    puts $line
    puts $fh $line
}

# ---------- runs 1 and 2: the ALU on its own (out of context = no I/O pins) ----------
foreach flat {0 1} {
    load_sources $srcs
    set tag [expr {$flat ? "alu_flat" : "alu_shared"}]
    synth_design -top alu_wrap -part $part -mode out_of_context -generic FLAT=$flat
    create_clock -name clk -period $period [get_ports clk]
    opt_design
    place_design
    route_design
    report_utilization                         -file reports/${tag}_utilization.rpt
    report_timing_summary                      -file reports/${tag}_timing_summary.rpt
    report_timing -max_paths 5 -delay_type max -file reports/${tag}_timing_paths.rpt
    write_summary $fh $tag $period
    close_design
}

# ---------- run 3: the full design (ALU + UART, no FIFO) ----------
load_sources $srcs
read_xdc alu_uart_top.xdc
synth_design -top alu_uart_top -part $part
opt_design
place_design
route_design
report_utilization                           -file reports/top_utilization.rpt
report_utilization -hierarchical             -file reports/top_utilization_hier.rpt
report_timing_summary                        -file reports/top_timing_summary.rpt
report_timing -max_paths 10 -delay_type max  -file reports/top_timing_paths.rpt
report_drc                                   -file reports/top_drc.rpt
write_summary $fh "alu_uart_top (full design)" $period

puts $fh ""
puts $fh "Fmax = 1 / (T - WNS), T = $period ns. Authoritative numbers are in the .rpt files."
close $fh
puts "\nDone. Open reports/summary.txt"
