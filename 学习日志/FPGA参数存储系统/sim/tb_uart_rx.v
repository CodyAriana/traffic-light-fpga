`timescale 1ns / 1ps

module tb_uart_rx;

    localparam integer CLK_FREQ_HZ = 1_000_000;
    localparam integer BAUD_RATE   = 10_000;
    localparam integer CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;
    localparam integer BIT_NS      = 1_000_000_000 / BAUD_RATE;

    reg       clk;
    reg       rst_n;
    reg       rx;
    wire      rx_valid;
    wire [7:0] rx_data;
    wire      busy;
    integer   rx_count;
    reg [7:0] seen0;
    reg [7:0] seen1;

    uart_rx #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rx        (rx),
        .rx_valid  (rx_valid),
        .rx_data   (rx_data),
        .busy      (busy)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    always @(posedge clk) begin
        if (rx_valid) begin
            if (rx_count == 0) seen0 = rx_data;
            if (rx_count == 1) seen1 = rx_data;
            rx_count = rx_count + 1;
        end
    end

    initial begin
        #5_000_000;
        $display("TEST_FAIL: UART RX test timeout, received_count=%0d busy=%b", rx_count, busy);
        $finish(1);
    end

    task automatic send_uart_byte(input [7:0] value);
        integer i;
        begin
            rx = 1'b0;
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = value[i];
                #(BIT_NS);
            end
            rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        rx      = 1'b1;
        rx_count = 0;
        seen0   = 8'h00;
        seen1   = 8'h00;

        #100;
        rst_n = 1'b1;
        #100;

        send_uart_byte(8'h55);
        send_uart_byte(8'hA5);
        wait (rx_count == 2);
        #20;

        if (seen0 !== 8'h55 || seen1 !== 8'hA5) begin
            $display("TEST_FAIL: RX expected 55 A5 got %02h %02h", seen0, seen1);
            $finish(1);
        end

        $display("TEST_PASS: UART RX received 55 A5");
        $finish(0);
    end

endmodule
