set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $project_root vivado_project]

create_project -force fpga_param_storage $project_dir -part xc7a35tfgg484-2

set rtl_files [glob -nocomplain -directory [file join $project_root rtl] *.v]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $project_root constr fpga_param_storage.xdc]

set sim_files [glob -nocomplain -directory [file join $project_root sim] *.v]
add_files -fileset sim_1 -norecurse $sim_files

set_property top fpga_param_storage_top [get_filesets sources_1]
set_property top tb_fpga_param_storage_top [get_filesets sim_1]
set_property -name xsim.simulate.runtime -value all -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $project_dir"
puts "Synthesis top: fpga_param_storage_top"
puts "Simulation top: tb_fpga_param_storage_top"
