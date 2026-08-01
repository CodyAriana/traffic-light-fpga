`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// SPI Mode 0 单事务引擎
//
// tx_bytes 的最高字节最先发送。例如：
//   {8'h03, 8'hFF, 8'h00, 8'h00, 32'd0}
// 会依次发送 03 FF 00 00。
//
// 发送完 tx_count 个字节后，继续发送 0x00 作为 dummy byte，
// 同时接收 rx_count 个字节。收到的数据左对齐到 rx_bytes 高位。
// -----------------------------------------------------------------------------
module spi_flash_xfer #(
    parameter integer CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] tx_bytes,
    input  wire [3:0]  tx_count,
    input  wire [3:0]  rx_count,
    output reg         busy,
    output reg         done,
    output reg  [63:0] rx_bytes,
    output reg         flash_cs_n,
    output reg         flash_sck,
    output reg         flash_mosi,
    input  wire        flash_miso
);

    reg [63:0] tx_bytes_reg;
    reg [3:0]  tx_count_reg;
    reg [3:0]  rx_count_reg;
    reg [7:0]  total_bits;
    reg [7:0]  bit_index;
    reg [15:0] div_count;
    reg [63:0] rx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_bytes_reg <= 64'd0;
            tx_count_reg <= 4'd0;
            rx_count_reg <= 4'd0;
            total_bits   <= 8'd0;
            bit_index    <= 8'd0;
            div_count    <= 16'd0;
            rx_shift     <= 64'd0;
            rx_bytes     <= 64'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            flash_cs_n    <= 1'b1;
            flash_sck     <= 1'b0;
            flash_mosi    <= 1'b0;
        end
        else begin
            done <= 1'b0;

            if (!busy) begin
                flash_cs_n <= 1'b1;
                flash_sck  <= 1'b0;
                div_count  <= 16'd0;

                if (start && tx_count != 4'd0 && tx_count <= 4'd8 && rx_count <= 4'd8) begin
                    tx_bytes_reg <= tx_bytes;
                    tx_count_reg <= tx_count;
                    rx_count_reg <= rx_count;
                    total_bits   <= (tx_count + rx_count) << 3;
                    bit_index    <= 8'd0;
                    rx_shift     <= 64'd0;
                    rx_bytes     <= 64'd0;
                    flash_cs_n   <= 1'b0;
                    flash_sck    <= 1'b0;
                    flash_mosi   <= tx_bytes[63];
                    busy         <= 1'b1;
                end
            end
            else begin
                if (div_count == CLK_DIV - 1) begin
                    div_count <= 16'd0;

                    if (!flash_sck) begin
                        // 上升沿：Flash 采样 MOSI，主机采样 MISO。
                        flash_sck <= 1'b1;
                        if (bit_index >= (tx_count_reg << 3)) begin
                            rx_shift <= {rx_shift[62:0], flash_miso};
                        end
                    end
                    else begin
                        // 下降沿：准备下一位 MOSI；Mode 0 下从机也会准备下一位 MISO。
                        flash_sck <= 1'b0;

                        if (bit_index == total_bits - 1'b1) begin
                            flash_cs_n <= 1'b1;
                            flash_mosi <= 1'b0;
                            busy       <= 1'b0;
                            done       <= 1'b1;

                            if (rx_count_reg != 4'd0) begin
                                rx_bytes <= rx_shift << (64 - (rx_count_reg << 3));
                            end
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                            if ((bit_index + 1'b1) < (tx_count_reg << 3)) begin
                                flash_mosi <= tx_bytes_reg[63 - (bit_index + 1'b1)];
                            end
                            else begin
                                flash_mosi <= 1'b0;
                            end
                        end
                    end
                end
                else begin
                    div_count <= div_count + 1'b1;
                end
            end
        end
    end

endmodule
