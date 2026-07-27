# 实现工程并生成 Bitstream、MCS 和 PRM
set root [file normalize [file dirname [info script]]]
set project_file [file join $root vivado_project traffic_light.xpr]
set bit_file [file join $root traffic_light.bit]
set mcs_file [file join $root traffic_light.mcs]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file. Run create_vivado_project.tcl first."
}

open_project $project_file
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
if {$impl_status ne "write_bitstream Complete!"} {
    error "Implementation/bitstream did not complete successfully: $impl_status"
}

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set generated_bit [file join $run_dir traffic_light_top.bit]
if {![file exists $generated_bit]} {
    error "Generated Bitstream not found: $generated_bit"
}
file copy -force $generated_bit $bit_file

write_cfgmem -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x0 $bit_file" -file $mcs_file -force

close_project

