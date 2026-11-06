`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/05 13:05:16
// Design Name: 
// Module Name: oled_controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module oled_controller #(
    parameter integer RESET_CYCLES = 10000000,
    parameter integer REFRESH_CYCLES = 10000000
)(
    input clk, input reset,
    input [15:0] distance, input data_valid,
    input comm_error,
    output reg byte_start, output reg [7:0] byte_tx,
    input byte_done, input byte_error,
    output reg dc, output reg link_error, output reg initialized
);
    localparam RESET_WAIT=0, ACQUIRE=1, SEND=2, WAIT_BYTE=3, IDLE=4, CONVERT=5;
    localparam INIT_COUNT=25, CLEAR_COUNT=1048, DISPLAY_COUNT=33;
    reg [2:0] state;
    reg initializing;
    reg [10:0] index;
    reg [31:0] reset_count, refresh_count;
    reg [15:0] latest_distance, display_distance;
    reg has_value, update_due;
    reg latest_error, display_error, display_ready;
    reg [2:0] clear_page, digit_index, glyph_column;
    reg [7:0] clear_column;
    reg [19:0] decimal_digits, adjusted_digits;
    reg [3:0] convert_bit;
    integer decimal_index;
    reg [7:0] next_byte;
    reg next_dc;
    reg [3:0] digit;
    reg [39:0] glyph;

    function [7:0] init_byte;
        input [10:0] n;
        begin
            case (n)
                0: init_byte=8'hae;  1: init_byte=8'hd5;  2: init_byte=8'h80;
                3: init_byte=8'ha8;  4: init_byte=8'h3f;  5: init_byte=8'hd3;
                6: init_byte=8'h00;  7: init_byte=8'h40;  8: init_byte=8'h8d;
                9: init_byte=8'h14; 10: init_byte=8'h20; 11: init_byte=8'h02;
               12: init_byte=8'ha1; 13: init_byte=8'hc8; 14: init_byte=8'hda;
               15: init_byte=8'h12; 16: init_byte=8'h81; 17: init_byte=8'h7f;
               18: init_byte=8'hd9; 19: init_byte=8'hf1; 20: init_byte=8'hdb;
               21: init_byte=8'h40; 22: init_byte=8'ha4; 23: init_byte=8'ha6;
               24: init_byte=8'h2e;
               default: init_byte=8'h00;
            endcase
        end
    endfunction

    function [39:0] digit_glyph;
        input [3:0] value;
        begin
            case (value)
                0: digit_glyph=40'h3e5149453e;
                1: digit_glyph=40'h00427f4000;
                2: digit_glyph=40'h4261514946;
                3: digit_glyph=40'h2141494936;
                4: digit_glyph=40'h1814127f10;
                5: digit_glyph=40'h2745454539;
                6: digit_glyph=40'h3c4a494930;
                7: digit_glyph=40'h0171090503;
                8: digit_glyph=40'h3649494936;
                9: digit_glyph=40'h064949291e;
                default: digit_glyph=0;
            endcase
        end
    endfunction

    function [39:0] error_glyph;
        input integer character_index;
        begin
            case (character_index)
                0: error_glyph=40'h7f49494941;
                1, 2, 4: error_glyph=40'h7f09192946;
                3: error_glyph=40'h3e4141413e;
                default: error_glyph=0;
            endcase
        end
    endfunction

    function [39:0] ready_glyph;
        input integer character_index;
        begin
            case (character_index)
                0: ready_glyph=40'h7f09192946;
                1: ready_glyph=40'h7f49494941;
                2: ready_glyph=40'h7e1111117e;
                3: ready_glyph=40'h7f4141221c;
                4: ready_glyph=40'h0304780403;
                default: ready_glyph=0;
            endcase
        end
    endfunction

    always @* begin
        // 각 십진 자릿수를 병렬 보정하고 한 비트씩 변환함.
        adjusted_digits = decimal_digits;
        for (decimal_index = 0; decimal_index < 5; decimal_index = decimal_index + 1)
            if (decimal_digits[decimal_index * 4 +: 4] >= 5)
                adjusted_digits[decimal_index * 4 +: 4] = decimal_digits[decimal_index * 4 +: 4] + 4'd3;
    end

    always @* begin
        next_byte = 0;
        next_dc = 0;
        digit = 0; glyph = 0;
        if (initializing) begin
            if (index < INIT_COUNT) next_byte = init_byte(index);
            // 화면을 모두 지운 뒤 마지막 명령으로 화면을 켬.
            else if (index == INIT_COUNT + CLEAR_COUNT) next_byte = 8'haf;
            else begin
                if (clear_column == 0) next_byte = {5'b10110, clear_page};
                else if (clear_column == 1) next_byte = 8'h00;
                else if (clear_column == 2) next_byte = 8'h10;
                else begin next_dc = 1; next_byte = 0; end
            end
        end else begin
            if (index == 0) next_byte = 8'hb0;
            else if (index == 1) next_byte = 8'h00;
            else if (index == 2) next_byte = 8'h10;
            else begin
                next_dc = 1;
                case (digit_index)
                    0: digit = decimal_digits[19:16];
                    1: digit = decimal_digits[15:12];
                    2: digit = decimal_digits[11:8];
                    3: digit = decimal_digits[7:4];
                    default: digit = decimal_digits[3:0];
                endcase
                glyph = display_error ? error_glyph(digit_index) :
                        display_ready ? ready_glyph(digit_index) : digit_glyph(digit);
                case (glyph_column)
                    0: next_byte = glyph[39:32];
                    1: next_byte = glyph[31:24];
                    2: next_byte = glyph[23:16];
                    3: next_byte = glyph[15:8];
                    4: next_byte = glyph[7:0];
                    default: next_byte = 0;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= RESET_WAIT;
            initializing <= 1;
            index <= 0;
            reset_count <= 0;
            refresh_count <= 0;
            latest_distance <= 0;
            display_distance <= 0;
            clear_page <= 0;
            clear_column <= 0;
            digit_index <= 0;
            glyph_column <= 0;
            decimal_digits <= 0;
            convert_bit <= 0;
            byte_tx <= 0;
            dc <= 0;
            has_value <= 0;
            update_due <= 0;
            latest_error <= 0;
            display_error <= 0;
            display_ready <= 0;
            link_error <= 0;
            initialized <= 0;
            byte_start <= 0;
        end else begin
            byte_start <= 0;
            // 새 정상 데이터를 받을 때까지 오류 표시를 유지함.
            if (comm_error) begin
                latest_error <= 1;
                if (!latest_error) update_due <= 1;
            end else if (data_valid) begin
                latest_distance <= distance;
                has_value <= 1;
                latest_error <= 0;
                if (!has_value || latest_error) update_due <= 1;
            end
            if (refresh_count >= REFRESH_CYCLES - 1) begin
                refresh_count <= 0;
                if (has_value || latest_error) update_due <= 1;
            end else refresh_count <= refresh_count + 1'b1;
            case (state)
                RESET_WAIT: if (reset_count >= RESET_CYCLES - 1) begin
                    state <= ACQUIRE;
                end else reset_count <= reset_count + 1'b1;
                // 바이트 계산 결과를 저장한 다음 전송을 요청함.
                ACQUIRE: begin
                    byte_tx <= next_byte;
                    dc <= next_dc;
                    state <= SEND;
                end
                SEND: begin byte_start <= 1; state <= WAIT_BYTE; end
                WAIT_BYTE: if (byte_done) begin
                    if (byte_error) begin
                        // OLED 미응답 시 초기화부터 다시 시도함.
                        link_error <= 1;
                        initialized <= 0;
                        initializing <= 1;
                        index <= 0;
                        clear_page <= 0;
                        clear_column <= 0;
                        reset_count <= 0;
                        update_due <= has_value || latest_error || comm_error || data_valid;
                        state <= RESET_WAIT;
                    end else if ((initializing && index == INIT_COUNT + CLEAR_COUNT) ||
                        (!initializing && index == DISPLAY_COUNT - 1)) begin
                        link_error <= 0;
                        if (initializing) initialized <= 1;
                        // 초기화 후 수신 대기 상태도 화면에 표시함.
                        if (initializing) update_due <= 1;
                        initializing <= 0;
                        index <= 0;
                        state <= IDLE;
                    end else begin
                        index <= index + 1'b1;
                        if (initializing && index >= INIT_COUNT) begin
                            if (clear_column == 130) begin
                                clear_column <= 0;
                                clear_page <= clear_page + 1'b1;
                            end else clear_column <= clear_column + 1'b1;
                        end else if (!initializing && index >= 3) begin
                            if (glyph_column == 5) begin
                                glyph_column <= 0;
                                digit_index <= digit_index + 1'b1;
                            end else glyph_column <= glyph_column + 1'b1;
                        end
                        state <= ACQUIRE;
                    end
                end
                IDLE: if (update_due) begin
                    // 전송 중 숫자와 오류 문구가 섞이지 않도록 고정함.
                    display_error <= comm_error || (latest_error && !data_valid);
                    display_ready <= !(has_value || data_valid || latest_error || comm_error);
                    display_distance <= data_valid ? distance : latest_distance;
                    decimal_digits <= 0;
                    convert_bit <= 0;
                    digit_index <= 0;
                    glyph_column <= 0;
                    update_due <= 0;
                    refresh_count <= 0;
                    index <= 0;
                    state <= CONVERT;
                end
                CONVERT: begin
                    decimal_digits <= {adjusted_digits[18:0], display_distance[15 - convert_bit]};
                    if (convert_bit == 15) state <= ACQUIRE;
                    else convert_bit <= convert_bit + 1'b1;
                end
                default: state <= RESET_WAIT;
            endcase
        end
    end
endmodule
