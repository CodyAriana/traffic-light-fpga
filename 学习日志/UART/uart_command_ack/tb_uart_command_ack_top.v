`timescale 1ns / 1ps

module tb_uart_command_ack_top;

    localparam integer BIT_CLKS = 10;

    reg        clk_50m;
    reg        rst_n;
    reg        uart_rx_pin;
    wire       uart_tx_pin;
    wire [3:0] led;

    uart_command_ack_top #(
        .CLK_FREQ_HZ(10),
        .BAUD_RATE(1)
    ) dut (
        .clk_50m(clk_50m),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .led(led)
    );

    always #5 clk_50m = ~clk_50m;

    task send_uart_byte;
        input [7:0] data;
        integer bit_no;
        begin
            uart_rx_pin = 1'b0;
            repeat (BIT_CLKS) @(posedge clk_50m);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                uart_rx_pin = data[bit_no];
                repeat (BIT_CLKS) @(posedge clk_50m);
            end
            uart_rx_pin = 1'b1;
            repeat (BIT_CLKS) @(posedge clk_50m);
        end
    endtask

    task receive_uart_byte;
        output [7:0] data;
        integer bit_no;
        begin
            @(negedge uart_tx_pin);
            repeat (BIT_CLKS / 2) @(posedge clk_50m);
            #1;
            if (uart_tx_pin !== 1'b0) begin
                $display("TEST_FAIL: bad response start bit");
                $finish;
            end

            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                repeat (BIT_CLKS) @(posedge clk_50m);
                #1 data[bit_no] = uart_tx_pin;
            end

            repeat (BIT_CLKS) @(posedge clk_50m);
            #1;
            if (uart_tx_pin !== 1'b1) begin
                $display("TEST_FAIL: bad response stop bit");
                $finish;
            end
        end
    endtask

    task expect_byte;
        input [7:0] expected;
        reg [7:0] actual;
        begin
            receive_uart_byte(actual);
            if (actual !== expected) begin
                $display("TEST_FAIL: expected byte %h, got %h", expected, actual);
                $finish;
            end
        end
    endtask

    task expect_off_reply;
        begin
            expect_byte("L"); expect_byte("E"); expect_byte("D");
            expect_byte(" "); expect_byte("O"); expect_byte("F");
            expect_byte("F"); expect_byte(8'h0d); expect_byte(8'h0a);
        end
    endtask

    task expect_green_reply;
        begin
            expect_byte("L"); expect_byte("E"); expect_byte("D");
            expect_byte(" "); expect_byte("G"); expect_byte("R");
            expect_byte("E"); expect_byte("E"); expect_byte("N");
            expect_byte(8'h0d); expect_byte(8'h0a);
        end
    endtask

    task expect_yellow_reply;
        begin
            expect_byte("L"); expect_byte("E"); expect_byte("D");
            expect_byte(" "); expect_byte("Y"); expect_byte("E");
            expect_byte("L"); expect_byte("L"); expect_byte("O");
            expect_byte("W"); expect_byte(8'h0d); expect_byte(8'h0a);
        end
    endtask

    task expect_red_reply;
        begin
            expect_byte("L"); expect_byte("E"); expect_byte("D");
            expect_byte(" "); expect_byte("R"); expect_byte("E");
            expect_byte("D"); expect_byte(8'h0d); expect_byte(8'h0a);
        end
    endtask

    task expect_error_reply;
        begin
            expect_byte("E"); expect_byte("R"); expect_byte("R");
            expect_byte("O"); expect_byte("R");
            expect_byte(8'h0d); expect_byte(8'h0a);
        end
    endtask

    initial begin
        clk_50m = 1'b0;
        rst_n = 1'b0;
        uart_rx_pin = 1'b1;

        repeat (3) @(posedge clk_50m);
        #1 rst_n = 1'b1;

        send_uart_byte("1");
        #1;
        if (led !== 4'b0001) begin
            $display("TEST_FAIL: command 1 did not select LED0");
            $finish;
        end
        expect_green_reply;

        send_uart_byte("2");
        #1;
        if (led !== 4'b0010) begin
            $display("TEST_FAIL: command 2 did not select LED1");
            $finish;
        end
        expect_yellow_reply;

        send_uart_byte("3");
        #1;
        if (led !== 4'b0100) begin
            $display("TEST_FAIL: command 3 did not select LED2");
            $finish;
        end
        expect_red_reply;

        send_uart_byte("0");
        #1;
        if (led !== 4'b0000) begin
            $display("TEST_FAIL: command 0 did not turn LEDs off");
            $finish;
        end
        expect_off_reply;

        send_uart_byte("X");
        #1;
        if (led !== 4'b0000) begin
            $display("TEST_FAIL: unknown command changed the LEDs");
            $finish;
        end
        expect_error_reply;

        $display("TEST_PASS: UART command acknowledgements work correctly");
        $finish;
    end

endmodule
