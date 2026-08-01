`timescale 1ns / 1ps

// UART 请求帧解析器。
// 帧格式：55 AA VERSION CMD LEN_L LEN_H SEQ PAYLOAD CRC32(小端序)
module command_parser (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         byte_valid,
    input  wire [7:0]   byte_data,
    output reg          frame_valid,
    output reg  [7:0]   command,
    output reg  [7:0]   seq_num,
    output reg  [15:0]  payload_length,
    output reg  [255:0] payload,
    output reg  [2:0]   frame_error
);

    localparam [3:0] WAIT_55   = 4'd0;
    localparam [3:0] WAIT_AA   = 4'd1;
    localparam [3:0] VERSION   = 4'd2;
    localparam [3:0] COMMAND   = 4'd3;
    localparam [3:0] LEN_L     = 4'd4;
    localparam [3:0] LEN_H     = 4'd5;
    localparam [3:0] SEQ       = 4'd6;
    localparam [3:0] PAYLOAD   = 4'd7;
    localparam [3:0] CRC_0     = 4'd8;
    localparam [3:0] CRC_1     = 4'd9;
    localparam [3:0] CRC_2     = 4'd10;
    localparam [3:0] CRC_3     = 4'd11;

    localparam [2:0] ERROR_CRC     = 3'b001;
    localparam [2:0] ERROR_FORMAT  = 3'b010;
    localparam [2:0] ERROR_VERSION = 3'b100;

    reg [3:0]  state;
    reg [7:0]  len_l_reg;
    reg [5:0]  payload_index;
    reg [31:0] crc_reg;
    reg [7:0]  crc_byte0;
    reg [7:0]  crc_byte1;
    reg [7:0]  crc_byte2;

    function [31:0] crc32_update_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        integer      i;
        reg [31:0]   c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0]) c = (c >> 1) ^ 32'hEDB88320;
                else     c = c >> 1;
            end
            crc32_update_byte = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= WAIT_55;
            len_l_reg      <= 8'd0;
            payload_index  <= 6'd0;
            crc_reg        <= 32'hFFFFFFFF;
            crc_byte0      <= 8'd0;
            crc_byte1      <= 8'd0;
            crc_byte2      <= 8'd0;
            frame_valid    <= 1'b0;
            command        <= 8'd0;
            seq_num        <= 8'd0;
            payload_length <= 16'd0;
            payload        <= 256'd0;
            frame_error    <= 3'd0;
        end
        else begin
            frame_valid <= 1'b0;
            frame_error <= 3'd0;

            if (byte_valid) begin
                case (state)
                    WAIT_55: begin
                        if (byte_data == 8'h55) state <= WAIT_AA;
                    end

                    WAIT_AA: begin
                        if (byte_data == 8'hAA) begin
                            state <= VERSION;
                        end
                        else if (byte_data == 8'h55) begin
                            state <= WAIT_AA;
                        end
                        else begin
                            state <= WAIT_55;
                        end
                    end

                    VERSION: begin
                        if (byte_data == 8'h01) begin
                            crc_reg <= crc32_update_byte(32'hFFFFFFFF, byte_data);
                            state   <= COMMAND;
                        end
                        else begin
                            frame_error <= ERROR_VERSION;
                            state       <= WAIT_55;
                        end
                    end

                    COMMAND: begin
                        command <= byte_data;
                        crc_reg <= crc32_update_byte(crc_reg, byte_data);
                        state   <= LEN_L;
                    end

                    LEN_L: begin
                        len_l_reg <= byte_data;
                        crc_reg   <= crc32_update_byte(crc_reg, byte_data);
                        state     <= LEN_H;
                    end

                    LEN_H: begin
                        crc_reg <= crc32_update_byte(crc_reg, byte_data);
                        if ({byte_data, len_l_reg} > 16'd32) begin
                            frame_error <= ERROR_FORMAT;
                            state       <= WAIT_55;
                        end
                        else begin
                            payload_length <= {byte_data, len_l_reg};
                            state          <= SEQ;
                        end
                    end

                    SEQ: begin
                        seq_num       <= byte_data;
                        crc_reg       <= crc32_update_byte(crc_reg, byte_data);
                        payload_index <= 6'd0;
                        payload       <= 256'd0;
                        if (payload_length == 16'd0) state <= CRC_0;
                        else                         state <= PAYLOAD;
                    end

                    PAYLOAD: begin
                        payload[payload_index * 8 +: 8] <= byte_data;
                        crc_reg <= crc32_update_byte(crc_reg, byte_data);
                        if (payload_index == payload_length - 1'b1) begin
                            state <= CRC_0;
                        end
                        else begin
                            payload_index <= payload_index + 1'b1;
                        end
                    end

                    CRC_0: begin
                        crc_byte0 <= byte_data;
                        state     <= CRC_1;
                    end

                    CRC_1: begin
                        crc_byte1 <= byte_data;
                        state     <= CRC_2;
                    end

                    CRC_2: begin
                        crc_byte2 <= byte_data;
                        state     <= CRC_3;
                    end

                    CRC_3: begin
                        if ({byte_data, crc_byte2, crc_byte1, crc_byte0} ==
                            (crc_reg ^ 32'hFFFFFFFF)) begin
                            frame_valid <= 1'b1;
                        end
                        else begin
                            frame_error <= ERROR_CRC;
                        end
                        state <= WAIT_55;
                    end

                    default: begin
                        state <= WAIT_55;
                    end
                endcase
            end
        end
    end

endmodule
