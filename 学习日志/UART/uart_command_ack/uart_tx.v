`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy
);

    // 发送一个 UART 数据位需要多少个 FPGA 时钟
    localparam integer BAUD_TICKS = CLK_FREQ_HZ / BAUD_RATE;

    // UART 状态
    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    // 内部寄存器
    reg [1:0]  state;
    reg [31:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_reg;

     always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            baud_count <= 32'd0;
            bit_index  <= 3'd0;
            data_reg   <= 8'd0;
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
        end
        else begin
            if (state == IDLE) begin
                // UART 空闲时，发送线必须保持高电平
                tx         <= 1'b1;
                tx_busy    <= 1'b0;
                baud_count <= 32'd0;
                bit_index  <= 3'd0;

                // 收到发送请求，保存要发送的数据
                if (tx_start) begin
                    data_reg <= tx_data;
                    state    <= START;
                    tx_busy  <= 1'b1;
                end
            end
             else if (state == START) begin
                // 起始位为低电平
                tx <= 1'b0;

                // 起始位持续 BAUD_TICKS 个时钟
                if (baud_count == BAUD_TICKS - 1) begin
                    baud_count <= 32'd0;
                    bit_index  <= 3'd0;
                    state      <= DATA;
                end
                else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
             else if (state == DATA) begin
                // 发送当前数据位
                tx <= data_reg[bit_index];

                // 当前数据位发送完成
                if (baud_count == BAUD_TICKS - 1) begin
                    baud_count <= 32'd0;

                    // bit_index 等于 7，说明 8 位数据发送完毕
                    if (bit_index == 3'd7) begin
                        bit_index <= 3'd0;
                        state     <= STOP;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
                else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
            else if (state == STOP) begin
                // 停止位为高电平
                tx <= 1'b1;

                // 停止位持续一个 UART 位时间
                if (baud_count == BAUD_TICKS - 1) begin
                    baud_count <= 32'd0;
                    state      <= IDLE;
                    tx_busy    <= 1'b0;
                end
                else begin
                    baud_count <= baud_count + 1'b1;
                end
            end
            else begin
                // 遇到非法状态时，回到空闲状态
                state      <= IDLE;
                baud_count <= 32'd0;
                bit_index  <= 3'd0;
                tx         <= 1'b1;
                tx_busy    <= 1'b0;
            end           
        end
    end   
endmodule