`timescale 1ns / 1ps

module tb_uart_tx;

    localparam integer CLK_FREQ_HZ = 1_000_000;
    localparam integer BAUD_RATE   = 10_000;
    localparam integer CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;
    localparam integer BIT_NS      = 1_000_000_000 / BAUD_RATE;

    reg       clk;
    reg       rst_n;
    reg       tx_start;
    reg [7:0] tx_data;
    wire      tx;
    wire      tx_busy;

    uart_tx #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        #5_000_000;
        $display("TEST_FAIL: UART TX test timeout, tx_busy=%b tx=%b", tx_busy, tx);
        $finish(1);
    end

    task automatic send_and_check(input [7:0] value);
        integer i;
        begin
            @(negedge clk);
            tx_data  = value;
            tx_start = 1'b1;
            // 这个上升沿是 DUT 接受 tx_start、拉低起始位的时刻。
            @(posedge clk);
            @(negedge clk);
            tx_start = 1'b0;

            #(BIT_NS / 2);
            if (tx !== 1'b0) begin
                $display("TEST_FAIL: start bit is not low");
                $finish(1);
            end

            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                $display("TX_SAMPLE: time=%0t bit=%0d expected=%b got=%b", $time, i, value[i], tx);
                if (tx !== value[i]) begin
                    $display("TEST_FAIL: bit %0d expected %b got %b", i, value[i], tx);
                    $finish(1);
                end
            end

            #(BIT_NS);
            if (tx !== 1'b1) begin
                $display("TEST_FAIL: stop bit is not high");
                $finish(1);
            end

            wait (tx_busy === 1'b0);
            $display("TEST_PASS: UART TX sent %02h", value);
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        tx_start = 1'b0;
        tx_data  = 8'h00;

        #100;
        rst_n = 1'b1;
        #100;

        send_and_check(8'hA5);
        $finish(0);
    end

endmodule
