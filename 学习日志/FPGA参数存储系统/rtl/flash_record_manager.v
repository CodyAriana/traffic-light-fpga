`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Dual-slot SPI NOR Flash record manager
//
// Record words and the 11-byte parameter payload are stored least-significant
// byte first. Reads use eight-byte chunks. Page-program transactions carry four
// data bytes so the complete command, address, and data fit spi_flash_xfer's
// 64-bit transmit port.
// -----------------------------------------------------------------------------
module flash_record_manager #(
    parameter integer SPI_CLK_DIV = 4,
    parameter integer FLASH_TIMEOUT_POLLS = 500000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        boot_start,
    input  wire        save_start,
    input  wire        load_start,
    input  wire [87:0] current_params,
    output reg  [87:0] loaded_params,
    output reg         params_valid,
    output reg         active_slot,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  error_code,
    output wire        flash_cs_n,
    output wire        flash_sck,
    output wire        flash_mosi,
    input  wire        flash_miso
);

    localparam [23:0] SLOT_A_ADDR = 24'hFF0000;
    localparam [23:0] SLOT_B_ADDR = 24'hFF1000;

    localparam [87:0] DEFAULT_PARAMS = {
        32'd1001, 16'd5, 16'd2, 16'd5, 8'd0
    };

    localparam [7:0] ERROR_NONE          = 8'h00;
    localparam [7:0] ERROR_FLASH_TIMEOUT = 8'h04;
    localparam [7:0] ERROR_READBACK      = 8'h05;
    localparam [7:0] ERROR_NO_VALID      = 8'h06;

    localparam [6:0]
        ST_IDLE                 = 7'd0,
        ST_READ_A_ISSUE         = 7'd1,
        ST_READ_A_WAIT          = 7'd2,
        ST_CRC_A_START          = 7'd3,
        ST_CRC_A_FEED           = 7'd4,
        ST_CRC_A_FINISH         = 7'd5,
        ST_CRC_A_WAIT           = 7'd6,
        ST_READ_B_ISSUE         = 7'd7,
        ST_READ_B_WAIT          = 7'd8,
        ST_CRC_B_START          = 7'd9,
        ST_CRC_B_FEED           = 7'd10,
        ST_CRC_B_FINISH         = 7'd11,
        ST_CRC_B_WAIT           = 7'd12,
        ST_SELECT_RECORD        = 7'd13,
        ST_SAVE_BUILD           = 7'd14,
        ST_SAVE_CRC_START       = 7'd15,
        ST_SAVE_CRC_FEED        = 7'd16,
        ST_SAVE_CRC_FINISH      = 7'd17,
        ST_SAVE_CRC_WAIT        = 7'd18,
        ST_ERASE_WREN_ISSUE     = 7'd19,
        ST_ERASE_WREN_WAIT      = 7'd20,
        ST_ERASE_ISSUE          = 7'd21,
        ST_ERASE_WAIT           = 7'd22,
        ST_ERASE_STATUS_ISSUE   = 7'd23,
        ST_ERASE_STATUS_WAIT    = 7'd24,
        ST_PROGRAM_WREN_ISSUE   = 7'd25,
        ST_PROGRAM_WREN_WAIT    = 7'd26,
        ST_PROGRAM_ISSUE        = 7'd27,
        ST_PROGRAM_WAIT         = 7'd28,
        ST_PROGRAM_STATUS_ISSUE = 7'd29,
        ST_PROGRAM_STATUS_WAIT  = 7'd30,
        ST_VERIFY_READ_ISSUE    = 7'd31,
        ST_VERIFY_READ_WAIT     = 7'd32,
        ST_VERIFY_CRC_START     = 7'd33,
        ST_VERIFY_CRC_FEED      = 7'd34,
        ST_VERIFY_CRC_FINISH    = 7'd35,
        ST_VERIFY_CRC_WAIT      = 7'd36,
        ST_VERIFY_CHECK         = 7'd37,
        ST_COMMIT_WREN_ISSUE    = 7'd38,
        ST_COMMIT_WREN_WAIT     = 7'd39,
        ST_COMMIT_ISSUE         = 7'd40,
        ST_COMMIT_WAIT          = 7'd41,
        ST_COMMIT_STATUS_ISSUE  = 7'd42,
        ST_COMMIT_STATUS_WAIT   = 7'd43,
        ST_SAVE_SUCCESS         = 7'd44,
        ST_OPERATION_ERROR      = 7'd45,
        ST_PRECHECK_STATUS_ISSUE = 7'd46,
        ST_PRECHECK_STATUS_WAIT = 7'd47,
        ST_SAVE_SETUP           = 7'd48,
        ST_COMMIT_READ_ISSUE    = 7'd49,
        ST_COMMIT_READ_WAIT     = 7'd50;

    reg [6:0] state;

    reg        spi_start;
    reg [63:0] spi_tx_bytes;
    reg [3:0]  spi_tx_count;
    reg [3:0]  spi_rx_count;
    wire       spi_busy;
    wire       spi_done;
    wire [63:0] spi_rx_bytes;

    reg        crc_start;
    reg        crc_data_valid;
    reg [7:0]  crc_data_byte;
    reg        crc_finish;
    wire       crc_busy;
    wire       crc_done;
    wire [31:0] crc_result;

    reg [7:0] slot_a_record [0:63];
    reg [7:0] slot_b_record [0:63];
    reg [7:0] write_record  [0:63];
    reg [7:0] verify_record [0:63];

    reg [6:0] read_offset;
    reg [5:0] crc_index;
    reg [5:0] program_offset;
    reg [31:0] poll_count;
    reg [23:0] target_base;
    reg        target_slot;
    reg [31:0] new_sequence;
    wire [23:0] slot_a_read_address;
    wire [23:0] slot_b_read_address;
    wire [23:0] target_read_address;
    wire [23:0] target_program_address;
    wire [23:0] target_commit_address;

    reg        slot_a_valid;
    reg        slot_b_valid;
    reg [31:0] slot_a_sequence;
    reg [31:0] slot_b_sequence;
    reg [87:0] slot_a_params;
    reg [87:0] slot_b_params;
    reg        have_active_record;
    reg [31:0] active_sequence;
    reg        scan_complete;
    reg        pending_save;

    integer array_index;
    reg verify_mismatch;

    assign slot_a_read_address  = SLOT_A_ADDR + read_offset;
    assign slot_b_read_address  = SLOT_B_ADDR + read_offset;
    assign target_read_address  = target_base + read_offset;
    assign target_program_address = target_base + program_offset;
    assign target_commit_address  = target_base + 24'h000020;

    spi_flash_xfer #(
        .CLK_DIV (SPI_CLK_DIV)
    ) spi_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (spi_start),
        .tx_bytes   (spi_tx_bytes),
        .tx_count   (spi_tx_count),
        .rx_count   (spi_rx_count),
        .busy       (spi_busy),
        .done       (spi_done),
        .rx_bytes   (spi_rx_bytes),
        .flash_cs_n (flash_cs_n),
        .flash_sck  (flash_sck),
        .flash_mosi (flash_mosi),
        .flash_miso (flash_miso)
    );

    crc32 crc_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (crc_start),
        .data_valid (crc_data_valid),
        .data_byte  (crc_data_byte),
        .finish     (crc_finish),
        .busy       (crc_busy),
        .done       (crc_done),
        .crc        (crc_result)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            spi_start          <= 1'b0;
            spi_tx_bytes       <= 64'd0;
            spi_tx_count       <= 4'd0;
            spi_rx_count       <= 4'd0;
            crc_start          <= 1'b0;
            crc_data_valid     <= 1'b0;
            crc_data_byte      <= 8'd0;
            crc_finish         <= 1'b0;
            read_offset        <= 7'd0;
            crc_index          <= 6'd0;
            program_offset     <= 6'd0;
            poll_count         <= 32'd0;
            target_base        <= SLOT_A_ADDR;
            target_slot        <= 1'b0;
            new_sequence       <= 32'd1;
            slot_a_valid       <= 1'b0;
            slot_b_valid       <= 1'b0;
            slot_a_sequence    <= 32'd0;
            slot_b_sequence    <= 32'd0;
            slot_a_params      <= DEFAULT_PARAMS;
            slot_b_params      <= DEFAULT_PARAMS;
            have_active_record <= 1'b0;
            active_sequence    <= 32'd0;
            scan_complete      <= 1'b0;
            pending_save       <= 1'b0;
            loaded_params      <= DEFAULT_PARAMS;
            params_valid       <= 1'b1;
            active_slot        <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
            error_code         <= ERROR_NONE;
        end
        else begin
            spi_start      <= 1'b0;
            crc_start      <= 1'b0;
            crc_data_valid <= 1'b0;
            crc_finish     <= 1'b0;
            done           <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (boot_start || load_start) begin
                        busy         <= 1'b1;
                        error_code   <= ERROR_NONE;
                        pending_save <= 1'b0;
                        poll_count   <= 32'd0;
                        state        <= ST_PRECHECK_STATUS_ISSUE;
                    end
                    else if (save_start) begin
                        busy         <= 1'b1;
                        error_code   <= ERROR_NONE;
                        pending_save <= 1'b1;
                        poll_count   <= 32'd0;
                        state        <= ST_PRECHECK_STATUS_ISSUE;
                    end
                end

                ST_PRECHECK_STATUS_ISSUE: begin
                    spi_tx_bytes <= {8'h05, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd1;
                    spi_start    <= 1'b1;
                    state        <= ST_PRECHECK_STATUS_WAIT;
                end

                ST_PRECHECK_STATUS_WAIT: begin
                    if (spi_done) begin
                        if (spi_rx_bytes[56]) begin
                            if (poll_count + 1 >= FLASH_TIMEOUT_POLLS) begin
                                error_code <= ERROR_FLASH_TIMEOUT;
                                state      <= ST_OPERATION_ERROR;
                            end
                            else begin
                                poll_count <= poll_count + 1'b1;
                                state      <= ST_PRECHECK_STATUS_ISSUE;
                            end
                        end
                        else if (pending_save && scan_complete) begin
                            state <= ST_SAVE_SETUP;
                        end
                        else begin
                            slot_a_valid <= 1'b0;
                            slot_b_valid <= 1'b0;
                            scan_complete <= 1'b0;
                            read_offset  <= 7'd0;
                            state        <= ST_READ_A_ISSUE;
                        end
                    end
                end

                ST_SAVE_SETUP: begin
                    pending_save <= 1'b0;
                    error_code   <= ERROR_NONE;
                    if (have_active_record) begin
                        target_slot  <= ~active_slot;
                        new_sequence <= active_sequence + 1'b1;
                        if (active_slot)
                            target_base <= SLOT_A_ADDR;
                        else
                            target_base <= SLOT_B_ADDR;
                    end
                    else begin
                        target_slot  <= 1'b0;
                        target_base  <= SLOT_A_ADDR;
                        new_sequence <= 32'd1;
                    end
                    state <= ST_SAVE_BUILD;
                end

                ST_READ_A_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h03,
                        slot_a_read_address[23:16],
                        slot_a_read_address[15:8],
                        slot_a_read_address[7:0],
                        32'd0
                    };
                    spi_tx_count <= 4'd4;
                    spi_rx_count <= 4'd8;
                    spi_start    <= 1'b1;
                    state        <= ST_READ_A_WAIT;
                end

                ST_READ_A_WAIT: begin
                    if (spi_done) begin
                        slot_a_record[read_offset]     <= spi_rx_bytes[63:56];
                        slot_a_record[read_offset + 1] <= spi_rx_bytes[55:48];
                        slot_a_record[read_offset + 2] <= spi_rx_bytes[47:40];
                        slot_a_record[read_offset + 3] <= spi_rx_bytes[39:32];
                        slot_a_record[read_offset + 4] <= spi_rx_bytes[31:24];
                        slot_a_record[read_offset + 5] <= spi_rx_bytes[23:16];
                        slot_a_record[read_offset + 6] <= spi_rx_bytes[15:8];
                        slot_a_record[read_offset + 7] <= spi_rx_bytes[7:0];
                        if (read_offset == 7'd56) begin
                            crc_index <= 6'd0;
                            state     <= ST_CRC_A_START;
                        end
                        else begin
                            read_offset <= read_offset + 7'd8;
                            state       <= ST_READ_A_ISSUE;
                        end
                    end
                end

                ST_CRC_A_START: begin
                    crc_start <= 1'b1;
                    crc_index <= 6'd0;
                    state     <= ST_CRC_A_FEED;
                end

                ST_CRC_A_FEED: begin
                    crc_data_valid <= 1'b1;
                    crc_data_byte  <= slot_a_record[crc_index];
                    if (crc_index == 6'd27)
                        state <= ST_CRC_A_FINISH;
                    else
                        crc_index <= crc_index + 1'b1;
                end

                ST_CRC_A_FINISH: begin
                    crc_finish <= 1'b1;
                    state      <= ST_CRC_A_WAIT;
                end

                ST_CRC_A_WAIT: begin
                    if (crc_done) begin
                        slot_a_sequence <= {
                            slot_a_record[11], slot_a_record[10],
                            slot_a_record[9], slot_a_record[8]
                        };
                        slot_a_params <= {
                            slot_a_record[26], slot_a_record[25],
                            slot_a_record[24], slot_a_record[23],
                            slot_a_record[22], slot_a_record[21],
                            slot_a_record[20], slot_a_record[19],
                            slot_a_record[18], slot_a_record[17],
                            slot_a_record[16]
                        };
                        slot_a_valid <=
                            ({slot_a_record[3], slot_a_record[2],
                              slot_a_record[1], slot_a_record[0]} ==
                             32'h50415241) &&
                            (slot_a_record[4] == 8'h01) &&
                            ({slot_a_record[13], slot_a_record[12]} ==
                             16'd11) &&
                            ({slot_a_record[35], slot_a_record[34],
                              slot_a_record[33], slot_a_record[32]} ==
                             32'hC0A55EED) &&
                            ({slot_a_record[31], slot_a_record[30],
                              slot_a_record[29], slot_a_record[28]} ==
                             crc_result);
                        read_offset <= 7'd0;
                        state       <= ST_READ_B_ISSUE;
                    end
                end

                ST_READ_B_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h03,
                        slot_b_read_address[23:16],
                        slot_b_read_address[15:8],
                        slot_b_read_address[7:0],
                        32'd0
                    };
                    spi_tx_count <= 4'd4;
                    spi_rx_count <= 4'd8;
                    spi_start    <= 1'b1;
                    state        <= ST_READ_B_WAIT;
                end

                ST_READ_B_WAIT: begin
                    if (spi_done) begin
                        slot_b_record[read_offset]     <= spi_rx_bytes[63:56];
                        slot_b_record[read_offset + 1] <= spi_rx_bytes[55:48];
                        slot_b_record[read_offset + 2] <= spi_rx_bytes[47:40];
                        slot_b_record[read_offset + 3] <= spi_rx_bytes[39:32];
                        slot_b_record[read_offset + 4] <= spi_rx_bytes[31:24];
                        slot_b_record[read_offset + 5] <= spi_rx_bytes[23:16];
                        slot_b_record[read_offset + 6] <= spi_rx_bytes[15:8];
                        slot_b_record[read_offset + 7] <= spi_rx_bytes[7:0];
                        if (read_offset == 7'd56) begin
                            crc_index <= 6'd0;
                            state     <= ST_CRC_B_START;
                        end
                        else begin
                            read_offset <= read_offset + 7'd8;
                            state       <= ST_READ_B_ISSUE;
                        end
                    end
                end

                ST_CRC_B_START: begin
                    crc_start <= 1'b1;
                    crc_index <= 6'd0;
                    state     <= ST_CRC_B_FEED;
                end

                ST_CRC_B_FEED: begin
                    crc_data_valid <= 1'b1;
                    crc_data_byte  <= slot_b_record[crc_index];
                    if (crc_index == 6'd27)
                        state <= ST_CRC_B_FINISH;
                    else
                        crc_index <= crc_index + 1'b1;
                end

                ST_CRC_B_FINISH: begin
                    crc_finish <= 1'b1;
                    state      <= ST_CRC_B_WAIT;
                end

                ST_CRC_B_WAIT: begin
                    if (crc_done) begin
                        slot_b_sequence <= {
                            slot_b_record[11], slot_b_record[10],
                            slot_b_record[9], slot_b_record[8]
                        };
                        slot_b_params <= {
                            slot_b_record[26], slot_b_record[25],
                            slot_b_record[24], slot_b_record[23],
                            slot_b_record[22], slot_b_record[21],
                            slot_b_record[20], slot_b_record[19],
                            slot_b_record[18], slot_b_record[17],
                            slot_b_record[16]
                        };
                        slot_b_valid <=
                            ({slot_b_record[3], slot_b_record[2],
                              slot_b_record[1], slot_b_record[0]} ==
                             32'h50415241) &&
                            (slot_b_record[4] == 8'h01) &&
                            ({slot_b_record[13], slot_b_record[12]} ==
                             16'd11) &&
                            ({slot_b_record[35], slot_b_record[34],
                              slot_b_record[33], slot_b_record[32]} ==
                             32'hC0A55EED) &&
                            ({slot_b_record[31], slot_b_record[30],
                              slot_b_record[29], slot_b_record[28]} ==
                             crc_result);
                        state <= ST_SELECT_RECORD;
                    end
                end

                ST_SELECT_RECORD: begin
                    scan_complete <= 1'b1;
                    params_valid <= 1'b1;
                    if (slot_a_valid && slot_b_valid) begin
                        have_active_record <= 1'b1;
                        error_code         <= ERROR_NONE;
                        if (slot_b_sequence > slot_a_sequence) begin
                            loaded_params   <= slot_b_params;
                            active_slot     <= 1'b1;
                            active_sequence <= slot_b_sequence;
                        end
                        else begin
                            loaded_params   <= slot_a_params;
                            active_slot     <= 1'b0;
                            active_sequence <= slot_a_sequence;
                        end
                    end
                    else if (slot_a_valid) begin
                        have_active_record <= 1'b1;
                        error_code         <= ERROR_NONE;
                        loaded_params      <= slot_a_params;
                        active_slot        <= 1'b0;
                        active_sequence    <= slot_a_sequence;
                    end
                    else if (slot_b_valid) begin
                        have_active_record <= 1'b1;
                        error_code         <= ERROR_NONE;
                        loaded_params      <= slot_b_params;
                        active_slot        <= 1'b1;
                        active_sequence    <= slot_b_sequence;
                    end
                    else begin
                        have_active_record <= 1'b0;
                        error_code         <= ERROR_NO_VALID;
                        loaded_params      <= DEFAULT_PARAMS;
                        active_slot        <= 1'b0;
                        active_sequence    <= 32'd0;
                    end
                    if (pending_save) begin
                        state <= ST_SAVE_SETUP;
                    end
                    else begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_SAVE_BUILD: begin
                    for (array_index = 0; array_index < 64;
                         array_index = array_index + 1)
                        write_record[array_index] <= 8'h00;

                    write_record[0]  <= 8'h41;
                    write_record[1]  <= 8'h52;
                    write_record[2]  <= 8'h41;
                    write_record[3]  <= 8'h50;
                    write_record[4]  <= 8'h01;
                    write_record[8]  <= new_sequence[7:0];
                    write_record[9]  <= new_sequence[15:8];
                    write_record[10] <= new_sequence[23:16];
                    write_record[11] <= new_sequence[31:24];
                    write_record[12] <= 8'h0B;
                    write_record[16] <= current_params[7:0];
                    write_record[17] <= current_params[15:8];
                    write_record[18] <= current_params[23:16];
                    write_record[19] <= current_params[31:24];
                    write_record[20] <= current_params[39:32];
                    write_record[21] <= current_params[47:40];
                    write_record[22] <= current_params[55:48];
                    write_record[23] <= current_params[63:56];
                    write_record[24] <= current_params[71:64];
                    write_record[25] <= current_params[79:72];
                    write_record[26] <= current_params[87:80];
                    write_record[32] <= 8'hFF;
                    write_record[33] <= 8'hFF;
                    write_record[34] <= 8'hFF;
                    write_record[35] <= 8'hFF;
                    crc_index        <= 6'd0;
                    state            <= ST_SAVE_CRC_START;
                end

                ST_SAVE_CRC_START: begin
                    crc_start <= 1'b1;
                    crc_index <= 6'd0;
                    state     <= ST_SAVE_CRC_FEED;
                end

                ST_SAVE_CRC_FEED: begin
                    crc_data_valid <= 1'b1;
                    crc_data_byte  <= write_record[crc_index];
                    if (crc_index == 6'd27)
                        state <= ST_SAVE_CRC_FINISH;
                    else
                        crc_index <= crc_index + 1'b1;
                end

                ST_SAVE_CRC_FINISH: begin
                    crc_finish <= 1'b1;
                    state      <= ST_SAVE_CRC_WAIT;
                end

                ST_SAVE_CRC_WAIT: begin
                    if (crc_done) begin
                        write_record[28] <= crc_result[7:0];
                        write_record[29] <= crc_result[15:8];
                        write_record[30] <= crc_result[23:16];
                        write_record[31] <= crc_result[31:24];
                        state            <= ST_ERASE_WREN_ISSUE;
                    end
                end

                ST_ERASE_WREN_ISSUE: begin
                    spi_tx_bytes <= {8'h06, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_ERASE_WREN_WAIT;
                end

                ST_ERASE_WREN_WAIT: begin
                    if (spi_done)
                        state <= ST_ERASE_ISSUE;
                end

                ST_ERASE_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h20, target_base[23:16], target_base[15:8],
                        target_base[7:0], 32'd0
                    };
                    spi_tx_count <= 4'd4;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_ERASE_WAIT;
                end

                ST_ERASE_WAIT: begin
                    if (spi_done) begin
                        poll_count <= 32'd0;
                        state      <= ST_ERASE_STATUS_ISSUE;
                    end
                end

                ST_ERASE_STATUS_ISSUE: begin
                    spi_tx_bytes <= {8'h05, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd1;
                    spi_start    <= 1'b1;
                    state        <= ST_ERASE_STATUS_WAIT;
                end

                ST_ERASE_STATUS_WAIT: begin
                    if (spi_done) begin
                        if (spi_rx_bytes[56]) begin
                            if (poll_count + 1 >= FLASH_TIMEOUT_POLLS) begin
                                error_code <= ERROR_FLASH_TIMEOUT;
                                state      <= ST_OPERATION_ERROR;
                            end
                            else begin
                                poll_count <= poll_count + 1'b1;
                                state      <= ST_ERASE_STATUS_ISSUE;
                            end
                        end
                        else begin
                            program_offset <= 6'd0;
                            state          <= ST_PROGRAM_WREN_ISSUE;
                        end
                    end
                end

                ST_PROGRAM_WREN_ISSUE: begin
                    spi_tx_bytes <= {8'h06, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_PROGRAM_WREN_WAIT;
                end

                ST_PROGRAM_WREN_WAIT: begin
                    if (spi_done)
                        state <= ST_PROGRAM_ISSUE;
                end

                ST_PROGRAM_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h02,
                        target_program_address[23:16],
                        target_program_address[15:8],
                        target_program_address[7:0],
                        write_record[program_offset],
                        write_record[program_offset + 1],
                        write_record[program_offset + 2],
                        write_record[program_offset + 3]
                    };
                    spi_tx_count <= 4'd8;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_PROGRAM_WAIT;
                end

                ST_PROGRAM_WAIT: begin
                    if (spi_done) begin
                        poll_count <= 32'd0;
                        state      <= ST_PROGRAM_STATUS_ISSUE;
                    end
                end

                ST_PROGRAM_STATUS_ISSUE: begin
                    spi_tx_bytes <= {8'h05, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd1;
                    spi_start    <= 1'b1;
                    state        <= ST_PROGRAM_STATUS_WAIT;
                end

                ST_PROGRAM_STATUS_WAIT: begin
                    if (spi_done) begin
                        if (spi_rx_bytes[56]) begin
                            if (poll_count + 1 >= FLASH_TIMEOUT_POLLS) begin
                                error_code <= ERROR_FLASH_TIMEOUT;
                                state      <= ST_OPERATION_ERROR;
                            end
                            else begin
                                poll_count <= poll_count + 1'b1;
                                state      <= ST_PROGRAM_STATUS_ISSUE;
                            end
                        end
                        else if (program_offset == 6'd60) begin
                            read_offset <= 7'd0;
                            state       <= ST_VERIFY_READ_ISSUE;
                        end
                        else begin
                            if (program_offset == 6'd28)
                                program_offset <= 6'd36;
                            else
                                program_offset <= program_offset + 6'd4;
                            state <= ST_PROGRAM_WREN_ISSUE;
                        end
                    end
                end

                ST_VERIFY_READ_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h03,
                        target_read_address[23:16],
                        target_read_address[15:8],
                        target_read_address[7:0],
                        32'd0
                    };
                    spi_tx_count <= 4'd4;
                    spi_rx_count <= 4'd8;
                    spi_start    <= 1'b1;
                    state        <= ST_VERIFY_READ_WAIT;
                end

                ST_VERIFY_READ_WAIT: begin
                    if (spi_done) begin
                        verify_record[read_offset]     <= spi_rx_bytes[63:56];
                        verify_record[read_offset + 1] <= spi_rx_bytes[55:48];
                        verify_record[read_offset + 2] <= spi_rx_bytes[47:40];
                        verify_record[read_offset + 3] <= spi_rx_bytes[39:32];
                        verify_record[read_offset + 4] <= spi_rx_bytes[31:24];
                        verify_record[read_offset + 5] <= spi_rx_bytes[23:16];
                        verify_record[read_offset + 6] <= spi_rx_bytes[15:8];
                        verify_record[read_offset + 7] <= spi_rx_bytes[7:0];
                        if (read_offset == 7'd56) begin
                            crc_index <= 6'd0;
                            state     <= ST_VERIFY_CRC_START;
                        end
                        else begin
                            read_offset <= read_offset + 7'd8;
                            state       <= ST_VERIFY_READ_ISSUE;
                        end
                    end
                end

                ST_VERIFY_CRC_START: begin
                    crc_start <= 1'b1;
                    crc_index <= 6'd0;
                    state     <= ST_VERIFY_CRC_FEED;
                end

                ST_VERIFY_CRC_FEED: begin
                    crc_data_valid <= 1'b1;
                    crc_data_byte  <= verify_record[crc_index];
                    if (crc_index == 6'd27)
                        state <= ST_VERIFY_CRC_FINISH;
                    else
                        crc_index <= crc_index + 1'b1;
                end

                ST_VERIFY_CRC_FINISH: begin
                    crc_finish <= 1'b1;
                    state      <= ST_VERIFY_CRC_WAIT;
                end

                ST_VERIFY_CRC_WAIT: begin
                    if (crc_done)
                        state <= ST_VERIFY_CHECK;
                end

                ST_VERIFY_CHECK: begin
                    verify_mismatch = 1'b0;
                    for (array_index = 0; array_index < 64;
                         array_index = array_index + 1) begin
                        if ((array_index < 32 || array_index >= 36) &&
                            verify_record[array_index] !=
                            write_record[array_index])
                            verify_mismatch = 1'b1;
                    end
                    if ({verify_record[31], verify_record[30],
                         verify_record[29], verify_record[28]} !=
                        crc_result)
                        verify_mismatch = 1'b1;

                    if (verify_mismatch) begin
                        error_code <= ERROR_READBACK;
                        state      <= ST_OPERATION_ERROR;
                    end
                    else begin
                        state <= ST_COMMIT_WREN_ISSUE;
                    end
                end

                ST_COMMIT_WREN_ISSUE: begin
                    spi_tx_bytes <= {8'h06, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_COMMIT_WREN_WAIT;
                end

                ST_COMMIT_WREN_WAIT: begin
                    if (spi_done)
                        state <= ST_COMMIT_ISSUE;
                end

                ST_COMMIT_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h02,
                        target_commit_address[23:16],
                        target_commit_address[15:8],
                        target_commit_address[7:0],
                        8'hED, 8'h5E, 8'hA5, 8'hC0
                    };
                    spi_tx_count <= 4'd8;
                    spi_rx_count <= 4'd0;
                    spi_start    <= 1'b1;
                    state        <= ST_COMMIT_WAIT;
                end

                ST_COMMIT_WAIT: begin
                    if (spi_done) begin
                        poll_count <= 32'd0;
                        state      <= ST_COMMIT_STATUS_ISSUE;
                    end
                end

                ST_COMMIT_STATUS_ISSUE: begin
                    spi_tx_bytes <= {8'h05, 56'd0};
                    spi_tx_count <= 4'd1;
                    spi_rx_count <= 4'd1;
                    spi_start    <= 1'b1;
                    state        <= ST_COMMIT_STATUS_WAIT;
                end

                ST_COMMIT_STATUS_WAIT: begin
                    if (spi_done) begin
                        if (spi_rx_bytes[56]) begin
                            if (poll_count + 1 >= FLASH_TIMEOUT_POLLS) begin
                                error_code <= ERROR_FLASH_TIMEOUT;
                                state      <= ST_OPERATION_ERROR;
                            end
                            else begin
                                poll_count <= poll_count + 1'b1;
                                state      <= ST_COMMIT_STATUS_ISSUE;
                            end
                        end
                        else begin
                            state <= ST_COMMIT_READ_ISSUE;
                        end
                    end
                end

                ST_COMMIT_READ_ISSUE: begin
                    spi_tx_bytes <= {
                        8'h03,
                        target_commit_address[23:16],
                        target_commit_address[15:8],
                        target_commit_address[7:0],
                        32'd0
                    };
                    spi_tx_count <= 4'd4;
                    spi_rx_count <= 4'd4;
                    spi_start    <= 1'b1;
                    state        <= ST_COMMIT_READ_WAIT;
                end

                ST_COMMIT_READ_WAIT: begin
                    if (spi_done) begin
                        if ({spi_rx_bytes[39:32], spi_rx_bytes[47:40],
                             spi_rx_bytes[55:48], spi_rx_bytes[63:56]} ==
                            32'hC0A55EED) begin
                            state <= ST_SAVE_SUCCESS;
                        end
                        else begin
                            error_code <= ERROR_READBACK;
                            state      <= ST_OPERATION_ERROR;
                        end
                    end
                end

                ST_SAVE_SUCCESS: begin
                    active_slot        <= target_slot;
                    active_sequence    <= new_sequence;
                    have_active_record <= 1'b1;
                    loaded_params      <= current_params;
                    params_valid       <= 1'b1;
                    error_code         <= ERROR_NONE;
                    busy               <= 1'b0;
                    done               <= 1'b1;
                    state              <= ST_IDLE;
                end

                ST_OPERATION_ERROR: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    busy       <= 1'b0;
                    error_code <= ERROR_FLASH_TIMEOUT;
                    state      <= ST_OPERATION_ERROR;
                end
            endcase
        end
    end

endmodule
