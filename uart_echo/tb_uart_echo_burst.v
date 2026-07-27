`timescale 1ns / 1ps

module tb_uart_echo_burst;

    localparam integer BIT_CLKS = 10;

    reg        clk_50m;
    reg        rst_n;
    reg        uart_rx_pin;
    wire       uart_tx_pin;
    wire [3:0] led;

    reg [7:0] received_qwer [0:3];
    integer i;

    uart_echo_top #(
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
        reg [7:0] temp_data;
        integer bit_no;
        begin
            @(negedge uart_tx_pin);
            repeat (BIT_CLKS / 2) @(posedge clk_50m);
            #1;

            if (uart_tx_pin !== 1'b0) begin
                $display("TEST_FAIL: bad echoed start bit");
                $finish;
            end

            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                repeat (BIT_CLKS) @(posedge clk_50m);
                #1;
                temp_data[bit_no] = uart_tx_pin;
            end

            repeat (BIT_CLKS) @(posedge clk_50m);
            #1;

            if (uart_tx_pin !== 1'b1) begin
                $display("TEST_FAIL: bad echoed stop bit");
                $finish;
            end

            data = temp_data;
        end
    endtask

    initial begin : burst_test
        clk_50m = 1'b0;
        rst_n = 1'b0;
        uart_rx_pin = 1'b1;

        repeat (3) @(posedge clk_50m);
        #1 rst_n = 1'b1;

        fork : run_or_timeout
            begin
                #10000;
                $display("TEST_FAIL: burst echo timed out");
                $finish;
            end
            begin
                fork
                    begin
                        send_uart_byte(8'h51);
                        send_uart_byte(8'h57);
                        send_uart_byte(8'h45);
                        send_uart_byte(8'h52);
                    end
                    begin
                        receive_uart_byte(received_qwer[0]);
                        receive_uart_byte(received_qwer[1]);
                        receive_uart_byte(received_qwer[2]);
                        receive_uart_byte(received_qwer[3]);
                    end
                join

                if (received_qwer[0] !== 8'h51 ||
                    received_qwer[1] !== 8'h57 ||
                    received_qwer[2] !== 8'h45 ||
                    received_qwer[3] !== 8'h52) begin
                    $display("TEST_FAIL: QWER burst was not echoed correctly");
                    $finish;
                end

                disable run_or_timeout;
            end
        join

        $display("TEST_PASS: QWER burst was echoed correctly");
        $finish;
    end

endmodule
