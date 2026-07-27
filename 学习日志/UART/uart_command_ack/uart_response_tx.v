`timescale 1ns / 1ps

// Send one fixed ASCII response string through the existing uart_tx module.
module uart_response_tx (
    input  wire       clk_50m,
    input  wire       rst_n,
    input  wire       response_start,
    input  wire [2:0] response_code,
    input  wire       uart_busy,
    output wire       tx_start,
    output reg  [7:0] tx_data,
    output wire       response_busy
);

    reg       active;
    reg [2:0] current_code;
    reg [3:0] char_index;
    reg [3:0] message_length;

    assign response_busy = active;
    assign tx_start = active && !uart_busy;

    // Small combinational ROM for the five response strings.
    always @(*) begin
        tx_data       = 8'h20;
        message_length = 4'd7;

        case (current_code)
            3'd0: begin
                message_length = 4'd9;
                case (char_index)
                    4'd0: tx_data = 8'h4c; // L
                    4'd1: tx_data = 8'h45; // E
                    4'd2: tx_data = 8'h44; // D
                    4'd3: tx_data = 8'h20; // space
                    4'd4: tx_data = 8'h4f; // O
                    4'd5: tx_data = 8'h46; // F
                    4'd6: tx_data = 8'h46; // F
                    4'd7: tx_data = 8'h0d; // CR
                    4'd8: tx_data = 8'h0a; // LF
                    default: tx_data = 8'h20;
                endcase
            end

            3'd1: begin
                message_length = 4'd11;
                case (char_index)
                    4'd0: tx_data = 8'h4c; // L
                    4'd1: tx_data = 8'h45; // E
                    4'd2: tx_data = 8'h44; // D
                    4'd3: tx_data = 8'h20; // space
                    4'd4: tx_data = 8'h47; // G
                    4'd5: tx_data = 8'h52; // R
                    4'd6: tx_data = 8'h45; // E
                    4'd7: tx_data = 8'h45; // E
                    4'd8: tx_data = 8'h4e; // N
                    4'd9: tx_data = 8'h0d; // CR
                    4'd10: tx_data = 8'h0a; // LF
                    default: tx_data = 8'h20;
                endcase
            end

            3'd2: begin
                message_length = 4'd12;
                case (char_index)
                    4'd0: tx_data = 8'h4c; // L
                    4'd1: tx_data = 8'h45; // E
                    4'd2: tx_data = 8'h44; // D
                    4'd3: tx_data = 8'h20; // space
                    4'd4: tx_data = 8'h59; // Y
                    4'd5: tx_data = 8'h45; // E
                    4'd6: tx_data = 8'h4c; // L
                    4'd7: tx_data = 8'h4c; // L
                    4'd8: tx_data = 8'h4f; // O
                    4'd9: tx_data = 8'h57; // W
                    4'd10: tx_data = 8'h0d; // CR
                    4'd11: tx_data = 8'h0a; // LF
                    default: tx_data = 8'h20;
                endcase
            end

            3'd3: begin
                message_length = 4'd9;
                case (char_index)
                    4'd0: tx_data = 8'h4c; // L
                    4'd1: tx_data = 8'h45; // E
                    4'd2: tx_data = 8'h44; // D
                    4'd3: tx_data = 8'h20; // space
                    4'd4: tx_data = 8'h52; // R
                    4'd5: tx_data = 8'h45; // E
                    4'd6: tx_data = 8'h44; // D
                    4'd7: tx_data = 8'h0d; // CR
                    4'd8: tx_data = 8'h0a; // LF
                    default: tx_data = 8'h20;
                endcase
            end

            default: begin
                message_length = 4'd7;
                case (char_index)
                    4'd0: tx_data = 8'h45; // E
                    4'd1: tx_data = 8'h52; // R
                    4'd2: tx_data = 8'h52; // R
                    4'd3: tx_data = 8'h4f; // O
                    4'd4: tx_data = 8'h52; // R
                    4'd5: tx_data = 8'h0d; // CR
                    4'd6: tx_data = 8'h0a; // LF
                    default: tx_data = 8'h20;
                endcase
            end
        endcase
    end

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            active      <= 1'b0;
            current_code <= 3'd4;
            char_index  <= 4'd0;
        end
        else if (!active) begin
            if (response_start) begin
                active       <= 1'b1;
                current_code <= response_code;
                char_index   <= 4'd0;
            end
        end
        else if (tx_start) begin
            if (char_index == message_length - 1'b1) begin
                active <= 1'b0;
            end
            else begin
                char_index <= char_index + 1'b1;
            end
        end
    end

endmodule
