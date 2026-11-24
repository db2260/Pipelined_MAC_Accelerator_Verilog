# vivado -mode batch -source syn/run_vivado.tcl
set part xc7a35tcpg236-1
foreach top {mac_pipe mac_base} {
  read_verilog rtl/mac_pipe.v rtl/mac_base.v
  read_xdc syn/mac.xdc
  synth_design -top $top -part $part -mode out_of_context
  report_utilization    -file syn/${top}_util.rpt
  report_timing_summary -file syn/${top}_timing.rpt
  close_design
}
