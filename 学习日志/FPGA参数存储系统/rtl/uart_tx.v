`timescale 1ns / 1ps

// UART 8N1 发送器：LSB first，空闲高电平。
module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy
);

    localparam integer BAUD_TICKS = CLK_FREQ_HZ / BAUD_RATE;

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0]  state;
    reg [31:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_count <= 32'd0;
            bit_index  <= 3'd0;
            data_reg   <= 8'd0;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    tx         <= 1'b1;
                    tx_busy    <= 1'b0;
                    baud_count <= 32'd0;
                    bit_index  <= 3'd0;

                    if (tx_start) begin
                        data_reg   <= tx_data;
                        state       <= START;
                        tx          <= 1'b0;
                        tx_busy     <= 1'b1;
                        baud_count  <= 32'd0;
                    end
                end

                START: begin
                    tx      <= 1'b0;
                    tx_busy <= 1'b1;
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;
                        bit_index  <= 3'd0;
                        state      <= DATA;
                        tx         <= data_reg[0];
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    tx      <= data_reg[bit_index];
                    tx_busy <= 1'b1;
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;
                        if (bit_index == 3'd7) begin
                            state <= STOP;
                            tx    <= 1'b1;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                            tx        <= data_reg[bit_index + 1'b1];
                        end
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                STOP: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b1;
                    if (baud_count == BAUD_TICKS - 1) begin
                        state      <= IDLE;
                        baud_count <= 32'd0;
                        tx_busy    <= 1'b0;
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                default: begin
                    state      <= IDLE;
                    baud_count <= 32'd0;
                    tx         <= 1'b1;
                    tx_busy    <= 1'b0;
                end
            endcase
        end
    end

endmodule
