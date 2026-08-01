`timescale 1ns / 1ps

module tb_crc32;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg        data_valid;
    reg [7:0]  data_byte;
    reg        finish;
    wire       busy;
    wire       done;
    wire [31:0] crc;

    crc32 dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .data_valid (data_valid),
        .data_byte  (data_byte),
        .finish     (finish),
        .busy       (busy),
        .done       (done),
        .crc        (crc)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge clk);
            data_byte  = value;
            data_valid = 1'b1;
            @(negedge clk);
            data_valid = 1'b0;
        end
    endtask

    task automatic begin_frame;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic end_frame_and_check(input [31:0] expected, input [255:0] name);
        begin
            @(negedge clk);
            finish = 1'b1;
            @(negedge clk);
            finish = 1'b0;
            wait (done === 1'b1);
            #1;
            if (crc !== expected) begin
                $display("TEST_FAIL: %0s expected %08h got %08h", name, expected, crc);
                $finish(1);
            end
            $display("TEST_PASS: %0s crc=%08h", name, crc);
        end
    endtask

    initial begin
        rst_n      = 1'b0;
        start      = 1'b0;
        data_valid = 1'b0;
        data_byte  = 8'h00;
        finish     = 1'b0;

        #20;
        rst_n = 1'b1;

        // Standard CRC32 check vector: CRC32("123456789") = 0xCBF43926.
        begin_frame();
        send_byte("1");
        send_byte("2");
        send_byte("3");
        send_byte("4");
        send_byte("5");
        send_byte("6");
        send_byte("7");
        send_byte("8");
        send_byte("9");
        end_frame_and_check(32'hCBF43926, "123456789");

        // Empty input: CRC32 of an empty message is 0x00000000.
        begin_frame();
        end_frame_and_check(32'h00000000, "empty");

        // A second frame proves that start really reinitializes the calculator.
        begin_frame();
        send_byte(8'h00);
        end_frame_and_check(32'hD202EF8D, "one_zero_byte");

        $display("TEST_PASS: all CRC32 tests passed");
        $finish(0);
    end

endmodule
