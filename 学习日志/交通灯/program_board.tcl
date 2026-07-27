# 尝试通过本机 hw_server 将交通灯 Bitstream 下载到开发板
set root [file normalize [file dirname [info script]]]
set bit_file [file join $root traffic_light.bit]

if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}

open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets *]
if {[llength $targets] == 0} {
    error "No JTAG hardware target found on localhost:3121"
}

open_hw_target [lindex $targets 0]
set devices [get_hw_devices]
if {[llength $devices] == 0} {
    error "No FPGA device found on the open JTAG target"
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "PROGRAM_STATUS=download completed to [get_property PART $device]"

close_hw_target
disconnect_hw_server localhost:3121
close_hw_manager
