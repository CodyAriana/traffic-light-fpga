`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Streaming CRC32 calculator
//
// 使用标准 CRC-32/ISO-HDLC 参数：
//   初始值：0xFFFFFFFF
//   多项式：0x04C11DB7 的反射形式 0xEDB88320
//   输入和输出均按反射方式处理
//   最终结果：内部 CRC 与 0xFFFFFFFF 异或
//
// 使用方法：
//   1. start 拉高一个时钟，开始一帧新的计算；
//   2. 每当 data_valid=1，在一个时钟内输入一个字节；
//   3. 所有字节输入完成后，finish 拉高一个时钟；
//   4. done 拉高一个时钟，crc 输出最终 CRC32。
// -----------------------------------------------------------------------------
module crc32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        data_valid,
    input  wire [7:0]  data_byte,
    input  wire        finish,
    output reg         busy,
    output reg         done,
    output reg  [31:0] crc
);

    reg [31:0] crc_reg;

    // 处理一个输入字节。Verilog 的 for 循环在综合后会展开为固定硬件。
    function [31:0] crc32_next_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        integer      bit_index;
        reg [31:0]   crc_work;
        begin
            crc_work = crc_in ^ {24'd0, data_in};

            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (crc_work[0]) begin
                    crc_work = (crc_work >> 1) ^ 32'hEDB88320;
                end
                else begin
                    crc_work = crc_work >> 1;
                end
            end

            crc32_next_byte = crc_work;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFFFFFF;
            crc     <= 32'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
        end
        else begin
            // done 是单周期脉冲，默认每个时钟清零。
            done <= 1'b0;

            if (start) begin
                // 新帧开始，重新装入 CRC 初始值。
                crc_reg <= 32'hFFFFFFFF;
                crc     <= 32'd0;
                busy    <= 1'b1;
            end
            else if (busy) begin
                if (data_valid) begin
                    crc_reg <= crc32_next_byte(crc_reg, data_byte);
                end

                if (finish) begin
                    // 本模块约定 finish 在最后一个 data_valid 之后到来。
                    crc  <= crc_reg ^ 32'hFFFFFFFF;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
