`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam integer BAUD_TICKS      = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_BAUD_TICKS = BAUD_TICKS / 2;

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0]  state;
    reg [31:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_reg;

    reg rx_meta;
    reg rx_sync;

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_count <= 32'd0;
            bit_index  <= 3'd0;
            data_reg   <= 8'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
            rx_meta    <= 1'b1;
            rx_sync    <= 1'b1;
        end
        else begin
            rx_meta  <= rx;
            rx_sync  <= rx_meta;
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    baud_count <= 32'd0;
                    bit_index  <= 3'd0;

                    if (rx_sync == 1'b0) begin
                        state      <= START;
                        baud_count <= 32'd0;
                    end
                end

                START: begin
                    if (baud_count == HALF_BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;

                        if (rx_sync == 1'b0) begin
                            state     <= DATA;
                            bit_index <= 3'd0;
                        end
                        else begin
                            state <= IDLE;
                        end
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count        <= 32'd0;
                        data_reg[bit_index] <= rx_sync;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;
                        state      <= IDLE;

                        if (rx_sync == 1'b1) begin
                            rx_data  <= data_reg;
                            rx_valid <= 1'b1;
                        end
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                default: begin
                    state      <= IDLE;
                    baud_count <= 32'd0;
                    bit_index  <= 3'd0;
                end
            endcase
        end
    end

endmodule
