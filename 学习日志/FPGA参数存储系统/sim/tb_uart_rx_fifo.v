`timescale 1ns / 1ps

module tb_uart_rx_fifo;

    reg       clk;
    reg       rst_n;
    reg       wr_en;
    reg [7:0] wr_data;
    reg       rd_en;
    wire [7:0] rd_data;
    wire      empty;
    wire      full;
    wire [6:0] count;

    uart_rx_fifo #(
        .DATA_WIDTH (8),
        .DEPTH      (64)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .empty    (empty),
        .full     (full),
        .count    (count)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic write_byte(input [7:0] value);
        begin
            @(negedge clk);
            wr_data = value;
            wr_en   = 1'b1;
            @(negedge clk);
            wr_en   = 1'b0;
        end
    endtask

    task automatic read_byte(input [7:0] expected, input [255:0] name);
        begin
            @(negedge clk);
            rd_en = 1'b1;
            @(posedge clk);
            #1;
            rd_en = 1'b0;
            if (rd_data !== expected) begin
                $display("TEST_FAIL: %0s expected=%02h got=%02h", name, expected, rd_data);
                $finish(1);
            end
            $display("TEST_PASS: %0s data=%02h", name, rd_data);
        end
    endtask

    integer i;

    initial begin
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        wr_data = 8'h00;
        rd_en   = 1'b0;

        #20;
        rst_n = 1'b1;
        #1;

        if (empty !== 1'b1 || full !== 1'b0 || count !== 7'd0) begin
            $display("TEST_FAIL: reset flags empty=%b full=%b count=%0d", empty, full, count);
            $finish(1);
        end

        // 空 FIFO 读操作不能改变 count。
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        #1;
        rd_en = 1'b0;
        if (count !== 7'd0) begin
            $display("TEST_FAIL: empty read changed count");
            $finish(1);
        end

        write_byte(8'h11);
        write_byte(8'h22);
        write_byte(8'h33);
        if (count !== 7'd3 || empty !== 1'b0) begin
            $display("TEST_FAIL: write count=%0d empty=%b", count, empty);
            $finish(1);
        end

        read_byte(8'h11, "ordered_read_0");
        read_byte(8'h22, "ordered_read_1");
        read_byte(8'h33, "ordered_read_2");
        if (empty !== 1'b1 || count !== 7'd0) begin
            $display("TEST_FAIL: FIFO not empty after reads");
            $finish(1);
        end

        // 填满 64 项，检查 full 和计数器。
        for (i = 0; i < 64; i = i + 1) begin
            write_byte(i[7:0]);
        end
        if (full !== 1'b1 || count !== 7'd64) begin
            $display("TEST_FAIL: full check full=%b count=%0d", full, count);
            $finish(1);
        end

        // 满 FIFO 继续写入应被拒绝，原数据不能被覆盖。
        write_byte(8'hEE);
        if (full !== 1'b1 || count !== 7'd64) begin
            $display("TEST_FAIL: write to full FIFO changed state");
            $finish(1);
        end

        read_byte(8'h00, "full_fifo_first_read");
        if (full !== 1'b0 || count !== 7'd63) begin
            $display("TEST_FAIL: full flag did not clear");
            $finish(1);
        end

        // 同时读写时，队列数量保持不变。
        @(negedge clk);
        wr_data = 8'hAB;
        wr_en   = 1'b1;
        rd_en   = 1'b1;
        @(posedge clk);
        #1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        if (count !== 7'd63) begin
            $display("TEST_FAIL: simultaneous read/write changed count=%0d", count);
            $finish(1);
        end

        $display("TEST_PASS: all UART RX FIFO tests passed");
        $finish(0);
    end

endmodule
