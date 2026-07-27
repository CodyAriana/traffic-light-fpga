`timescale 1ns / 1ps

// ============================================================
// 野火升腾 Mini：交通灯状态机
//
// LED1（led[0]）= 绿灯
// LED2（led[1]）= 黄灯
// LED3（led[2]）= 红灯
// LED4（led[3]）= 不使用，始终熄灭
//
// 开发板时钟：50 MHz
// 复位信号：低电平有效
// 默认循环：绿灯 5 秒 -> 黄灯 2 秒 -> 红灯 5 秒
// ============================================================

module traffic_light_top #(
    // CLK_FREQ_HZ 表示“每秒有多少个时钟”。
    parameter integer CLK_FREQ_HZ   = 50_000_000,
    parameter integer GREEN_TIME_S  = 5,
    parameter integer YELLOW_TIME_S = 2,
    parameter integer RED_TIME_S    = 5,
    parameter integer FAST_GREEN_TIME_S = 1,
    parameter integer FAST_YELLOW_TIME_S = 1,
    parameter integer FAST_RED_TIME_S   = 1 ,
    parameter integer DEBOUNCE_TIME_MS  = 20
)(
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire [3:0] key_n,
    output reg  [3:0] led
);

    // 给三个状态编号。2'b00 表示一个 2 位二进制数 00。
    localparam [1:0] GREEN  = 2'b00;
    localparam [1:0] YELLOW = 2'b01;
    localparam [1:0] RED    = 2'b10;

    // FPGA 不直接认识“秒”，所以把秒数换算成需要等待的时钟个数。
    localparam integer GREEN_TICKS  = CLK_FREQ_HZ * GREEN_TIME_S;
    localparam integer YELLOW_TICKS = CLK_FREQ_HZ * YELLOW_TIME_S;
    localparam integer RED_TICKS    = CLK_FREQ_HZ * RED_TIME_S;
    localparam integer FAST_GREEN_TICKS  = CLK_FREQ_HZ * FAST_GREEN_TIME_S;
    localparam integer FAST_YELLOW_TICKS = CLK_FREQ_HZ * FAST_YELLOW_TIME_S;
    localparam integer FAST_RED_TICKS    = CLK_FREQ_HZ * FAST_RED_TIME_S;
    localparam integer DEBOUNCE_TICKS_CALC =
                    CLK_FREQ_HZ * DEBOUNCE_TIME_MS / 1000;

    localparam integer DEBOUNCE_TICKS =
                    (DEBOUNCE_TICKS_CALC < 2) ? 2 : DEBOUNCE_TICKS_CALC;

    // state 保存当前灯色，state_count 记录当前灯色已经持续了多少个时钟。
    reg [1:0]  state;
    reg [31:0] state_count;
    reg        fast_mode;
    reg        key1_sync1;
    reg        key1_sync2;
    reg [31:0] key1_debounce_count;
    reg        key1_stable;
    reg        key1_stable_d;

    // 当前交通灯不依赖按键切换；保留 key_n 接口，方便后续加入按键消抖和手动控制。

    // 时序逻辑：只在时钟上升沿或复位到来时更新状态和计数器。
    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            // 按下复位键后，从绿灯和计数器 0 重新开始。
            state       <= GREEN;
            state_count <= 32'd0;
            fast_mode   <= 1'b0;
            key1_sync1 <= 1'b1;
            key1_sync2 <= 1'b1;
            key1_debounce_count <= 32'd0;
            key1_stable         <= 1'b1;
            key1_stable_d       <= 1'b1;
        end
        else begin
            key1_sync1 <= key_n[0];
            key1_sync2 <= key1_sync1;
                // 按键状态没有变化，清零消抖计数器
    if (key1_sync2 == key1_stable) begin
        key1_debounce_count <= 32'd0;
    end

    // 按键保持新状态足够长时间，确认按键状态改变
    else if (key1_debounce_count >= DEBOUNCE_TICKS - 1) begin
        key1_stable         <= key1_sync2;
        key1_debounce_count <= 32'd0;
    end

    // 按键状态刚发生变化，继续计数
    else begin
        key1_debounce_count <= key1_debounce_count + 1'b1;
    end

    // 保存上一个稳定状态，后面用来检测按下瞬间
    key1_stable_d <= key1_stable;
    // 检测稳定按键从 1 变成 0，表示按下了一次 KEY1
    if (key1_stable_d && !key1_stable) begin
        fast_mode <= ~fast_mode;
    end
            case (state)
                GREEN: begin
                    // 计数器从 0 开始，所以最后一个数是总次数减 1。
                    if ((fast_mode && state_count >= FAST_GREEN_TICKS - 1) ||
    (!fast_mode && state_count >= GREEN_TICKS - 1)) begin
                        state       <= YELLOW;
                        state_count <= 32'd0;
                    end
                    else begin
                        state_count <= state_count + 1'b1;
                    end
                end

                YELLOW: begin
                    if ((fast_mode && state_count >= FAST_YELLOW_TICKS - 1) ||
    (!fast_mode && state_count >= YELLOW_TICKS - 1)) begin
                        state       <= RED;
                        state_count <= 32'd0;
                    end
                    else begin
                        state_count <= state_count + 1'b1;
                    end
                end

                RED: begin
                    if ((fast_mode && state_count >= FAST_RED_TICKS - 1) ||
    (!fast_mode && state_count >= RED_TICKS - 1)) begin
                        state       <= GREEN;
                        state_count <= 32'd0;
                    end
                    else begin
                        state_count <= state_count + 1'b1;
                    end
                end

                // 如果状态受到干扰而变成非法值，就回到绿灯安全状态。
                default: begin
                    state       <= GREEN;
                    state_count <= 32'd0;
                end
            endcase
        end
    end

    // 组合逻辑：把当前状态翻译成四个 LED 的亮灭结果。
    always @(*) begin
        // 先给出默认值，保证所有情况下每个 LED 都有明确输出。
        led = 4'b0000;

        case (state)
            GREEN:   led[0] = 1'b1;
            YELLOW:  led[1] = 1'b1;
            RED:     led[2] = 1'b1;
            default: led    = 4'b0000;
        endcase
    end

endmodule
