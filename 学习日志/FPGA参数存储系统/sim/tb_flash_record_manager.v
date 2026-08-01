`timescale 1ns / 1ps

module tb_flash_record_manager;

    localparam [23:0] SLOT_A_ADDR = 24'hFF0000;
    localparam [23:0] SLOT_B_ADDR = 24'hFF1000;
    localparam [87:0] DEFAULT_PARAMS = {
        32'd1001, 16'd5, 16'd2, 16'd5, 8'd0
    };

    localparam [7:0] ERROR_NONE           = 8'h00;
    localparam [7:0] ERROR_FLASH_TIMEOUT  = 8'h04;
    localparam [7:0] ERROR_READBACK       = 8'h05;
    localparam [7:0] ERROR_NO_VALID       = 8'h06;
    localparam integer MODEL_OPERATION_CYCLES = 80;

    reg         clk;
    reg         rst_n;
    reg         boot_start;
    reg         save_start;
    reg         load_start;
    reg  [87:0] current_params;
    wire [87:0] loaded_params;
    wire        params_valid;
    wire        active_slot;
    wire        busy;
    wire        done;
    wire [7:0]  error_code;
    wire        flash_cs_n;
    wire        flash_sck;
    wire        flash_mosi;
    reg         flash_miso;

    reg [7:0] flash_mem [0:8191];

    reg [7:0] model_shift;
    reg [7:0] model_command;
    reg [2:0] model_bit_index;
    integer   model_byte_count;
    reg [23:0] model_address;
    reg [23:0] model_program_start;
    integer   model_program_bytes;
    reg       model_output_active;
    reg [2:0] model_output_bit;
    reg [23:0] model_read_address;
    reg       model_wel;
    integer   model_busy_cycles;
    reg       force_stuck_wip;
    reg       force_corrupt_program;
    reg       force_reject_commit_program;
    reg [23:0] corrupt_address;
    reg       corrupt_applied;
    reg       protocol_error;
    reg       commit_program_seen;
    integer   read_transaction_count;
    integer   erase_transaction_count;
    integer   program_transaction_count;
    integer   status_transaction_count;
    integer   wren_transaction_count;

    integer i;
    reg [31:0] crc_value;
    reg [31:0] sequence_value;

    flash_record_manager #(
        .SPI_CLK_DIV         (1),
        .FLASH_TIMEOUT_POLLS (4)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .boot_start   (boot_start),
        .save_start   (save_start),
        .load_start   (load_start),
        .current_params(current_params),
        .loaded_params(loaded_params),
        .params_valid (params_valid),
        .active_slot  (active_slot),
        .busy         (busy),
        .done         (done),
        .error_code   (error_code),
        .flash_cs_n   (flash_cs_n),
        .flash_sck    (flash_sck),
        .flash_mosi   (flash_mosi),
        .flash_miso   (flash_miso)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    function integer mem_index;
        input [23:0] address;
        begin
            if (address >= SLOT_A_ADDR && address < SLOT_A_ADDR + 24'h002000)
                mem_index = address - SLOT_A_ADDR;
            else
                mem_index = -1;
        end
    endfunction

    function [7:0] memory_byte;
        input [23:0] address;
        integer index;
        begin
            index = mem_index(address);
            if (index >= 0 && index < 8192)
                memory_byte = flash_mem[index];
            else
                memory_byte = 8'hFF;
        end
    endfunction

    function [31:0] crc32_next_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_number;
        reg [31:0] work;
        begin
            work = crc_in ^ {24'd0, data_in};
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                if (work[0])
                    work = (work >> 1) ^ 32'hEDB88320;
                else
                    work = work >> 1;
            end
            crc32_next_byte = work;
        end
    endfunction

    function [31:0] record_crc;
        input [23:0] base_address;
        integer byte_number;
        reg [31:0] work;
        begin
            work = 32'hFFFFFFFF;
            for (byte_number = 0; byte_number < 28; byte_number = byte_number + 1) begin
                work = crc32_next_byte(work, memory_byte(base_address + byte_number));
            end
            record_crc = work ^ 32'hFFFFFFFF;
        end
    endfunction

    function [31:0] memory_u32_le;
        input [23:0] address;
        begin
            memory_u32_le = {
                memory_byte(address + 3),
                memory_byte(address + 2),
                memory_byte(address + 1),
                memory_byte(address)
            };
        end
    endfunction

    task automatic write_memory_byte;
        input [23:0] address;
        input [7:0] value;
        integer index;
        begin
            index = mem_index(address);
            if (index >= 0 && index < 8192)
                flash_mem[index] = value;
        end
    endtask

    task automatic clear_flash;
        begin
            for (i = 0; i < 8192; i = i + 1)
                flash_mem[i] = 8'hFF;
        end
    endtask

    task automatic reset_model_counters;
        begin
            protocol_error           = 1'b0;
            commit_program_seen      = 1'b0;
            read_transaction_count   = 0;
            erase_transaction_count  = 0;
            program_transaction_count = 0;
            status_transaction_count = 0;
            wren_transaction_count   = 0;
            force_stuck_wip          = 1'b0;
            force_corrupt_program    = 1'b0;
            force_reject_commit_program = 1'b0;
            corrupt_address          = 24'd0;
            corrupt_applied          = 1'b0;
            model_wel                = 1'b0;
            model_busy_cycles        = 0;
        end
    endtask

    task automatic build_record;
        input [23:0] base_address;
        input [31:0] seq_value;
        input [87:0] params;
        input        include_commit;
        input        corrupt_crc;
        integer byte_number;
        reg [31:0] calculated_crc;
        begin
            for (byte_number = 0; byte_number < 64; byte_number = byte_number + 1)
                write_memory_byte(base_address + byte_number, 8'h00);

            write_memory_byte(base_address + 0, 8'h41);
            write_memory_byte(base_address + 1, 8'h52);
            write_memory_byte(base_address + 2, 8'h41);
            write_memory_byte(base_address + 3, 8'h50);
            write_memory_byte(base_address + 4, 8'h01);
            write_memory_byte(base_address + 5, 8'h00);
            write_memory_byte(base_address + 6, 8'h00);
            write_memory_byte(base_address + 7, 8'h00);
            write_memory_byte(base_address + 8, seq_value[7:0]);
            write_memory_byte(base_address + 9, seq_value[15:8]);
            write_memory_byte(base_address + 10, seq_value[23:16]);
            write_memory_byte(base_address + 11, seq_value[31:24]);
            write_memory_byte(base_address + 12, 8'h0B);
            write_memory_byte(base_address + 13, 8'h00);
            write_memory_byte(base_address + 14, 8'h00);
            write_memory_byte(base_address + 15, 8'h00);
            for (byte_number = 0; byte_number < 11; byte_number = byte_number + 1)
                write_memory_byte(base_address + 16 + byte_number,
                                  params[byte_number * 8 +: 8]);
            write_memory_byte(base_address + 27, 8'h00);

            calculated_crc = record_crc(base_address);
            if (corrupt_crc)
                calculated_crc = calculated_crc ^ 32'h00000001;
            write_memory_byte(base_address + 28, calculated_crc[7:0]);
            write_memory_byte(base_address + 29, calculated_crc[15:8]);
            write_memory_byte(base_address + 30, calculated_crc[23:16]);
            write_memory_byte(base_address + 31, calculated_crc[31:24]);

            if (include_commit) begin
                write_memory_byte(base_address + 32, 8'hED);
                write_memory_byte(base_address + 33, 8'h5E);
                write_memory_byte(base_address + 34, 8'hA5);
                write_memory_byte(base_address + 35, 8'hC0);
            end
            else begin
                write_memory_byte(base_address + 32, 8'hFF);
                write_memory_byte(base_address + 33, 8'hFF);
                write_memory_byte(base_address + 34, 8'hFF);
                write_memory_byte(base_address + 35, 8'hFF);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            boot_start = 1'b0;
            save_start = 1'b0;
            load_start = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic pulse_and_wait;
        input [1:0] operation;
        begin
            @(negedge clk);
            case (operation)
                2'd0: boot_start = 1'b1;
                2'd1: save_start = 1'b1;
                default: load_start = 1'b1;
            endcase
            @(negedge clk);
            boot_start = 1'b0;
            save_start = 1'b0;
            load_start = 1'b0;
            wait (busy === 1'b1);
            wait (done === 1'b1);
            #1;
            if (busy !== 1'b0) begin
                $display("TEST_FAIL: manager stayed busy when done asserted");
                $finish(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic expect_result;
        input [87:0] expected_params;
        input        expected_slot;
        input [7:0]  expected_error;
        input [255:0] test_name;
        begin
            if (loaded_params !== expected_params ||
                params_valid !== 1'b1 ||
                active_slot !== expected_slot ||
                error_code !== expected_error) begin
                $display("TEST_FAIL: %0s params=%022h valid=%b slot=%b error=%02h",
                    test_name, loaded_params, params_valid, active_slot, error_code);
                $display("DIAG: A magic=%02h%02h%02h%02h seq=%02h%02h%02h%02h stored_crc=%02h%02h%02h%02h commit=%02h%02h%02h%02h valid=%b",
                    dut.slot_a_record[3], dut.slot_a_record[2],
                    dut.slot_a_record[1], dut.slot_a_record[0],
                    dut.slot_a_record[11], dut.slot_a_record[10],
                    dut.slot_a_record[9], dut.slot_a_record[8],
                    dut.slot_a_record[31], dut.slot_a_record[30],
                    dut.slot_a_record[29], dut.slot_a_record[28],
                    dut.slot_a_record[35], dut.slot_a_record[34],
                    dut.slot_a_record[33], dut.slot_a_record[32],
                    dut.slot_a_valid);
                $display("DIAG: B magic=%02h%02h%02h%02h seq=%02h%02h%02h%02h stored_crc=%02h%02h%02h%02h commit=%02h%02h%02h%02h valid=%b reads=%0d",
                    dut.slot_b_record[3], dut.slot_b_record[2],
                    dut.slot_b_record[1], dut.slot_b_record[0],
                    dut.slot_b_record[11], dut.slot_b_record[10],
                    dut.slot_b_record[9], dut.slot_b_record[8],
                    dut.slot_b_record[31], dut.slot_b_record[30],
                    dut.slot_b_record[29], dut.slot_b_record[28],
                    dut.slot_b_record[35], dut.slot_b_record[34],
                    dut.slot_b_record[33], dut.slot_b_record[32],
                    dut.slot_b_valid, read_transaction_count);
                $display("DIAG: model A crc stored=%08h calculated=%08h; model B crc stored=%08h calculated=%08h; crc_result=%08h",
                    memory_u32_le(SLOT_A_ADDR + 24'h1C),
                    record_crc(SLOT_A_ADDR),
                    memory_u32_le(SLOT_B_ADDR + 24'h1C),
                    record_crc(SLOT_B_ADDR), dut.crc_result);
                $finish(1);
            end
            $display("TEST_PASS: %0s", test_name);
        end
    endtask

    // A low CS starts a fresh pin-level SPI transaction.
    always @(negedge flash_cs_n) begin
        model_shift          = 8'd0;
        model_command        = 8'd0;
        model_bit_index      = 3'd0;
        model_byte_count     = 0;
        model_address        = 24'd0;
        model_program_start  = 24'd0;
        model_program_bytes  = 0;
        model_output_active  = 1'b0;
        model_output_bit     = 3'd7;
        model_read_address   = 24'd0;
        flash_miso           = 1'b0;
    end

    // SPI Mode 0: the Flash samples MOSI on each rising edge.
    always @(posedge flash_sck) begin
        integer index;
        reg [7:0] complete_byte;
        if (!flash_cs_n) begin
            complete_byte = {model_shift[6:0], flash_mosi};
            model_shift = complete_byte;
            if (model_bit_index == 3'd7) begin
                if (model_byte_count == 0) begin
                    model_command = complete_byte;
                end
                else if (model_byte_count == 1) begin
                    model_address[23:16] = complete_byte;
                end
                else if (model_byte_count == 2) begin
                    model_address[15:8] = complete_byte;
                end
                else if (model_byte_count == 3) begin
                    model_address[7:0] = complete_byte;
                    model_program_start = {
                        model_address[23:8], complete_byte
                    };
                    model_read_address = {
                        model_address[23:8], complete_byte
                    };
                end
                else if (model_command == 8'h02) begin
                    if (model_wel && model_busy_cycles == 0) begin
                        if (!(force_reject_commit_program &&
                              (model_program_start ==
                                   SLOT_A_ADDR + 24'h20 ||
                               model_program_start ==
                                   SLOT_B_ADDR + 24'h20))) begin
                            index = mem_index(model_address);
                            if (index >= 0 && index < 8192)
                                flash_mem[index] =
                                    flash_mem[index] & complete_byte;
                        end
                        model_address = model_address + 1'b1;
                        model_program_bytes = model_program_bytes + 1;
                    end
                end

                model_byte_count = model_byte_count + 1;
                model_bit_index = 3'd0;
                model_shift = 8'd0;
            end
            else begin
                model_bit_index = model_bit_index + 1'b1;
            end
        end
    end

    // SPI Mode 0: the Flash changes MISO on falling edges.
    always @(negedge flash_sck) begin
        reg [7:0] response_byte;
        if (!flash_cs_n) begin
            if (!model_output_active) begin
                if (model_command == 8'h05 && model_byte_count >= 1) begin
                    response_byte = {
                        6'd0, model_wel,
                        (force_stuck_wip || model_busy_cycles > 0)
                    };
                    flash_miso = response_byte[7];
                    model_output_bit = 3'd7;
                    model_output_active = 1'b1;
                end
                else if (model_command == 8'h03 && model_byte_count >= 4 &&
                         !force_stuck_wip && model_busy_cycles == 0) begin
                    response_byte = memory_byte(model_read_address);
                    flash_miso = response_byte[7];
                    model_output_bit = 3'd7;
                    model_output_active = 1'b1;
                end
            end
            else begin
                if (model_output_bit == 0) begin
                    model_output_bit = 3'd7;
                    if (model_command == 8'h03) begin
                        model_read_address = model_read_address + 1'b1;
                        response_byte = memory_byte(model_read_address);
                    end
                    else begin
                        response_byte = {
                            6'd0, model_wel,
                            (force_stuck_wip || model_busy_cycles > 0)
                        };
                    end
                    flash_miso = response_byte[7];
                end
                else begin
                    model_output_bit = model_output_bit - 1'b1;
                    if (model_command == 8'h03)
                        response_byte = memory_byte(model_read_address);
                    else
                        response_byte = {
                            6'd0, model_wel,
                            (force_stuck_wip || model_busy_cycles > 0)
                        };
                    flash_miso = response_byte[model_output_bit];
                end
            end
        end
    end

    // Complete mutating commands only when CS rises.
    always @(posedge flash_cs_n) begin
        integer sector_index;
        integer byte_number;
        if (rst_n) begin
            case (model_command)
                8'h06: begin
                    wren_transaction_count = wren_transaction_count + 1;
                    if (!force_stuck_wip && model_busy_cycles == 0)
                        model_wel = 1'b1;
                end

                8'h20: begin
                    erase_transaction_count = erase_transaction_count + 1;
                    if (!model_wel || force_stuck_wip ||
                        model_busy_cycles != 0)
                        protocol_error = 1'b1;
                    else begin
                        sector_index = mem_index({model_address[23:12], 12'd0});
                        if (sector_index >= 0) begin
                            for (byte_number = 0; byte_number < 4096;
                                 byte_number = byte_number + 1)
                                flash_mem[sector_index + byte_number] = 8'hFF;
                        end
                        model_busy_cycles = MODEL_OPERATION_CYCLES;
                    end
                    model_wel = 1'b0;
                end

                8'h02: begin
                    program_transaction_count = program_transaction_count + 1;
                    if (!model_wel || force_stuck_wip ||
                        model_busy_cycles != 0 ||
                        model_program_bytes < 1 || model_program_bytes > 4)
                        protocol_error = 1'b1;
                    if (model_program_start == SLOT_A_ADDR + 24'h20 ||
                        model_program_start == SLOT_B_ADDR + 24'h20) begin
                        if (model_program_bytes != 4)
                            protocol_error = 1'b1;
                        commit_program_seen = 1'b1;
                    end
                    else if (commit_program_seen) begin
                        protocol_error = 1'b1;
                    end
                    if (force_corrupt_program && !corrupt_applied &&
                        corrupt_address >= model_program_start &&
                        corrupt_address < model_program_start +
                                          model_program_bytes) begin
                        byte_number = mem_index(corrupt_address);
                        flash_mem[byte_number] =
                            flash_mem[byte_number] ^ 8'h01;
                        corrupt_applied = 1'b1;
                    end
                    if (model_wel && !force_stuck_wip &&
                        model_busy_cycles == 0)
                        model_busy_cycles = MODEL_OPERATION_CYCLES;
                    model_wel = 1'b0;
                end

                8'h03: read_transaction_count = read_transaction_count + 1;

                8'h05: begin
                    status_transaction_count = status_transaction_count + 1;
                end
                default: ;
            endcase
        end
        flash_miso = 1'b0;
    end

    // Flash self-timed erase/program continues independently of FPGA reset.
    always @(posedge clk) begin
        if (!force_stuck_wip && model_busy_cycles > 0)
            model_busy_cycles = model_busy_cycles - 1;
    end

    initial begin
        #5_000_000;
        $display("TEST_FAIL: flash record manager test timeout");
        $finish(1);
    end

    initial begin
        reg [87:0] params_a;
        reg [87:0] params_b;
        reg [87:0] params_new;
        integer programs_before_interrupt;

        rst_n = 1'b0;
        boot_start = 1'b0;
        save_start = 1'b0;
        load_start = 1'b0;
        current_params = DEFAULT_PARAMS;
        flash_miso = 1'b0;
        model_wel = 1'b0;
        model_busy_cycles = 0;

        params_a   = {32'h11223344, 16'd30, 16'd4, 16'd20, 8'd1};
        params_b   = {32'h55667788, 16'd45, 16'd5, 16'd25, 8'd0};
        params_new = {32'hA1B2C3D4, 16'd60, 16'd6, 16'd35, 8'd1};

        // Both erased records are invalid: boot restores defaults and reports 06.
        clear_flash();
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        expect_result(DEFAULT_PARAMS, 1'b0, ERROR_NO_VALID,
                      "invalid A/B restore defaults");

        // Two valid records select the larger sequence.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd7, params_a, 1'b1, 1'b0);
        build_record(SLOT_B_ADDR, 32'd12, params_b, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd2);
        expect_result(params_b, 1'b1, ERROR_NONE,
                      "two valid records select newest");

        // A single valid record is selected.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd3, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd2);
        expect_result(params_a, 1'b0, ERROR_NONE,
                      "single valid A record selected");

        // A newer CRC-corrupt B record must not displace valid A.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd4, params_a, 1'b1, 1'b0);
        build_record(SLOT_B_ADDR, 32'd99, params_b, 1'b1, 1'b1);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd2);
        expect_result(params_a, 1'b0, ERROR_NONE,
                      "CRC error rejected");

        // A record without COMMIT is invalid even when its CRC is correct.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd8, params_a, 1'b0, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd2);
        expect_result(DEFAULT_PARAMS, 1'b0, ERROR_NO_VALID,
                      "missing COMMIT rejected");

        // Boot/load must not issue READ while WIP is stuck. The same bounded
        // poll budget used by writes must terminate startup with error 04.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd49, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        force_stuck_wip = 1'b1;
        pulse_and_wait(2'd0);
        if (error_code !== ERROR_FLASH_TIMEOUT ||
            status_transaction_count != 4 ||
            read_transaction_count != 0) begin
            $display("TEST_FAIL: boot WIP timeout error=%02h polls=%0d reads=%0d",
                error_code, status_transaction_count,
                read_transaction_count);
            $finish(1);
        end
        $display("TEST_PASS: boot WIP timeout occurs before any record read");

        // A direct save after manager reset must scan first. With only A valid,
        // preserving A requires selecting inactive B and sequence 51.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd50, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        current_params = params_new;
        pulse_and_wait(2'd1);
        if (error_code !== ERROR_NONE || active_slot !== 1'b1 ||
            memory_u32_le(SLOT_A_ADDR + 24'h20) !== 32'hC0A55EED ||
            memory_u32_le(SLOT_B_ADDR + 24'h08) !== 32'd51 ||
            memory_u32_le(SLOT_B_ADDR + 24'h20) !== 32'hC0A55EED) begin
            $display("TEST_FAIL: direct save did not scan first slot=%b error=%02h Acommit=%08h Bseq=%0d Bcommit=%08h",
                active_slot, error_code,
                memory_u32_le(SLOT_A_ADDR + 24'h20),
                memory_u32_le(SLOT_B_ADDR + 24'h08),
                memory_u32_le(SLOT_B_ADDR + 24'h20));
            $finish(1);
        end
        $display("TEST_PASS: direct save scans slots and preserves sole valid A");

        // Save must erase/program inactive B, increment sequence, verify, then
        // program COMMIT last. A load pulse while busy must be ignored.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd5, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        current_params = params_new;
        @(negedge clk);
        save_start = 1'b1;
        @(negedge clk);
        save_start = 1'b0;
        wait (busy === 1'b1);
        @(negedge clk);
        load_start = 1'b1;
        @(negedge clk);
        load_start = 1'b0;
        wait (done === 1'b1);
        @(negedge clk);

        sequence_value = memory_u32_le(SLOT_B_ADDR + 24'h08);
        crc_value = record_crc(SLOT_B_ADDR);
        if (active_slot !== 1'b1 || error_code !== ERROR_NONE ||
            sequence_value !== 32'd6 ||
            memory_u32_le(SLOT_B_ADDR + 24'h1C) !== crc_value ||
            memory_u32_le(SLOT_B_ADDR + 24'h20) !== 32'hC0A55EED ||
            protocol_error || !commit_program_seen) begin
            $display("TEST_FAIL: save inactive B seq=%0d crc=%08h stored=%08h commit=%08h protocol=%b",
                sequence_value, crc_value,
                memory_u32_le(SLOT_B_ADDR + 24'h1C),
                memory_u32_le(SLOT_B_ADDR + 24'h20), protocol_error);
            $finish(1);
        end
        for (i = 0; i < 11; i = i + 1) begin
            if (memory_byte(SLOT_B_ADDR + 16 + i) !==
                params_new[i * 8 +: 8]) begin
                $display("TEST_FAIL: saved parameter byte %0d mismatch", i);
                $finish(1);
            end
        end
        $display("TEST_PASS: save targets inactive slot with sequence+1 and COMMIT last");

        // Corruption injected into a page-program transaction must be caught by
        // readback verification, leaving A active and B uncommitted.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd20, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        current_params = params_new;
        force_corrupt_program = 1'b1;
        corrupt_address = SLOT_B_ADDR + 24'h10;
        pulse_and_wait(2'd1);
        if (error_code !== ERROR_READBACK || active_slot !== 1'b0 ||
            memory_u32_le(SLOT_B_ADDR + 24'h20) === 32'hC0A55EED ||
            !corrupt_applied) begin
            $display("TEST_FAIL: readback mismatch error=%02h slot=%b commit=%08h corrupt=%b",
                error_code, active_slot,
                memory_u32_le(SLOT_B_ADDR + 24'h20), corrupt_applied);
            $finish(1);
        end
        $display("TEST_PASS: readback mismatch leaves old slot active");

        // COMMIT itself must be read back. A rejected COMMIT program cannot
        // switch the active slot or report save success.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd25, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        current_params = params_new;
        force_reject_commit_program = 1'b1;
        pulse_and_wait(2'd1);
        if (error_code !== ERROR_READBACK || active_slot !== 1'b0 ||
            loaded_params !== params_a ||
            memory_u32_le(SLOT_B_ADDR + 24'h20) === 32'hC0A55EED ||
            !commit_program_seen) begin
            $display("TEST_FAIL: rejected COMMIT error=%02h slot=%b loaded=%022h commit=%08h seen=%b",
                error_code, active_slot, loaded_params,
                memory_u32_le(SLOT_B_ADDR + 24'h20),
                commit_program_seen);
            $finish(1);
        end
        $display("TEST_PASS: rejected COMMIT readback leaves old slot active");

        // A permanently busy Flash must terminate with timeout rather than hang.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd30, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        current_params = params_new;
        status_transaction_count = 0;
        force_stuck_wip = 1'b1;
        pulse_and_wait(2'd1);
        if (error_code !== ERROR_FLASH_TIMEOUT || active_slot !== 1'b0 ||
            status_transaction_count != 4) begin
            $display("TEST_FAIL: timeout error=%02h slot=%b polls=%0d",
                error_code, active_slot, status_transaction_count);
            $finish(1);
        end
        $display("TEST_PASS: Flash WIP timeout bounded at configured poll count");

        // Reset the FPGA while a Flash self-timed program is still busy. The
        // operation continues independently; boot must wait for WIP=0 and then
        // recover old A because B still has no COMMIT.
        clear_flash();
        build_record(SLOT_A_ADDR, 32'd40, params_a, 1'b1, 1'b0);
        reset_model_counters();
        reset_dut();
        pulse_and_wait(2'd0);
        current_params = params_new;
        programs_before_interrupt = program_transaction_count;
        @(negedge clk);
        save_start = 1'b1;
        @(negedge clk);
        save_start = 1'b0;
        wait (program_transaction_count >= programs_before_interrupt + 2);
        if (model_busy_cycles <= 0) begin
            $display("TEST_FAIL: reset-busy fixture missed Flash WIP window");
            $finish(1);
        end
        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        if (memory_u32_le(SLOT_B_ADDR + 24'h20) === 32'hC0A55EED) begin
            $display("TEST_FAIL: interrupted save wrote COMMIT too early");
            $finish(1);
        end
        force_stuck_wip = 1'b0;
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        pulse_and_wait(2'd0);
        expect_result(params_a, 1'b0, ERROR_NONE,
                      "reset-busy boot preserves old A");

        $display("TEST_PASS: all flash record manager tests passed");
        $finish(0);
    end

endmodule
