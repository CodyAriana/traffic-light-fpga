`timescale 1ns / 1ps

// UART command controller with LED control and readable ASCII acknowledgements.
module uart_command_ack_top #(
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
    wire       tx;
    wire       tx_busy;

    wire       command_valid;
    wire [3:0] command_led;
    wire [2:0] received_response_code;

    // Four-entry response FIFO. It stores one response code per received byte.
    reg [2:0] response_fifo [0:3];
    reg [1:0] fifo_wr_ptr;
    reg [1:0] fifo_rd_ptr;
    reg [2:0] fifo_count;

    wire       fifo_empty;
    wire       fifo_full;
    wire       fifo_push;
    wire       fifo_pop;
    wire       response_start;
    wire       response_busy;
    wire [2:0] response_code;
    wire       tx_start;
    wire [7:0] tx_data;

    assign fifo_empty    = (fifo_count == 3'd0);
    assign fifo_full     = (fifo_count == 3'd4);
    assign fifo_push     = rx_valid && !fifo_full;
    assign response_start = !response_busy && !fifo_empty;
    assign fifo_pop      = response_start;
    assign response_code = response_fifo[fifo_rd_ptr];

    always @(posedge clk_50m) begin
        if (fifo_push) begin
            response_fifo[fifo_wr_ptr] <= received_response_code;
        end
    end

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 2'd0;
            fifo_rd_ptr <= 2'd0;
            fifo_count  <= 3'd0;
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

    uart_cmd_decoder_ack uart_cmd_decoder_ack_inst (
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .command_valid(command_valid),
        .led_value(command_led),
        .response_code(received_response_code)
    );

    uart_response_tx uart_response_tx_inst (
        .clk_50m(clk_50m),
        .rst_n(rst_n),
        .response_start(response_start),
        .response_code(response_code),
        .uart_busy(tx_busy),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .response_busy(response_busy)
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
        else if (command_valid) begin
            led <= command_led;
        end
    end

    assign uart_tx_pin = tx;

endmodule
