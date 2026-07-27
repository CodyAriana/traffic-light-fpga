# 启动交通灯行为级仿真
set root [file normalize [file dirname [info script]]]
set project_file [file join $root vivado_project traffic_light.xpr]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file. Run create_vivado_project.tcl first."
}

open_project $project_file
## 批处理模式会启动 XSim，并运行到 Testbench 的 $finish。
## 这等价于交互模式中的“Run All”；不要在 XSim 已结束后再次调用 run all，
## 否则 Vivado 2022.2 可能在批处理模式下等待一个已经关闭的仿真会话。
launch_simulation -mode behavioral -type batch
puts "SIMULATION_STATUS=behavioral batch completed"
close_project
