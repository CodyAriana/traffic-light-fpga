`timescale 1ns / 1ps

// Decode an ASCII command and select both the LED result and response text.
// Response codes: 0=OFF, 1=GREEN, 2=YELLOW, 3=RED, 4=ERROR.
module uart_cmd_decoder_ack (
    input  wire       rx_valid,
    input  wire [7:0] rx_data,
    output reg        command_valid,
    output reg  [3:0] led_value,
    output reg  [2:0] response_code
);

    always @(*) begin
        command_valid = 1'b0;
        led_value     = 4'b0000;
        response_code = 3'd4;

        if (rx_valid) begin
            case (rx_data)
                8'h30: begin
                    command_valid = 1'b1;
                    led_value     = 4'b0000;
                    response_code = 3'd0;
                end

                8'h31: begin
                    command_valid = 1'b1;
                    led_value     = 4'b0001;
                    response_code = 3'd1;
                end

                8'h32: begin
                    command_valid = 1'b1;
                    led_value     = 4'b0010;
                    response_code = 3'd2;
                end

                8'h33: begin
                    command_valid = 1'b1;
                    led_value     = 4'b0100;
                    response_code = 3'd3;
                end

                default: begin
                    command_valid = 1'b0;
                    led_value     = 4'b0000;
                    response_code = 3'd4;
                end
            endcase
        end
    end

endmodule
