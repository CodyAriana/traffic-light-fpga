`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// FPGA non-volatile parameter storage system top level.
//
// Data path:
//   UART RX -> FIFO -> command parser -> system controller
//                                      -> parameter registers
//                                      -> dual-slot Flash manager
//                                      -> UART TX response
// -----------------------------------------------------------------------------
module fpga_param_storage_top #(
    parameter integer CLK_FREQ_HZ     = 50_000_000,
    parameter integer BAUD_RATE       = 115_200,
    parameter integer SPI_CLK_DIV     = 4,
    parameter integer FLASH_TIMEOUT_POLLS = 500000,
    parameter integer AUTO_BOOT       = 1
)(
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire       uart_rx_pin,
    output wire       uart_tx_pin,
    output wire       flash_cs_n,
    output wire       flash_io0,
    input  wire       flash_io1,
    output wire       flash_io2,
    output wire       flash_io3,
    output wire [3:0] led
);

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_busy;

    wire       fifo_empty;
    wire       fifo_full;
    wire [7:0] fifo_rd_data;
    wire [6:0] fifo_count;
    wire       fifo_rd_en;
    reg        fifo_rd_pending;

    wire       parser_byte_valid;
    wire [7:0] parser_byte_data;
    wire       frame_valid;
    wire [7:0] parser_command;
    wire [7:0] parser_seq_num;
    wire [15:0] parser_payload_length;
    wire [255:0] parser_payload;
    wire [2:0] parser_frame_error;

    wire [87:0] params;
    wire         params_valid;
    wire         write_error;
    wire         param_write_en;
    wire [87:0]  param_write_params;
    wire         param_load_en;
    wire [87:0]  param_load_params;
    wire         param_default_en;

    wire         flash_boot_start;
    wire         flash_save_start;
    wire         flash_load_start;
    wire         flash_busy;
    wire         flash_done;
    wire [7:0]   flash_error_code;
    wire [87:0]  flash_loaded_params;
    wire         flash_params_valid;
    wire         flash_active_slot;
    wire         flash_mosi;
    wire         flash_clk_user;

    wire         tx_start;
    wire [7:0]   tx_data;
    wire         tx_busy;
    wire         controller_busy;
    wire [7:0]   last_error;

    // FIFO output is registered. The pending flag aligns byte_valid with the
    // byte that was read on the preceding clock edge.
    assign fifo_rd_en        = !fifo_empty;
    assign parser_byte_valid = fifo_rd_pending;
    assign parser_byte_data  = fifo_rd_data;

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n)
            fifo_rd_pending <= 1'b0;
        else
            fifo_rd_pending <= fifo_rd_en;
    end

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_rx (
        .clk      (clk_50m),
        .rst_n    (rst_n),
        .rx       (uart_rx_pin),
        .rx_valid (rx_valid),
        .rx_data  (rx_data),
        .busy     (rx_busy)
    );

    uart_rx_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (64)
    ) u_uart_rx_fifo (
        .clk     (clk_50m),
        .rst_n   (rst_n),
        .wr_en   (rx_valid),
        .wr_data (rx_data),
        .rd_en   (fifo_rd_en),
        .rd_data (fifo_rd_data),
        .empty   (fifo_empty),
        .full    (fifo_full),
        .count   (fifo_count)
    );

    command_parser u_command_parser (
        .clk            (clk_50m),
        .rst_n          (rst_n),
        .byte_valid     (parser_byte_valid),
        .byte_data      (parser_byte_data),
        .frame_valid    (frame_valid),
        .command        (parser_command),
        .seq_num        (parser_seq_num),
        .payload_length (parser_payload_length),
        .payload        (parser_payload),
        .frame_error    (parser_frame_error)
    );

    parameter_regs u_parameter_regs (
        .clk          (clk_50m),
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

    flash_record_manager #(
        .SPI_CLK_DIV          (SPI_CLK_DIV),
        .FLASH_TIMEOUT_POLLS (FLASH_TIMEOUT_POLLS)
    ) u_flash_record_manager (
        .clk            (clk_50m),
        .rst_n          (rst_n),
        .boot_start     (flash_boot_start),
        .save_start     (flash_save_start),
        .load_start     (flash_load_start),
        .current_params (params),
        .loaded_params  (flash_loaded_params),
        .params_valid   (flash_params_valid),
        .active_slot    (flash_active_slot),
        .busy           (flash_busy),
        .done           (flash_done),
        .error_code     (flash_error_code),
        .flash_cs_n     (flash_cs_n),
        .flash_sck      (flash_clk_user),
        .flash_mosi     (flash_mosi),
        .flash_miso     (flash_io1)
    );

    system_controller #(
        .AUTO_BOOT(AUTO_BOOT)
    ) u_system_controller (
        .clk                 (clk_50m),
        .rst_n               (rst_n),
        .frame_valid         (frame_valid),
        .command             (parser_command),
        .seq_num             (parser_seq_num),
        .payload_length      (parser_payload_length),
        .payload             (parser_payload),
        .frame_error         (parser_frame_error),
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

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk_50m),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx_pin),
        .tx_busy  (tx_busy)
    );

    // IO0 is MOSI. IO2/IO3 are WP#/HOLD#/RESET related pins and stay inactive.
    assign flash_io0 = flash_mosi;
    assign flash_io2 = 1'b1;
    assign flash_io3 = 1'b1;

    // The board routes the user Flash clock through the dedicated CCLK pin.
    STARTUPE2 #(
        .PROG_USR     ("FALSE"),
        .SIM_CCLK_FREQ(10.0)
    ) u_startupe2 (
        .CFGCLK      (),
        .CFGMCLK     (),
        .EOS         (),
        .PREQ        (),
        .CLK         (1'b0),
        .GSR         (1'b0),
        .GTS         (1'b0),
        .KEYCLEARB   (1'b1),
        .PACK        (1'b0),
        .USRCCLKO   (flash_clk_user),
        .USRCCLKTS  (1'b0),
        .USRDONEO    (1'b0),
        .USRDONETS   (1'b1)
    );

    assign led[0] = controller_busy;
    assign led[1] = tx_busy;
    assign led[2] = params_valid;
    assign led[3] = (last_error != 8'd0);

endmodule
