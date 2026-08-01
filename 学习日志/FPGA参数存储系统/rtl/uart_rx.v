`timescale 1ns / 1ps

// UART 8N1 接收器：空闲高电平，1 个起始位，8 个数据位，1 个停止位。
module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        rx_valid,
    output reg [7:0]  rx_data,
    output reg        busy
);

    localparam integer BAUD_TICKS      = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_BAUD_TICKS = BAUD_TICKS / 2;

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg       rx_meta;
    reg       rx_sync;
    reg [1:0] state;
    reg [31:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta    <= 1'b1;
            rx_sync    <= 1'b1;
            state      <= IDLE;
            baud_count <= 32'd0;
            bit_index  <= 3'd0;
            rx_shift   <= 8'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
            busy       <= 1'b0;
        end
        else begin
            // 两级同步器，降低异步串口输入导致亚稳态的传播风险。
            rx_meta  <= rx;
            rx_sync  <= rx_meta;
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    busy       <= 1'b0;
                    baud_count <= 32'd0;
                    if (!rx_sync) begin
                        state      <= START;
                        baud_count <= 32'd0;
                        busy       <= 1'b1;
                    end
                end

                START: begin
                    busy <= 1'b1;
                    if (baud_count == HALF_BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;
                        if (!rx_sync) begin
                            state     <= DATA;
                            bit_index <= 3'd0;
                        end
                        else begin
                            // 起始位中点不是低电平，说明是噪声或毛刺。
                            state <= IDLE;
                        end
                    end
                    else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                DATA: begin
                    busy <= 1'b1;
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count          <= 32'd0;
                        rx_shift[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            state <= STOP;
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
                    busy <= 1'b1;
                    if (baud_count == BAUD_TICKS - 1) begin
                        baud_count <= 32'd0;
                        state      <= IDLE;
                        busy       <= 1'b0;
                        if (rx_sync) begin
                            rx_data  <= rx_shift;
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
                    busy       <= 1'b0;
                end
            endcase
        end
    end

endmodule
