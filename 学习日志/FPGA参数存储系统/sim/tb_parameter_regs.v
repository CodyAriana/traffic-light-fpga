`timescale 1ns / 1ps

module tb_parameter_regs;

    localparam [87:0] DEFAULT_PARAMS = {
        32'd1001, 16'd5, 16'd2, 16'd5, 8'd0
    };

    reg        clk;
    reg        rst_n;
    reg        write_en;
    reg [87:0] write_params;
    reg        load_en;
    reg [87:0] load_params;
    reg        default_en;
    wire [87:0] params;
    wire       params_valid;
    wire       write_error;

    parameter_regs dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (write_en),
        .write_params (write_params),
        .load_en      (load_en),
        .load_params  (load_params),
        .default_en   (default_en),
        .params       (params),
        .params_valid (params_valid),
        .write_error  (write_error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_params(input [87:0] expected, input [255:0] name);
        begin
            #1;
            if (params !== expected || params_valid !== 1'b1) begin
                $display("TEST_FAIL: %0s params=%022h valid=%b", name, params, params_valid);
                $finish(1);
            end
            $display("TEST_PASS: %0s params=%022h", name, params);
        end
    endtask

    task automatic pulse_write(input [87:0] value);
        begin
            @(negedge clk);
            write_params = value;
            write_en     = 1'b1;
            @(posedge clk);
            #1;
            write_en = 1'b0;
        end
    endtask

    task automatic pulse_load(input [87:0] value);
        begin
            @(negedge clk);
            load_params = value;
            load_en     = 1'b1;
            @(posedge clk);
            #1;
            load_en = 1'b0;
        end
    endtask

    initial begin
        rst_n        = 1'b0;
        write_en     = 1'b0;
        write_params = 88'd0;
        load_en      = 1'b0;
        load_params  = 88'd0;
        default_en   = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        check_params(DEFAULT_PARAMS, "reset_defaults");

        pulse_write({32'd2026, 16'd20, 16'd3, 16'd10, 8'd1});
        check_params({32'd2026, 16'd20, 16'd3, 16'd10, 8'd1}, "valid_write");

        pulse_write({32'd2026, 16'd20, 16'd3, 16'd10, 8'd2});
        if (write_error !== 1'b1) begin
            $display("TEST_FAIL: invalid_mode was accepted");
            $finish(1);
        end
        check_params({32'd2026, 16'd20, 16'd3, 16'd10, 8'd1}, "reject_invalid_mode");

        pulse_write({32'd2026, 16'd20, 16'd3, 16'd0, 8'd1});
        if (write_error !== 1'b1) begin
            $display("TEST_FAIL: zero_green_time was accepted");
            $finish(1);
        end
        check_params({32'd2026, 16'd20, 16'd3, 16'd10, 8'd1}, "reject_zero_time");

        pulse_load({32'd3003, 16'd60, 16'd8, 16'd30, 8'd0});
        check_params({32'd3003, 16'd60, 16'd8, 16'd30, 8'd0}, "load_from_flash");

        @(negedge clk);
        default_en = 1'b1;
        @(posedge clk);
        #1;
        default_en = 1'b0;
        check_params(DEFAULT_PARAMS, "load_default");

        $display("TEST_PASS: all parameter register tests passed");
        $finish(0);
    end

endmodule
