set root_dir [file normalize [file dirname [info script]]]
set project_name uart_command_ack_project
set project_dir [file join $root_dir $project_name]

create_project $project_name $project_dir -part xc7a35tfgg484-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

add_files -norecurse [list \
    [file join $root_dir uart_tx.v] \
    [file join $root_dir uart_rx.v] \
    [file join $root_dir uart_cmd_decoder_ack.v] \
    [file join $root_dir uart_response_tx.v] \
    [file join $root_dir uart_command_ack_top.v] \
]

add_files -fileset constrs_1 -norecurse \
    [file join $root_dir uart_command_ack_top.xdc]

add_files -fileset sim_1 -norecurse \
    [file join $root_dir tb_uart_command_ack_top.v]

set_property top uart_command_ack_top [get_filesets sources_1]
set_property top tb_uart_command_ack_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 10
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 10
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation or bitstream generation failed"
}

open_run impl_1
report_timing_summary -file [file join $project_dir uart_command_ack_timing_summary.rpt]
report_utilization -file [file join $project_dir uart_command_ack_utilization.rpt]

puts "UART_COMMAND_ACK_BUILD_PASS"
puts "BITSTREAM: [file join $project_dir ${project_name}.runs impl_1 uart_command_ack_top.bit]"
