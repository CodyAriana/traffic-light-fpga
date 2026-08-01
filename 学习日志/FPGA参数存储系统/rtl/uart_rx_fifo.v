`timescale 1ns / 1ps

// 单时钟同步 FIFO：用于暂存 UART RX 已经还原出的字节。
module uart_rx_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 64
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output wire                  empty,
    output wire                  full,
    output reg  [$clog2(DEPTH):0] count
);

    localparam integer ADDR_WIDTH = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_WIDTH{1'b0}};
            rd_ptr  <= {ADDR_WIDTH{1'b0}};
            rd_data <= {DATA_WIDTH{1'b0}};
            count   <= {(ADDR_WIDTH + 1){1'b0}};
        end
        else begin
            if (do_write) begin
                memory[wr_ptr] <= wr_data;
                if (wr_ptr == DEPTH - 1) begin
                    wr_ptr <= {ADDR_WIDTH{1'b0}};
                end
                else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (do_read) begin
                rd_data <= memory[rd_ptr];
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= {ADDR_WIDTH{1'b0}};
                end
                else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
