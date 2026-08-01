set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_file [file join $project_root vivado_project fpga_param_storage.xpr]

open_project $project_file
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation/bitstream failed: [get_property STATUS [get_runs impl_1]]"
}

puts "BITSTREAM: [get_property DIRECTORY [get_runs impl_1]]/fpga_param_storage_top.bit"
close_project
