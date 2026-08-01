`timescale 1ns / 1ps

module tb_spi_flash_xfer;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg [63:0] tx_bytes;
    reg [3:0]  tx_count;
    reg [3:0]  rx_count;
    wire       busy;
    wire       done;
    wire [63:0] rx_bytes;
    wire       flash_cs_n;
    wire       flash_sck;
    wire       flash_mosi;
    reg        flash_miso;

    // 行为级 SPI Flash 模型的内部信号。
    reg [7:0]  model_shift;
    reg [7:0]  model_command;
    reg [2:0]  model_bit_index;
    reg [2:0]  model_byte_index;
    reg [31:0] model_response;
    reg [5:0]  model_response_bits;
    reg [5:0]  model_response_index;
    reg        model_response_active;
    reg        model_miso_started;
    reg [7:0]  model_byte0;
    reg [7:0]  model_byte1;
    reg [7:0]  model_byte2;
    reg [7:0]  model_byte3;

    spi_flash_xfer #(
        .CLK_DIV (2)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .tx_bytes   (tx_bytes),
        .tx_count   (tx_count),
        .rx_count   (rx_count),
        .busy       (busy),
        .done       (done),
        .rx_bytes   (rx_bytes),
        .flash_cs_n (flash_cs_n),
        .flash_sck  (flash_sck),
        .flash_mosi (flash_mosi),
        .flash_miso (flash_miso)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    // CS 拉低代表一笔新 SPI 事务开始，清空模型状态。
    always @(negedge flash_cs_n) begin
        model_shift           = 8'd0;
        model_command         = 8'd0;
        model_bit_index       = 3'd0;
        model_byte_index      = 3'd0;
        model_response        = 32'd0;
        model_response_bits   = 6'd0;
        model_response_index  = 6'd0;
        model_response_active = 1'b0;
        model_miso_started    = 1'b0;
        model_byte0           = 8'd0;
        model_byte1           = 8'd0;
        model_byte2           = 8'd0;
        model_byte3           = 8'd0;
        flash_miso            = 1'b0;
    end

    // SPI Mode 0：Flash 在上升沿采样 MOSI。
    always @(posedge flash_sck) begin
        if (!flash_cs_n) begin
            model_shift = {model_shift[6:0], flash_mosi};
            if (model_bit_index == 3'd7) begin
                case (model_byte_index)
                    3'd0: model_byte0 = model_shift;
                    3'd1: model_byte1 = model_shift;
                    3'd2: model_byte2 = model_shift;
                    3'd3: model_byte3 = model_shift;
                    default: ;
                endcase

                if (model_byte_index == 3'd0) begin
                    model_command = model_shift;
                    if (model_shift == 8'h9F) begin
                        model_response        = 32'h0020BA18;
                        model_response_bits   = 6'd24;
                        model_response_active = 1'b1;
                    end
                end

                // 0x03 后面有 24 位地址，四个发送字节后开始返回数据。
                if (model_byte_index == 3'd3 && model_command == 8'h03) begin
                    model_response        = 32'hDEADBEEF;
                    model_response_bits   = 6'd32;
                    model_response_active = 1'b1;
                end

                model_bit_index  = 3'd0;
                model_byte_index = model_byte_index + 1'b1;
            end
            else begin
                model_bit_index = model_bit_index + 1'b1;
            end
        end
    end

    // SPI Mode 0：Flash 在下降沿准备下一位 MISO，主机在下一上升沿采样。
    always @(negedge flash_sck) begin
        if (!flash_cs_n && model_response_active) begin
            if (!model_miso_started) begin
                flash_miso         = model_response[model_response_bits - 1'b1];
                model_miso_started = 1'b1;
                model_response_index = 6'd0;
            end
            else if (model_response_index + 1'b1 < model_response_bits) begin
                flash_miso = model_response[model_response_bits - 2 - model_response_index];
                model_response_index = model_response_index + 1'b1;
            end
        end
    end

    task automatic start_transaction(
        input [63:0] bytes,
        input [3:0]  send_count,
        input [3:0]  receive_count
    );
        begin
            @(negedge clk);
            tx_bytes = bytes;
            tx_count = send_count;
            rx_count = receive_count;
            start    = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done === 1'b1);
            #1;
            if (flash_cs_n !== 1'b1 || flash_sck !== 1'b0 || busy !== 1'b0) begin
                $display("TEST_FAIL: SPI did not return to idle");
                $finish(1);
            end
        end
    endtask

    initial begin
        #100_000;
        $display("TEST_FAIL: SPI transfer test timeout");
        $finish(1);
    end

    initial begin
        rst_n    = 1'b0;
        start    = 1'b0;
        tx_bytes = 64'd0;
        tx_count = 4'd0;
        rx_count = 4'd0;
        flash_miso = 1'b0;

        #100;
        rst_n = 1'b1;

        // 0x9F：读取 Flash JEDEC ID，期望 20 BA 18。
        start_transaction({8'h9F, 56'd0}, 4'd1, 4'd3);
        if (rx_bytes[63:40] !== 24'h20BA18 || model_byte0 !== 8'h9F) begin
            $display("TEST_FAIL: JEDEC ID expected 20BA18 got %06h cmd=%02h", rx_bytes[63:40], model_byte0);
            $finish(1);
        end
        $display("TEST_PASS: JEDEC ID transaction returned %06h", rx_bytes[63:40]);

        // 0x03 FF 00 00：读取四个字节，Flash 模型返回 DE AD BE EF。
        start_transaction({8'h03, 8'hFF, 8'h00, 8'h00, 32'd0}, 4'd4, 4'd4);
        if (rx_bytes[63:32] !== 32'hDEADBEEF ||
            model_byte0 !== 8'h03 || model_byte1 !== 8'hFF ||
            model_byte2 !== 8'h00 || model_byte3 !== 8'h00) begin
            $display("TEST_FAIL: read transaction data=%08h bytes=%02h %02h %02h %02h",
                rx_bytes[63:32], model_byte0, model_byte1, model_byte2, model_byte3);
            $finish(1);
        end
        $display("TEST_PASS: 0x03 read transaction returned %08h", rx_bytes[63:32]);

        $display("TEST_PASS: all SPI Flash transfer tests passed");
        $finish(0);
    end

endmodule
