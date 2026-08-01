`timescale 1ns / 1ps

module tb_command_parser;

    reg        clk;
    reg        rst_n;
    reg        byte_valid;
    reg [7:0]  byte_data;
    wire       frame_valid;
    wire [7:0] command;
    wire [7:0] seq_num;
    wire [15:0] payload_length;
    wire [255:0] payload;
    wire [2:0] frame_error;

    integer valid_count;
    integer error_count;
    reg [7:0] last_command;
    reg [7:0] last_sequence;
    reg [15:0] last_length;
    reg [2:0] last_error;

    command_parser dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .byte_valid     (byte_valid),
        .byte_data      (byte_data),
        .frame_valid    (frame_valid),
        .command        (command),
        .seq_num        (seq_num),
        .payload_length (payload_length),
        .payload        (payload),
        .frame_error    (frame_error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        #1;
        if (frame_valid) begin
            valid_count  = valid_count + 1;
            last_command = command;
            last_sequence = seq_num;
            last_length  = payload_length;
        end
        if (frame_error != 3'd0) begin
            error_count = error_count + 1;
            last_error  = frame_error;
        end
    end

    function [31:0] crc_update;
        input [31:0] crc_in;
        input [7:0]  data_in;
        integer i;
        reg [31:0] c;
        begin
            c = crc_in ^ {24'd0, data_in};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0]) c = (c >> 1) ^ 32'hEDB88320;
                else     c = c >> 1;
            end
            crc_update = c;
        end
    endfunction

    function [31:0] read_param_crc;
        reg [31:0] c;
        begin
            c = 32'hFFFFFFFF;
            c = crc_update(c, 8'h01);
            c = crc_update(c, 8'h02);
            c = crc_update(c, 8'h00);
            c = crc_update(c, 8'h00);
            c = crc_update(c, 8'h42);
            read_param_crc = c ^ 32'hFFFFFFFF;
        end
    endfunction

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge clk);
            byte_data  = value;
            byte_valid = 1'b1;
            @(negedge clk);
            byte_valid = 1'b0;
        end
    endtask

    task automatic send_read_param(input bit corrupt_crc);
        reg [31:0] c;
        begin
            c = read_param_crc();
            if (corrupt_crc) c = c ^ 32'h00000001;
            send_byte(8'h55);
            send_byte(8'hAA);
            send_byte(8'h01);
            send_byte(8'h02);
            send_byte(8'h00);
            send_byte(8'h00);
            send_byte(8'h42);
            send_byte(c[7:0]);
            send_byte(c[15:8]);
            send_byte(c[23:16]);
            send_byte(c[31:24]);
        end
    endtask

    initial begin
        #10_000;
        $display("TEST_FAIL: command parser timeout valid=%0d errors=%0d", valid_count, error_count);
        $finish(1);
    end

    initial begin
        rst_n       = 1'b0;
        byte_valid  = 1'b0;
        byte_data   = 8'h00;
        valid_count = 0;
        error_count = 0;
        last_command = 8'h00;
        last_sequence = 8'h00;
        last_length = 16'h0000;
        last_error = 3'd0;

        #20;
        rst_n = 1'b1;

        send_read_param(1'b0);
        wait (valid_count == 1);
        if (last_command !== 8'h02 || last_sequence !== 8'h42 || last_length !== 16'd0) begin
            $display("TEST_FAIL: valid frame fields command=%02h seq=%02h len=%0d", last_command, last_sequence, last_length);
            $finish(1);
        end
        $display("TEST_PASS: valid READ_PARAM frame");

        send_read_param(1'b1);
        wait (error_count == 1);
        if (last_error !== 3'b001) begin
            $display("TEST_FAIL: CRC error code=%b", last_error);
            $finish(1);
        end
        $display("TEST_PASS: CRC error rejected");

        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h21);
        send_byte(8'h00);
        wait (error_count == 2);
        if (last_error !== 3'b010) begin
            $display("TEST_FAIL: length error code=%b", last_error);
            $finish(1);
        end
        $display("TEST_PASS: oversized frame rejected");

        send_byte(8'h55);
        send_byte(8'hAA);
        send_byte(8'h02);
        wait (error_count == 3);
        if (last_error !== 3'b100) begin
            $display("TEST_FAIL: version error code=%b", last_error);
            $finish(1);
        end
        $display("TEST_PASS: unsupported version rejected");

        // 错误帧之后必须能重新寻找帧头。
        send_read_param(1'b0);
        wait (valid_count == 2);
        $display("TEST_PASS: parser recovered after errors");

        $display("TEST_PASS: all command parser tests passed");
        $finish(0);
    end

endmodule
