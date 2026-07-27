# 重新综合并执行 Vivado 批处理行为仿真
set root [file normalize [file dirname [info script]]]
set project_file [file join $root vivado_project traffic_light.xpr]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file. Run create_vivado_project.tcl first."
}

open_project $project_file
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
    error "Synthesis did not complete successfully: $synth_status"
}

## 批处理 XSim 会自动运行到 Testbench 的 $finish。
launch_simulation -mode behavioral -type batch
puts "SIMULATION_STATUS=behavioral batch completed"
close_project
