`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 参数寄存器组
//
// 参数总线排列如下：
//   params[7:0]   = mode
//   params[23:8]  = green_time
//   params[39:24] = yellow_time
//   params[55:40] = red_time
//   params[87:56] = device_id
//
// default_en 的优先级最高，其次是 load_en，最后是 write_en。
// write_error 是一个单周期错误脉冲；非法输入不会覆盖当前参数。
// -----------------------------------------------------------------------------
module parameter_regs (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        write_en,
    input  wire [87:0] write_params,
    input  wire        load_en,
    input  wire [87:0] load_params,
    input  wire        default_en,
    output reg  [87:0] params,
    output reg         params_valid,
    output reg         write_error
);

    localparam [87:0] DEFAULT_PARAMS = {
        32'd1001, 16'd5, 16'd2, 16'd5, 8'd0
    };

    function params_are_valid;
        input [87:0] value;
        reg [7:0]  mode_value;
        reg [15:0] green_value;
        reg [15:0] yellow_value;
        reg [15:0] red_value;
        begin
            mode_value   = value[7:0];
            green_value  = value[23:8];
            yellow_value = value[39:24];
            red_value    = value[55:40];

            params_are_valid =
                (mode_value <= 8'd1) &&
                (green_value >= 16'd1) && (green_value <= 16'd600) &&
                (yellow_value >= 16'd1) && (yellow_value <= 16'd600) &&
                (red_value >= 16'd1) && (red_value <= 16'd600);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            params       <= DEFAULT_PARAMS;
            params_valid <= 1'b1;
            write_error  <= 1'b0;
        end
        else begin
            // 错误信号默认为 0，只在本周期发现非法参数时拉高。
            write_error <= 1'b0;

            if (default_en) begin
                params       <= DEFAULT_PARAMS;
                params_valid <= 1'b1;
            end
            else if (load_en) begin
                if (params_are_valid(load_params)) begin
                    params       <= load_params;
                    params_valid <= 1'b1;
                end
                else begin
                    write_error <= 1'b1;
                end
            end
            else if (write_en) begin
                if (params_are_valid(write_params)) begin
                    params       <= write_params;
                    params_valid <= 1'b1;
                end
                else begin
                    write_error <= 1'b1;
                end
            end
        end
    end

endmodule
