# 创建交通灯 Vivado 工程
set root [file normalize [file dirname [info script]]]
set project_dir [file join $root vivado_project]
set rtl_file [file join $root traffic_light.v]
set tb_file [file join $root tb_traffic_light.v]
set xdc_file [file join $root traffic_light.xdc]

create_project traffic_light $project_dir -part xc7a35tfgg484-2 -force

add_files -fileset sources_1 -norecurse $rtl_file
add_files -fileset sim_1 -norecurse $tb_file
add_files -fileset constrs_1 -norecurse $xdc_file

set_property top traffic_light_top [get_filesets sources_1]
set_property top tb_traffic_light [get_filesets sim_1]
set_property file_type {Verilog} [get_files $rtl_file]
set_property file_type {Verilog} [get_files $tb_file]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project

