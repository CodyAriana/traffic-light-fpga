`timescale 1ns / 1ps

module tb_system_controller;

    localparam [87:0] BOOT_PARAMS = {
        32'h12345678, 16'd20, 16'd3, 16'd10, 8'd1
    };
    localparam [87:0] WRITE_PARAMS = {
        32'hA1B2C3D4, 16'd40, 16'd4, 16'd30, 8'd0
    };
    localparam [87:0] INVALID_PARAMS = {
        32'hA1B2C3D4, 16'd40, 16'd4, 16'd30, 8'd2
    };
    localparam [87:0] LOAD_PARAMS = {
        32'h0BADF00D, 16'd70, 16'd6, 16'd60, 8'd1
    };
    localparam [87:0] DEFAULT_PARAMS = {
        32'd1001, 16'd5, 16'd2, 16'd5, 8'd0
    };

    reg          clk;
    reg          rst_n;

    reg          frame_valid;
    reg  [7:0]   command;
    reg  [7:0]   seq_num;
    reg  [15:0]  payload_length;
    reg  [255:0] payload;
    reg  [2:0]   frame_error;

    wire [87:0] params;
    wire        params_valid;
    wire        write_error;
    wire        param_write_en;
    wire [87:0] param_write_params;
    wire        param_load_en;
    wire [87:0] param_load_params;
    wire        param_default_en;

    reg         flash_busy;
    reg         flash_done;
    reg  [7:0]  flash_error_code;
    reg  [87:0] flash_loaded_params;
    reg         flash_params_valid;
    reg         flash_active_slot;
    wire        flash_boot_start;
    wire        flash_save_start;
    wire        flash_load_start;

    reg         tx_busy;
    wire        tx_start;
    wire [7:0]  tx_data;
    wire        controller_busy;
    wire [7:0]  last_error;

    reg [7:0] tx_bytes [0:511];
    integer tx_count;
    integer tx_hold_cycles;
    integer boot_start_count;
    integer save_start_count;
    integer load_start_count;
    integer write_en_count;
    integer load_en_count;
    integer default_en_count;
    integer response_base;
    integer pulse_base;
    integer load_en_before;
    integer timeout_count;
    integer i;

    system_controller dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .frame_valid         (frame_valid),
        .command             (command),
        .seq_num             (seq_num),
        .payload_length      (payload_length),
        .payload             (payload),
        .frame_error         (frame_error),
        .params              (params),
        .params_valid        (params_valid),
        .write_error         (write_error),
        .param_write_en      (param_write_en),
        .param_write_params  (param_write_params),
        .param_load_en       (param_load_en),
        .param_load_params   (param_load_params),
        .param_default_en    (param_default_en),
        .flash_busy          (flash_busy),
        .flash_done          (flash_done),
        .flash_error_code    (flash_error_code),
        .flash_loaded_params (flash_loaded_params),
        .flash_params_valid  (flash_params_valid),
        .flash_active_slot   (flash_active_slot),
        .flash_boot_start    (flash_boot_start),
        .flash_save_start    (flash_save_start),
        .flash_load_start    (flash_load_start),
        .tx_busy             (tx_busy),
        .tx_start            (tx_start),
        .tx_data             (tx_data),
        .controller_busy     (controller_busy),
        .last_error          (last_error)
    );

    parameter_regs regs_model (
        .clk          (clk),
        .rst_n        (rst_n),
        .write_en     (param_write_en),
        .write_params (param_write_params),
        .load_en      (param_load_en),
        .load_params  (param_load_params),
        .default_en   (param_default_en),
        .params       (params),
        .params_valid (params_valid),
        .write_error  (write_error)
    );

    always #5 clk = ~clk;

    // UART sink: each accepted byte holds busy for a varying number of cycles.
    // Sampling tx_data one clock after the DUT raises tx_start matches uart_tx.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_busy        <= 1'b0;
            tx_hold_cycles <= 0;
            tx_count       <= 0;
        end
        else begin
            if (tx_start) begin
                if (tx_busy) begin
                    $display("TEST_FAIL: tx_start asserted while tx_busy");
                    $finish(1);
                end
                tx_bytes[tx_count] <= tx_data;
                tx_count           <= tx_count + 1;
                tx_busy            <= 1'b1;
                tx_hold_cycles     <= (tx_count % 3) + 1;
            end
            else if (tx_busy) begin
                if (tx_hold_cycles == 0) begin
                    tx_busy <= 1'b0;
                end
                else begin
                    tx_hold_cycles <= tx_hold_cycles - 1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_start_count <= 0;
            save_start_count <= 0;
            load_start_count <= 0;
            write_en_count   <= 0;
            load_en_count    <= 0;
            default_en_count <= 0;
        end
        else begin
            if (flash_boot_start) boot_start_count <= boot_start_count + 1;
            if (flash_save_start) save_start_count <= save_start_count + 1;
            if (flash_load_start) load_start_count <= load_start_count + 1;
            if (param_write_en)   write_en_count   <= write_en_count + 1;
            if (param_load_en)    load_en_count    <= load_en_count + 1;
            if (param_default_en) default_en_count <= default_en_count + 1;
        end
    end

    task fail;
        input [8*96-1:0] message;
        begin
            $display("TEST_FAIL: %0s", message);
            $finish(1);
        end
    endtask

    task pulse_frame;
        input [7:0] req_command;
        input [7:0] req_seq;
        input [15:0] req_length;
        input [255:0] req_payload;
        begin
            @(negedge clk);
            command        = req_command;
            seq_num        = req_seq;
            payload_length = req_length;
            payload        = req_payload;
            frame_valid    = 1'b1;
            @(negedge clk);
            frame_valid    = 1'b0;
        end
    endtask

    task pulse_parser_error;
        input [7:0] req_seq;
        begin
            @(negedge clk);
            seq_num     = req_seq;
            frame_error = 3'b001;
            @(negedge clk);
            frame_error = 3'b000;
        end
    endtask

    task wait_for_start;
        input [1:0] operation;
        begin
            timeout_count = 0;
            while ((((operation == 2'd0) && !flash_boot_start) ||
                    ((operation == 2'd1) && !flash_save_start) ||
                    ((operation == 2'd2) && !flash_load_start)) &&
                   (timeout_count < 100)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (timeout_count >= 100)
                fail("timed out waiting for Flash start pulse");
        end
    endtask

    task wait_until_ready;
        begin
            timeout_count = 0;
            while (controller_busy && (timeout_count < 200)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (timeout_count >= 200)
                fail("controller did not return to ready");
        end
    endtask

    task reset_for_boot;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            wait_for_start(2'd0);
        end
    endtask

    task complete_flash;
        input [7:0] result_code;
        input [87:0] result_params;
        input result_valid;
        input result_slot;
        integer tx_before_done;
        integer load_before_done;
        integer default_before_done;
        begin
            @(negedge clk);
            tx_before_done      = tx_count;
            load_before_done    = load_en_count;
            default_before_done = default_en_count;
            flash_busy          = 1'b1;
            flash_error_code    = 8'hAA;
            flash_loaded_params = INVALID_PARAMS;
            flash_params_valid  = 1'b0;
            flash_active_slot   = ~result_slot;
            repeat (3) begin
                @(negedge clk);
                if ((tx_count != tx_before_done) ||
                    (load_en_count != load_before_done) ||
                    (default_en_count != default_before_done))
                    fail("Flash result consumed before flash_done");
            end
            flash_busy          = 1'b0;
            flash_error_code    = result_code;
            flash_loaded_params = result_params;
            flash_params_valid  = result_valid;
            flash_active_slot   = result_slot;
            flash_done          = 1'b1;
            @(negedge clk);
            flash_done = 1'b0;
        end
    endtask

    task expect_response;
        input integer start_index;
        input integer frame_length;
        input [175:0] expected;
        begin
            timeout_count = 0;
            while ((tx_count < start_index + frame_length) &&
                   (timeout_count < 2000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (timeout_count >= 2000)
                fail("timed out waiting for complete UART response");

            timeout_count = 0;
            while (controller_busy && (timeout_count < 2000)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end
            if (timeout_count >= 2000)
                fail("controller did not return to ready");

            repeat (5) @(negedge clk);
            if (tx_count != start_index + frame_length) begin
                $display("TEST_FAIL: expected one %0d-byte response, got %0d bytes",
                         frame_length, tx_count - start_index);
                $finish(1);
            end

            for (i = 0; i < frame_length; i = i + 1) begin
                if (tx_bytes[start_index + i] !==
                    expected[(frame_length - 1 - i) * 8 +: 8]) begin
                    $display("TEST_FAIL: response byte %0d expected=%02h got=%02h",
                             i,
                             expected[(frame_length - 1 - i) * 8 +: 8],
                             tx_bytes[start_index + i]);
                    $finish(1);
                end
            end
        end
    endtask

    initial begin
        clk                 = 1'b0;
        rst_n               = 1'b0;
        frame_valid         = 1'b0;
        command             = 8'd0;
        seq_num             = 8'd0;
        payload_length      = 16'd0;
        payload             = 256'd0;
        frame_error         = 3'd0;
        flash_busy          = 1'b0;
        flash_done          = 1'b0;
        flash_error_code    = 8'd0;
        flash_loaded_params = DEFAULT_PARAMS;
        flash_params_valid  = 1'b1;
        flash_active_slot   = 1'b0;

        // A structurally valid Flash record can still contain out-of-range
        // parameters. parameter_regs must reject it, then the controller must
        // restore defaults and preserve status 03 for GET_STATUS.
        reset_for_boot();
        complete_flash(8'h00, INVALID_PARAMS, 1'b1, 1'b1);
        wait_until_ready();
        if (params !== DEFAULT_PARAMS || load_en_count != 1 ||
            default_en_count != 1 || last_error !== 8'h03)
            fail("boot invalid parameters did not fall back to defaults");
        response_base = tx_count;
        pulse_frame(8'h01, 8'h0F, 16'd0, 256'd0);
        expect_response(response_base, 15,
            176'h55AA810004000F00010103ACB9E860);
        $display("TEST_PASS: boot invalid parameters restore defaults with status 03");

        // The manager's normal no-record result publishes valid defaults with
        // status 06. They must be loaded and the status must remain visible.
        reset_for_boot();
        complete_flash(8'h06, DEFAULT_PARAMS, 1'b1, 1'b0);
        wait_until_ready();
        if (params !== DEFAULT_PARAMS || load_en_count != 1 ||
            default_en_count != 0 || last_error !== 8'h06)
            fail("boot status 06/default result was not loaded and preserved");
        $display("TEST_PASS: boot manager status 06 loads published defaults");

        reset_for_boot();

        // Automatic boot must run exactly once, keep the controller busy,
        // ignore parser events, and load the manager's parameters.
        if (!controller_busy)
            fail("controller_busy was low during automatic boot");
        pulse_frame(8'h02, 8'hEE, 16'd0, 256'd0);
        if (tx_count != 0)
            fail("command was accepted before boot recovery completed");
        complete_flash(8'h00, BOOT_PARAMS, 1'b1, 1'b1);
        wait_until_ready();
        if (params !== BOOT_PARAMS ||
            boot_start_count != 1 || load_en_count != 1 ||
            last_error !== 8'h00)
            fail("automatic boot did not load parameters exactly once");
        $display("TEST_PASS: automatic boot loads parameters and rejects commands");

        // GET_STATUS: [ready=0, active_slot, params_valid, last_error].
        response_base = tx_count;
        pulse_frame(8'h01, 8'h11, 16'd0, 256'd0);
        expect_response(response_base, 15,
            176'h55AA810004001100010100F5C13126);
        $display("TEST_PASS: GET_STATUS payload, CRC, and byte order");

        // READ_PARAM returns the current 11-byte parameter payload.
        response_base = tx_count;
        pulse_frame(8'h02, 8'h12, 16'd0, 256'd0);
        expect_response(response_base, 22,
            176'h55AA82000B0012010A000300140078563412E59BB0D6);
        $display("TEST_PASS: READ_PARAM returns current parameters");

        // WRITE_PARAM must pulse write_en, wait for registered validation,
        // and then report success.
        response_base = tx_count;
        pulse_base = write_en_count;
        pulse_frame(8'h03, 8'h13, 16'd11, {168'd0, WRITE_PARAMS});
        expect_response(response_base, 11,
            176'h55AA8300000013817CDAB4);
        if (write_en_count != pulse_base + 1 || params !== WRITE_PARAMS)
            fail("WRITE_PARAM did not commit through parameter_regs once");
        $display("TEST_PASS: WRITE_PARAM waits for registered success");

        // Wrong payload length must be rejected without touching registers.
        response_base = tx_count;
        pulse_base = write_en_count;
        pulse_frame(8'h03, 8'h14, 16'd10, {168'd0, WRITE_PARAMS});
        expect_response(response_base, 11,
            176'h55AA8303000014CC460B38);
        if (write_en_count != pulse_base || params !== WRITE_PARAMS)
            fail("bad WRITE_PARAM length changed parameters");
        $display("TEST_PASS: WRITE_PARAM rejects bad length");

        // Range validation is reported one cycle after write_en.
        response_base = tx_count;
        pulse_base = write_en_count;
        pulse_frame(8'h03, 8'h15, 16'd11, {168'd0, INVALID_PARAMS});
        expect_response(response_base, 11,
            176'h55AA83030000155A760C4F);
        if (write_en_count != pulse_base + 1 || params !== WRITE_PARAMS ||
            last_error !== 8'h03)
            fail("invalid WRITE_PARAM was not rejected after validation");
        $display("TEST_PASS: WRITE_PARAM propagates range failure");

        // Unsupported command and parser errors have distinct status codes.
        response_base = tx_count;
        pulse_frame(8'h7F, 8'h16, 16'd0, 256'd0);
        expect_response(response_base, 11,
            176'h55AAFF020000164B4D9B52);
        if (last_error !== 8'h02)
            fail("illegal command did not update last_error");
        $display("TEST_PASS: illegal command returns status 02");

        response_base = tx_count;
        pulse_parser_error(8'h17);
        expect_response(response_base, 11,
            176'h55AAFF0100001733D22937);
        if (last_error !== 8'h01)
            fail("parser error did not update last_error");
        $display("TEST_PASS: parser frame_error returns status 01");

        // SAVE_FLASH success. A READ pulse while save is outstanding must be
        // ignored and must not create a second response.
        response_base = tx_count;
        pulse_base = save_start_count;
        pulse_frame(8'h04, 8'h18, 16'd0, 256'd0);
        wait_for_start(2'd1);
        pulse_frame(8'h02, 8'hEE, 16'd0, 256'd0);
        complete_flash(8'h00, WRITE_PARAMS, 1'b1, 1'b1);
        expect_response(response_base, 11,
            176'h55AA840000001819792891);
        if (save_start_count != pulse_base + 1)
            fail("SAVE_FLASH start pulse count was not exactly one");
        $display("TEST_PASS: SAVE_FLASH succeeds and ignores busy-time frame");

        // A manager already busy at command acceptance returns status 04
        // immediately and does not issue a start pulse.
        flash_busy = 1'b1;
        response_base = tx_count;
        pulse_base = save_start_count;
        pulse_frame(8'h04, 8'h19, 16'd0, 256'd0);
        expect_response(response_base, 11,
            176'h55AA8404000019D8DE4D69);
        flash_busy = 1'b0;
        if (save_start_count != pulse_base || last_error !== 8'h04)
            fail("busy Flash was started instead of returning status 04");
        $display("TEST_PASS: Flash busy returns status 04");

        // Manager timeout result must propagate unchanged.
        response_base = tx_count;
        pulse_base = save_start_count;
        pulse_frame(8'h04, 8'h1A, 16'd0, 256'd0);
        wait_for_start(2'd1);
        complete_flash(8'h04, WRITE_PARAMS, 1'b1, 1'b1);
        expect_response(response_base, 11,
            176'h55AA840400001A628F44F0);
        if (save_start_count != pulse_base + 1 || last_error !== 8'h04)
            fail("Flash timeout status was not propagated");
        $display("TEST_PASS: Flash timeout propagates status 04");

        // Successful LOAD_FLASH must load parameter_regs before responding.
        response_base = tx_count;
        pulse_base = load_start_count;
        pulse_frame(8'h05, 8'h1B, 16'd0, 256'd0);
        wait_for_start(2'd2);
        complete_flash(8'h00, LOAD_PARAMS, 1'b1, 1'b0);
        expect_response(response_base, 22,
            176'h55AA85000B001B013C00060046000DF0AD0B09E4579F);
        if (load_start_count != pulse_base + 1 || params !== LOAD_PARAMS)
            fail("LOAD_FLASH did not load successful manager result");
        $display("TEST_PASS: LOAD_FLASH returns and installs parameters");

        // Success without a published parameter result is an invalid
        // readback/result combination and must become status 05.
        response_base = tx_count;
        pulse_base = load_en_count;
        pulse_frame(8'h05, 8'h1F, 16'd0, 256'd0);
        wait_for_start(2'd2);
        complete_flash(8'h00, DEFAULT_PARAMS, 1'b0, 1'b0);
        expect_response(response_base, 11,
            176'h55AA850500001F3835F205);
        if (load_en_count != pulse_base || params !== LOAD_PARAMS ||
            last_error !== 8'h05)
            fail("LOAD_FLASH 00 without valid result was not converted to 05");
        $display("TEST_PASS: LOAD_FLASH success without valid result returns 05");

        // Readback failure has no payload and must not overwrite parameters.
        response_base = tx_count;
        pulse_base = load_en_count;
        pulse_frame(8'h05, 8'h1C, 16'd0, 256'd0);
        wait_for_start(2'd2);
        complete_flash(8'h05, DEFAULT_PARAMS, 1'b1, 1'b0);
        expect_response(response_base, 11,
            176'h55AA850500001C8264FB9C);
        if (load_en_count != pulse_base || params !== LOAD_PARAMS ||
            last_error !== 8'h05)
            fail("readback error overwrote parameters or lost status 05");
        $display("TEST_PASS: LOAD_FLASH propagates readback status 05");

        // No valid record returns defaults with status 06 and still loads them.
        response_base = tx_count;
        pulse_base = load_en_count;
        pulse_frame(8'h05, 8'h1D, 16'd0, 256'd0);
        wait_for_start(2'd2);
        complete_flash(8'h06, DEFAULT_PARAMS, 1'b1, 1'b0);
        expect_response(response_base, 22,
            176'h55AA85060B001D00050002000500E9030000DB959A68);
        if (load_en_count != pulse_base + 1 || params !== DEFAULT_PARAMS ||
            last_error !== 8'h06)
            fail("no-valid recovery did not install defaults with status 06");
        $display("TEST_PASS: LOAD_FLASH no-valid returns and installs defaults");

        // Status 06 without a published payload must use parameter_regs'
        // default path and still return the settled 11-byte defaults.
        response_base = tx_count;
        pulse_base = default_en_count;
        load_en_before = load_en_count;
        pulse_frame(8'h05, 8'h20, 16'd0, 256'd0);
        wait_for_start(2'd2);
        complete_flash(8'h06, INVALID_PARAMS, 1'b0, 1'b0);
        expect_response(response_base, 22,
            176'h55AA85060B002000050002000500E903000031A21CE2);
        if (default_en_count != pulse_base + 1 || load_en_count != load_en_before ||
            params !== DEFAULT_PARAMS || last_error !== 8'h06)
            fail("LOAD_FLASH 06 without result did not use defaults");
        $display("TEST_PASS: LOAD_FLASH status 06 without payload uses defaults");

        // LOAD_DEFAULT uses parameter_regs.default_en and returns settled data.
        response_base = tx_count;
        pulse_base = default_en_count;
        pulse_frame(8'h06, 8'h1E, 16'd0, 256'd0);
        expect_response(response_base, 22,
            176'h55AA86000B001E00050002000500E90300002B273614);
        if (default_en_count != pulse_base + 1 || params !== DEFAULT_PARAMS ||
            last_error !== 8'h00)
            fail("LOAD_DEFAULT did not use parameter_regs default path");
        $display("TEST_PASS: LOAD_DEFAULT returns settled default parameters");

        if (boot_start_count != 1)
            fail("automatic boot start was not a one-cycle one-shot");

        $display("TEST_PASS: all system controller tests passed");
        $finish(0);
    end

endmodule
