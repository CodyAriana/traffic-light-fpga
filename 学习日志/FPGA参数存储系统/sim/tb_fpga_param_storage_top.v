`timescale 1ns / 1ps

module tb_fpga_param_storage_top;

    localparam integer CLK_PERIOD_NS = 10;
    localparam integer BIT_TICKS     = 100;

    reg        clk_50m;
    reg        rst_n;
    reg        uart_rx_pin;
    wire       uart_tx_pin;
    wire       flash_cs_n;
    wire       flash_io0;
    reg        flash_io1;
    wire       flash_io2;
    wire       flash_io3;
    wire [3:0] led;

    reg [7:0] received [0:7];
    integer   i;

    fpga_param_storage_top #(
        .CLK_FREQ_HZ     (1_000_000),
        .BAUD_RATE       (10_000),
        .SPI_CLK_DIV     (1),
        .AUTO_BOOT       (1'b0)
    ) dut (
        .clk_50m    (clk_50m),
        .rst_n      (rst_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .flash_cs_n (flash_cs_n),
        .flash_io0  (flash_io0),
        .flash_io1  (flash_io1),
        .flash_io2  (flash_io2),
        .flash_io3  (flash_io3),
        .led        (led)
    );

    initial clk_50m = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk_50m = ~clk_50m;

    function [31:0] crc32_next_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        integer      bit_index;
        reg [31:0]   crc_work;
        begin
            crc_work = crc_in ^ {24'd0, data_in};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (crc_work[0])
                    crc_work = (crc_work >> 1) ^ 32'hEDB88320;
                else
                    crc_work = crc_work >> 1;
            end
            crc32_next_byte = crc_work;
        end
    endfunction

    task send_uart_byte;
        input [7:0] value;
        integer bit_index;
        begin
            uart_rx_pin = 1'b0;
            repeat (BIT_TICKS) @(negedge clk_50m);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_pin = value[bit_index];
                repeat (BIT_TICKS) @(negedge clk_50m);
            end
            uart_rx_pin = 1'b1;
            repeat (BIT_TICKS) @(negedge clk_50m);
        end
    endtask

    task send_load_default_frame;
        reg [31:0] crc_work;
        begin
            crc_work = 32'hFFFFFFFF;
            crc_work = crc32_next_byte(crc_work, 8'h01);
            crc_work = crc32_next_byte(crc_work, 8'h06);
            crc_work = crc32_next_byte(crc_work, 8'h00);
            crc_work = crc32_next_byte(crc_work, 8'h00);
            crc_work = crc32_next_byte(crc_work, 8'h01);
            crc_work = crc_work ^ 32'hFFFFFFFF;

            send_uart_byte(8'h55);
            send_uart_byte(8'hAA);
            send_uart_byte(8'h01);
            send_uart_byte(8'h06);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h01);
            send_uart_byte(crc_work[7:0]);
            send_uart_byte(crc_work[15:8]);
            send_uart_byte(crc_work[23:16]);
            send_uart_byte(crc_work[31:24]);
        end
    endtask

    task receive_uart_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge uart_tx_pin);
            repeat (BIT_TICKS + BIT_TICKS / 2) @(posedge clk_50m);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx_pin;
                repeat (BIT_TICKS) @(posedge clk_50m);
            end
            repeat (BIT_TICKS) @(posedge clk_50m);
        end
    endtask

    // The transmitter sends the next byte immediately after the stop bit.
    // Continue from the previous byte's timing instead of looking for a new
    // edge, because the next start edge may coincide with a clock event.
    task receive_uart_byte_contiguous;
        output [7:0] value;
        integer bit_index;
        begin
            repeat (BIT_TICKS) @(posedge clk_50m);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx_pin;
                repeat (BIT_TICKS) @(posedge clk_50m);
            end
            repeat (BIT_TICKS) @(posedge clk_50m);
        end
    endtask

    initial begin
        uart_rx_pin = 1'b1;
        flash_io1   = 1'b1;
        rst_n       = 1'b0;

        repeat (5) @(posedge clk_50m);
        rst_n = 1'b1;
        repeat (10) @(posedge clk_50m);

        fork
            begin
                send_load_default_frame();
            end
            begin
                receive_uart_byte(received[0]);
                for (i = 1; i < 8; i = i + 1)
                    receive_uart_byte_contiguous(received[i]);
            end
        join

        if (received[0] !== 8'h55 || received[1] !== 8'hAA ||
            received[2] !== 8'h86 || received[3] !== 8'h00 ||
            received[4] !== 8'h0B || received[5] !== 8'h00 ||
            received[6] !== 8'h01 || received[7] !== 8'h00) begin
            $display("TEST_FAIL: top UART response header/status mismatch");
            $finish(1);
        end

        $display("TEST_PASS: top UART command reached controller and returned response");
        $finish(0);
    end

    initial begin
        #2_000_000;
        $display("TEST_FAIL: top-level integration test timeout");
        $finish(1);
    end

endmodule
