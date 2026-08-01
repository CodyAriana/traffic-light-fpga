set project_root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $project_root vivado_project fpga_param_storage.xpr]
foreach run_name {synth_1 impl_1} {
    set run_obj [get_runs $run_name]
    puts "$run_name STATUS=[get_property STATUS $run_obj] PROGRESS=[get_property PROGRESS $run_obj]"
}
close_project
