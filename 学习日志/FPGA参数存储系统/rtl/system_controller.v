`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Parameter-storage system coordinator.
//
// This module owns command scheduling and response framing only. UART receive,
// request parsing, parameter storage, Flash record handling, and UART
// serialization remain in their dedicated modules.
// -----------------------------------------------------------------------------
module system_controller #(
    parameter integer AUTO_BOOT = 1
) (
    input  wire         clk,
    input  wire         rst_n,

    // command_parser result interface
    input  wire         frame_valid,
    input  wire [7:0]   command,
    input  wire [7:0]   seq_num,
    input  wire [15:0]  payload_length,
    input  wire [255:0] payload,
    input  wire [2:0]   frame_error,

    // parameter_regs interface
    input  wire [87:0]  params,
    input  wire         params_valid,
    input  wire         write_error,
    output reg          param_write_en,
    output reg  [87:0]  param_write_params,
    output reg          param_load_en,
    output reg  [87:0]  param_load_params,
    output reg          param_default_en,

    // flash_record_manager interface
    input  wire         flash_busy,
    input  wire         flash_done,
    input  wire [7:0]   flash_error_code,
    input  wire [87:0]  flash_loaded_params,
    input  wire         flash_params_valid,
    input  wire         flash_active_slot,
    output reg          flash_boot_start,
    output reg          flash_save_start,
    output reg          flash_load_start,

    // uart_tx byte interface
    input  wire         tx_busy,
    output reg          tx_start,
    output reg  [7:0]   tx_data,

    // top-level status interface
    output wire         controller_busy,
    output reg  [7:0]   last_error
);

    localparam [7:0] CMD_GET_STATUS   = 8'h01;
    localparam [7:0] CMD_READ_PARAM   = 8'h02;
    localparam [7:0] CMD_WRITE_PARAM  = 8'h03;
    localparam [7:0] CMD_SAVE_FLASH   = 8'h04;
    localparam [7:0] CMD_LOAD_FLASH   = 8'h05;
    localparam [7:0] CMD_LOAD_DEFAULT = 8'h06;

    localparam [7:0] STATUS_SUCCESS       = 8'h00;
    localparam [7:0] STATUS_FRAME_ERROR   = 8'h01;
    localparam [7:0] STATUS_BAD_COMMAND   = 8'h02;
    localparam [7:0] STATUS_BAD_PARAMETER = 8'h03;
    localparam [7:0] STATUS_FLASH_BUSY    = 8'h04;
    localparam [7:0] STATUS_READBACK      = 8'h05;
    localparam [7:0] STATUS_NO_VALID      = 8'h06;

    localparam [4:0]
        ST_BOOT_START     = 5'd0,
        ST_BOOT_WAIT      = 5'd1,
        ST_BOOT_LOAD      = 5'd2,
        ST_BOOT_SETTLE    = 5'd3,
        ST_READY          = 5'd4,
        ST_WRITE_ISSUE    = 5'd5,
        ST_WRITE_WAIT     = 5'd6,
        ST_WRITE_CHECK    = 5'd7,
        ST_SAVE_ISSUE     = 5'd8,
        ST_SAVE_WAIT      = 5'd9,
        ST_LOAD_ISSUE     = 5'd10,
        ST_LOAD_WAIT      = 5'd11,
        ST_LOAD_APPLY     = 5'd12,
        ST_LOAD_SETTLE    = 5'd13,
        ST_LOAD_CHECK     = 5'd14,
        ST_DEFAULT_ISSUE  = 5'd15,
        ST_DEFAULT_WAIT   = 5'd16,
        ST_DEFAULT_CHECK  = 5'd17,
        ST_BUILD_RESPONSE = 5'd18,
        ST_TX_ISSUE       = 5'd19,
        ST_TX_WAIT_BUSY   = 5'd20,
        ST_TX_WAIT_DONE   = 5'd21,
        ST_BOOT_CHECK     = 5'd22,
        ST_BOOT_DEFAULT_ISSUE = 5'd23,
        ST_BOOT_DEFAULT_WAIT  = 5'd24,
        ST_BOOT_DEFAULT_CHECK = 5'd25;

    reg [4:0] state;

    reg [7:0]  response_command;
    reg [7:0]  response_status;
    reg [15:0] response_length;
    reg [7:0]  response_sequence;
    reg [87:0] response_payload;
    reg [7:0]  response_buffer [0:21];
    reg [4:0]  response_total_length;
    reg [4:0]  tx_index;

    reg [87:0] load_result_params;
    reg [7:0]  load_result_status;
    reg [7:0]  default_result_status;
    integer response_index;
    wire [31:0] response_crc_value;

    assign controller_busy = (state != ST_READY);

    function [31:0] crc32_update_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        integer bit_index;
        reg [31:0] value;
        begin
            value = crc_in ^ {24'd0, data_in};
            for (bit_index = 0; bit_index < 8;
                 bit_index = bit_index + 1) begin
                if (value[0])
                    value = (value >> 1) ^ 32'hEDB88320;
                else
                    value = value >> 1;
            end
            crc32_update_byte = value;
        end
    endfunction

    function [31:0] response_crc32;
        input [7:0]  command_in;
        input [7:0]  status_in;
        input [15:0] length_in;
        input [7:0]  sequence_in;
        input [87:0] payload_in;
        integer payload_index;
        reg [31:0] value;
        begin
            value = 32'hFFFFFFFF;
            value = crc32_update_byte(value, command_in);
            value = crc32_update_byte(value, status_in);
            value = crc32_update_byte(value, length_in[7:0]);
            value = crc32_update_byte(value, length_in[15:8]);
            value = crc32_update_byte(value, sequence_in);
            for (payload_index = 0; payload_index < 11;
                 payload_index = payload_index + 1) begin
                if (payload_index < length_in)
                    value = crc32_update_byte(
                        value, payload_in[payload_index * 8 +: 8]);
            end
            response_crc32 = value ^ 32'hFFFFFFFF;
        end
    endfunction

    assign response_crc_value = response_crc32(
        response_command,
        response_status,
        response_length,
        response_sequence,
        response_payload
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= AUTO_BOOT ? ST_BOOT_START : ST_READY;
            param_write_en        <= 1'b0;
            param_write_params    <= 88'd0;
            param_load_en         <= 1'b0;
            param_load_params     <= 88'd0;
            param_default_en      <= 1'b0;
            flash_boot_start      <= 1'b0;
            flash_save_start      <= 1'b0;
            flash_load_start      <= 1'b0;
            tx_start              <= 1'b0;
            tx_data               <= 8'd0;
            last_error            <= STATUS_SUCCESS;
            response_command      <= 8'd0;
            response_status       <= STATUS_SUCCESS;
            response_length       <= 16'd0;
            response_sequence     <= 8'd0;
            response_payload      <= 88'd0;
            response_total_length <= 5'd0;
            tx_index              <= 5'd0;
            load_result_params    <= 88'd0;
            load_result_status    <= STATUS_SUCCESS;
            default_result_status <= STATUS_SUCCESS;
            for (response_index = 0; response_index < 22;
                 response_index = response_index + 1)
                response_buffer[response_index] <= 8'd0;
        end
        else begin
            param_write_en   <= 1'b0;
            param_load_en    <= 1'b0;
            param_default_en <= 1'b0;
            flash_boot_start <= 1'b0;
            flash_save_start <= 1'b0;
            flash_load_start <= 1'b0;
            tx_start         <= 1'b0;

            case (state)
                ST_BOOT_START: begin
                    flash_boot_start <= 1'b1;
                    state            <= ST_BOOT_WAIT;
                end

                ST_BOOT_WAIT: begin
                    if (flash_done) begin
                        last_error <= flash_error_code;
                        if (flash_params_valid) begin
                            param_load_params <= flash_loaded_params;
                            state             <= ST_BOOT_LOAD;
                        end
                        else if (flash_error_code == STATUS_NO_VALID) begin
                            state <= ST_BOOT_DEFAULT_ISSUE;
                        end
                        else if (flash_error_code == STATUS_SUCCESS) begin
                            last_error <= STATUS_READBACK;
                            state      <= ST_BOOT_DEFAULT_ISSUE;
                        end
                        else begin
                            state <= ST_READY;
                        end
                    end
                end

                ST_BOOT_LOAD: begin
                    param_load_en <= 1'b1;
                    state         <= ST_BOOT_SETTLE;
                end

                ST_BOOT_SETTLE: begin
                    state <= ST_BOOT_CHECK;
                end

                ST_BOOT_CHECK: begin
                    if (write_error || !params_valid ||
                        (params != param_load_params)) begin
                        last_error <= STATUS_BAD_PARAMETER;
                        state      <= ST_BOOT_DEFAULT_ISSUE;
                    end
                    else begin
                        state <= ST_READY;
                    end
                end

                ST_BOOT_DEFAULT_ISSUE: begin
                    param_default_en <= 1'b1;
                    state            <= ST_BOOT_DEFAULT_WAIT;
                end

                ST_BOOT_DEFAULT_WAIT: begin
                    state <= ST_BOOT_DEFAULT_CHECK;
                end

                ST_BOOT_DEFAULT_CHECK: begin
                    if (!params_valid || write_error)
                        last_error <= STATUS_BAD_PARAMETER;
                    state <= ST_READY;
                end

                ST_READY: begin
                    if (frame_error != 3'd0) begin
                        response_command  <= 8'hFF;
                        response_status   <= STATUS_FRAME_ERROR;
                        response_length   <= 16'd0;
                        response_sequence <= seq_num;
                        response_payload  <= 88'd0;
                        last_error        <= STATUS_FRAME_ERROR;
                        state             <= ST_BUILD_RESPONSE;
                    end
                    else if (frame_valid) begin
                        response_command  <= command + 8'h80;
                        response_sequence <= seq_num;
                        response_payload  <= 88'd0;

                        case (command)
                            CMD_GET_STATUS: begin
                                if (payload_length != 16'd0) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                end
                                else begin
                                    response_status <= STATUS_SUCCESS;
                                    response_length <= 16'd4;
                                    response_payload <= {
                                        56'd0,
                                        last_error,
                                        {7'd0, params_valid},
                                        {7'd0, flash_active_slot},
                                        8'h00
                                    };
                                    last_error <= STATUS_SUCCESS;
                                end
                                state <= ST_BUILD_RESPONSE;
                            end

                            CMD_READ_PARAM: begin
                                if (payload_length != 16'd0) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                end
                                else begin
                                    response_status  <= STATUS_SUCCESS;
                                    response_length  <= 16'd11;
                                    response_payload <= params;
                                    last_error       <= STATUS_SUCCESS;
                                end
                                state <= ST_BUILD_RESPONSE;
                            end

                            CMD_WRITE_PARAM: begin
                                if (payload_length != 16'd11) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else begin
                                    param_write_params <= payload[87:0];
                                    state              <= ST_WRITE_ISSUE;
                                end
                            end

                            CMD_SAVE_FLASH: begin
                                if (payload_length != 16'd0) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else if (flash_busy) begin
                                    response_status <= STATUS_FLASH_BUSY;
                                    response_length <= 16'd0;
                                    last_error      <= STATUS_FLASH_BUSY;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else begin
                                    state <= ST_SAVE_ISSUE;
                                end
                            end

                            CMD_LOAD_FLASH: begin
                                if (payload_length != 16'd0) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else if (flash_busy) begin
                                    response_status <= STATUS_FLASH_BUSY;
                                    response_length <= 16'd0;
                                    last_error      <= STATUS_FLASH_BUSY;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else begin
                                    state <= ST_LOAD_ISSUE;
                                end
                            end

                            CMD_LOAD_DEFAULT: begin
                                if (payload_length != 16'd0) begin
                                    response_status <=
                                        STATUS_BAD_PARAMETER;
                                    response_length <= 16'd0;
                                    last_error      <=
                                        STATUS_BAD_PARAMETER;
                                    state <= ST_BUILD_RESPONSE;
                                end
                                else begin
                                    default_result_status <= STATUS_SUCCESS;
                                    state                 <= ST_DEFAULT_ISSUE;
                                end
                            end

                            default: begin
                                response_status <= STATUS_BAD_COMMAND;
                                response_length <= 16'd0;
                                last_error      <= STATUS_BAD_COMMAND;
                                state           <= ST_BUILD_RESPONSE;
                            end
                        endcase
                    end
                end

                ST_WRITE_ISSUE: begin
                    param_write_en <= 1'b1;
                    state          <= ST_WRITE_WAIT;
                end

                ST_WRITE_WAIT: begin
                    state <= ST_WRITE_CHECK;
                end

                ST_WRITE_CHECK: begin
                    response_length <= 16'd0;
                    response_payload <= 88'd0;
                    if (write_error || !params_valid ||
                        (params != param_write_params)) begin
                        response_status <= STATUS_BAD_PARAMETER;
                        last_error      <= STATUS_BAD_PARAMETER;
                    end
                    else begin
                        response_status <= STATUS_SUCCESS;
                        last_error      <= STATUS_SUCCESS;
                    end
                    state <= ST_BUILD_RESPONSE;
                end

                ST_SAVE_ISSUE: begin
                    flash_save_start <= 1'b1;
                    state            <= ST_SAVE_WAIT;
                end

                ST_SAVE_WAIT: begin
                    if (flash_done) begin
                        response_status  <= flash_error_code;
                        response_length  <= 16'd0;
                        response_payload <= 88'd0;
                        last_error       <= flash_error_code;
                        state            <= ST_BUILD_RESPONSE;
                    end
                end

                ST_LOAD_ISSUE: begin
                    flash_load_start <= 1'b1;
                    state            <= ST_LOAD_WAIT;
                end

                ST_LOAD_WAIT: begin
                    if (flash_done) begin
                        load_result_params <= flash_loaded_params;
                        load_result_status <= flash_error_code;
                        if (flash_error_code == STATUS_SUCCESS) begin
                            if (flash_params_valid) begin
                                param_load_params <= flash_loaded_params;
                                state             <= ST_LOAD_APPLY;
                            end
                            else begin
                                response_status  <= STATUS_READBACK;
                                response_length  <= 16'd0;
                                response_payload <= 88'd0;
                                last_error       <= STATUS_READBACK;
                                state            <= ST_BUILD_RESPONSE;
                            end
                        end
                        else if (flash_error_code == STATUS_NO_VALID) begin
                            if (flash_params_valid) begin
                                param_load_params <= flash_loaded_params;
                                state             <= ST_LOAD_APPLY;
                            end
                            else begin
                                default_result_status <= STATUS_NO_VALID;
                                state                 <= ST_DEFAULT_ISSUE;
                            end
                        end
                        else begin
                            response_status  <= flash_error_code;
                            response_length  <= 16'd0;
                            response_payload <= 88'd0;
                            last_error       <= flash_error_code;
                            state            <= ST_BUILD_RESPONSE;
                        end
                    end
                end

                ST_LOAD_APPLY: begin
                    param_load_en <= 1'b1;
                    state         <= ST_LOAD_SETTLE;
                end

                ST_LOAD_SETTLE: begin
                    state <= ST_LOAD_CHECK;
                end

                ST_LOAD_CHECK: begin
                    if (write_error || !params_valid ||
                        (params != load_result_params)) begin
                        response_status  <= STATUS_BAD_PARAMETER;
                        response_length  <= 16'd0;
                        response_payload <= 88'd0;
                        last_error       <= STATUS_BAD_PARAMETER;
                    end
                    else begin
                        response_status  <= load_result_status;
                        response_length  <= 16'd11;
                        response_payload <= load_result_params;
                        last_error       <= load_result_status;
                    end
                    state <= ST_BUILD_RESPONSE;
                end

                ST_DEFAULT_ISSUE: begin
                    param_default_en <= 1'b1;
                    state            <= ST_DEFAULT_WAIT;
                end

                ST_DEFAULT_WAIT: begin
                    state <= ST_DEFAULT_CHECK;
                end

                ST_DEFAULT_CHECK: begin
                    response_status  <= default_result_status;
                    response_length  <= 16'd11;
                    response_payload <= params;
                    last_error       <= default_result_status;
                    state            <= ST_BUILD_RESPONSE;
                end

                ST_BUILD_RESPONSE: begin
                    response_buffer[0] <= 8'h55;
                    response_buffer[1] <= 8'hAA;
                    response_buffer[2] <= response_command;
                    response_buffer[3] <= response_status;
                    response_buffer[4] <= response_length[7:0];
                    response_buffer[5] <= response_length[15:8];
                    response_buffer[6] <= response_sequence;

                    for (response_index = 0; response_index < 11;
                         response_index = response_index + 1) begin
                        if (response_index < response_length)
                            response_buffer[7 + response_index] <=
                                response_payload[
                                    response_index * 8 +: 8
                                ];
                    end

                    response_buffer[7 + response_length] <=
                        response_crc_value[7:0];
                    response_buffer[8 + response_length] <=
                        response_crc_value[15:8];
                    response_buffer[9 + response_length] <=
                        response_crc_value[23:16];
                    response_buffer[10 + response_length] <=
                        response_crc_value[31:24];
                    response_total_length <= response_length + 5'd11;
                    tx_index              <= 5'd0;
                    state                 <= ST_TX_ISSUE;
                end

                ST_TX_ISSUE: begin
                    if (!tx_busy) begin
                        tx_data  <= response_buffer[tx_index];
                        tx_start <= 1'b1;
                        state    <= ST_TX_WAIT_BUSY;
                    end
                end

                ST_TX_WAIT_BUSY: begin
                    if (tx_busy)
                        state <= ST_TX_WAIT_DONE;
                end

                ST_TX_WAIT_DONE: begin
                    if (!tx_busy) begin
                        if (tx_index + 1'b1 >= response_total_length) begin
                            state <= ST_READY;
                        end
                        else begin
                            tx_index <= tx_index + 1'b1;
                            state    <= ST_TX_ISSUE;
                        end
                    end
                end

                default: begin
                    last_error <= STATUS_FLASH_BUSY;
                    state      <= ST_READY;
                end
            endcase
        end
    end

endmodule
