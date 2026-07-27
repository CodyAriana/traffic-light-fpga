`timescale 1ns / 1ps

// ============================================================
// 交通灯状态机 Testbench
//
// 仿真时把各状态持续时间缩短为几个时钟周期：
// 绿灯 4 个时钟 -> 黄灯 2 个时钟 -> 红灯 3 个时钟
// Testbench 会自动检查状态、计数器和 LED，发现错误立即停止。
// ============================================================

module tb_traffic_light;

    reg        clk_50m;
    reg        rst_n;
    reg  [3:0] key_n;
    wire [3:0] led;

    // 使用很小的参数，让一次完整循环在很短时间内完成。
    traffic_light_top #(
        .CLK_FREQ_HZ   (1),
        .GREEN_TIME_S  (4),
        .YELLOW_TIME_S (2),
        .RED_TIME_S    (3)
    ) dut (
        .clk_50m (clk_50m),
        .rst_n   (rst_n),
        .key_n   (key_n),
        .led     (led)
    );

    // 仿真时钟：每 5 ns 翻转一次，所以完整周期是 10 ns。
    initial begin
        clk_50m = 1'b0;
        forever #5 clk_50m = ~clk_50m;
    end

    // 检查当前状态、计数值和 LED 是否符合预期。
    task automatic check_result;
        input [1:0]  expected_state;
        input [31:0] expected_count;
        input [3:0]  expected_led;
        input [8*32-1:0] step_name;
        begin
            // 等待 1 ns，让非阻塞赋值更新完成后再检查。
            #1;
            if (dut.state !== expected_state) begin
                $fatal(1,
                       "FAIL %0s: state=%b, expected=%b",
                       step_name, dut.state, expected_state);
            end
            if (dut.state_count !== expected_count) begin
                $fatal(1,
                       "FAIL %0s: count=%0d, expected=%0d",
                       step_name, dut.state_count, expected_count);
            end
            if (led !== expected_led) begin
                $fatal(1,
                       "FAIL %0s: led=%b, expected=%b",
                       step_name, led, expected_led);
            end
        end
    endtask

    initial begin
        // 低电平表示复位有效，并保持两个时钟上升沿。
        rst_n = 1'b0;
        key_n = 4'b1111;
        repeat (2) @(posedge clk_50m);
        check_result(2'b00, 32'd0, 4'b0001, "reset");

        // 释放复位。此时从绿灯、计数器 0 开始。
        rst_n = 1'b1;

        // 模拟 KEY1 被按下再释放；本实验暂不使用按键控制状态机。
        #2 key_n = 4'b1110;
        #3 key_n = 4'b1111;

        @(posedge clk_50m);
        check_result(2'b00, 32'd1, 4'b0001, "green count 1");
        @(posedge clk_50m);
        check_result(2'b00, 32'd2, 4'b0001, "green count 2");
        @(posedge clk_50m);
        check_result(2'b00, 32'd3, 4'b0001, "green count 3");
        @(posedge clk_50m);
        check_result(2'b01, 32'd0, 4'b0010, "green to yellow");

        @(posedge clk_50m);
        check_result(2'b01, 32'd1, 4'b0010, "yellow count 1");
        @(posedge clk_50m);
        check_result(2'b10, 32'd0, 4'b0100, "yellow to red");

        @(posedge clk_50m);
        check_result(2'b10, 32'd1, 4'b0100, "red count 1");
        @(posedge clk_50m);
        check_result(2'b10, 32'd2, 4'b0100, "red count 2");
        @(posedge clk_50m);
        check_result(2'b00, 32'd0, 4'b0001, "red to green");
                // 测试按下 KEY1，等待同步和消抖完成
        key_n = 4'b1110;

        // 等待两级同步器和消抖计数器完成
        repeat (5) @(posedge clk_50m);

        // 进入快速模式后，绿灯切换到黄灯
        check_result(2'b01, 32'd0, 4'b0010,
                     "fast green to yellow");

        // 快速黄灯切换到红灯
        @(posedge clk_50m);
        check_result(2'b10, 32'd0, 4'b0100,
                     "fast yellow to red");

        // 快速红灯回到绿灯
        @(posedge clk_50m);
        check_result(2'b00, 32'd0, 4'b0001,
                     "fast red to green");

        // 松开 KEY1
        key_n = 4'b1111;
        $display("TEST_PASS: traffic_light full cycle verified");
        $finish;
    end

endmodule
