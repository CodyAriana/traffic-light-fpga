`timescale 1ns / 1ps

module uart_echo_top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire       uart_rx_pin,
    output wire       uart_tx_pin,
    output reg  [3:0] led
);

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       tx_busy;
    wire       tx;

    reg [7:0] fifo_mem [0:15];
    reg [3:0] fifo_wr_ptr;
    reg [3:0] fifo_rd_ptr;
    reg [4:0] fifo_count;

    wire fifo_empty;
    wire fifo_full;
    wire fifo_push;
    wire fifo_pop;
    wire tx_start;
    wire [7:0] tx_data;

    assign fifo_empty = (fifo_count == 5'd0);
    assign fifo_full  = (fifo_count == 5'd16);
    assign fifo_push  = rx_valid & ~fifo_full;
    assign tx_start   = ~tx_busy & ~fifo_empty;
    assign fifo_pop   = tx_start;
    assign tx_data    = fifo_mem[fifo_rd_ptr];

    always @(posedge clk_50m) begin
        if (fifo_push) begin
            fifo_mem[fifo_wr_ptr] <= rx_data;
        end
    end

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 4'd0;
            fifo_rd_ptr <= 4'd0;
            fifo_count  <= 5'd0;
        end
        else begin
            case ({fifo_push, fifo_pop})
                2'b10: begin
                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                    fifo_count  <= fifo_count + 1'b1;
                end

                2'b01: begin
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                    fifo_count  <= fifo_count - 1'b1;
                end

                2'b11: begin
                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                end

                default: begin
                end
            endcase
        end
    end

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_rx_inst (
        .clk_50m(clk_50m),
        .rst_n(rst_n),
        .rx(uart_rx_pin),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx_inst (
        .clk_50m(clk_50m),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(tx),
        .tx_busy(tx_busy)
    );

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            led <= 4'b0000;
        end
        else if (rx_valid) begin
            led <= rx_data[3:0];
        end
    end

    assign uart_tx_pin = tx;

endmodule
