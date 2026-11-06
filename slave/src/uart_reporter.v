`timescale 1ns / 1ps

module uart_reporter (
    input  wire        clk,
    input  wire        reset,

    // sensor_result_fifo
    input  wire [18:0] fifo_data,   // {status[2:0], distance_cm[15:0]}
    input  wire        fifo_empty,
    output wire        fifo_read,

    // uart_tx
    input  wire        tx_busy,
    input  wire        tx_done,
    output reg  [7:0]  tx_data,
    output reg         tx_start
);

    localparam [2:0]
        S_IDLE      = 3'd0,
        S_FORMAT    = 3'd1,
        S_SEND_BYTE = 3'd2,
        S_WAIT_DONE = 3'd3,
        S_NEXT_CHAR = 3'd4;

    localparam [2:0]
        ST_NO_DATA      = 3'd0,
        ST_OK           = 3'd1,
        ST_NO_ECHO      = 3'd2,
        ST_ECHO_TIMEOUT = 3'd3,
        ST_OUT_OF_RANGE = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;

    reg [15:0] distance_snapshot;
    reg [2:0]  status_snapshot;

    reg [7:0] digit_thousands;
    reg [7:0] digit_hundreds;
    reg [7:0] digit_tens;
    reg [7:0] digit_ones;

    reg [5:0] char_index;
    reg [4:0] status_length;

    wire [5:0] last_char_index = 6'd14 + status_length + 6'd1;
    wire [7:0] current_char;

    // IDLE에서 FIFO가 비어 있지 않으면 현재 항목을 가져옴.
    // FIFO와 Reporter가 같은 상승 에지에서 각각 pop/복사를 수행.
    assign fifo_read = (state == S_IDLE) && !fifo_empty;

    // 상태 문구 길이
    always @(*) begin
        case (status_snapshot)
            ST_OK:           status_length = 5'd2;   // OK
            ST_NO_ECHO:      status_length = 5'd7;   // NO_ECHO
            ST_ECHO_TIMEOUT: status_length = 5'd12;  // ECHO_TIMEOUT
            ST_OUT_OF_RANGE: status_length = 5'd11;  // RANGE_ERROR
            default:         status_length = 5'd7;   // NO_DATA
        endcase
    end
    /* 
        상태 문구에서 한 문자 선택
        index는 상태 문구의 첫 글자 기준으로 0부터 시작
    */
    function [7:0] status_char;
        input [2:0] status_value;
        input [4:0] index;
        begin
            status_char = "?";

            case (status_value)
                ST_OK: begin
                    case (index)
                        0: status_char = "O";
                        1: status_char = "K";
                    endcase
                end

                ST_NO_ECHO: begin
                    case (index)
                        0: status_char = "N";
                        1: status_char = "O";
                        2: status_char = "_";
                        3: status_char = "E";
                        4: status_char = "C";
                        5: status_char = "H";
                        6: status_char = "O";
                    endcase
                end

                ST_ECHO_TIMEOUT: begin
                    case (index)
                         0: status_char = "E";
                         1: status_char = "C";
                         2: status_char = "H";
                         3: status_char = "O";
                         4: status_char = "_";
                         5: status_char = "T";
                         6: status_char = "I";
                         7: status_char = "M";
                         8: status_char = "E";
                         9: status_char = "O";
                        10: status_char = "U";
                        11: status_char = "T";
                    endcase
                end

                ST_OUT_OF_RANGE: begin
                    case (index)
                         0: status_char = "R";
                         1: status_char = "A";
                         2: status_char = "N";
                         3: status_char = "G";
                         4: status_char = "E";
                         5: status_char = "_";
                         6: status_char = "E";
                         7: status_char = "R";
                         8: status_char = "R";
                         9: status_char = "O";
                        10: status_char = "R";
                    endcase
                end

                default: begin
                    case (index)
                        0: status_char = "N";
                        1: status_char = "O";
                        2: status_char = "_";
                        3: status_char = "D";
                        4: status_char = "A";
                        5: status_char = "T";
                        6: status_char = "A";
                    endcase
                end
            endcase
        end
    endfunction

    /* 
    현재 보낼 문자 선택
    0~13: "DIST=0123 cm, "
    14~ : 상태 문구
    이후: CR, LF
    */
    reg [7:0] selected_char;

    always @(*) begin
        selected_char = "?";

        case (char_index)
             0: selected_char = "D";
             1: selected_char = "I";
             2: selected_char = "S";
             3: selected_char = "T";
             4: selected_char = "=";

             5: selected_char = digit_thousands;
             6: selected_char = digit_hundreds;
             7: selected_char = digit_tens;
             8: selected_char = digit_ones;

             9: selected_char = " ";
            10: selected_char = "c";
            11: selected_char = "m";
            12: selected_char = ",";
            13: selected_char = " ";

            default: begin
                if (char_index < 6'd14 + status_length)
                    selected_char =
                        status_char(status_snapshot, char_index - 6'd14);
                else if (char_index == 6'd14 + status_length)
                    selected_char = 8'h0D; // \r
                else if (char_index == 6'd15 + status_length)
                    selected_char = 8'h0A; // \n
            end
        endcase
    end

    assign current_char = selected_char;

    // 다음 상태 결정
    always @(*) begin
        next_state = state;

        case (state)
            S_IDLE:
                if (!fifo_empty)
                    next_state = S_FORMAT;

            S_FORMAT:
                next_state = S_SEND_BYTE;

            S_SEND_BYTE:
                if (!tx_busy)
                    next_state = S_WAIT_DONE;

            S_WAIT_DONE:
                if (tx_done)
                    next_state = S_NEXT_CHAR;

            S_NEXT_CHAR:
                if (char_index == last_char_index)
                    next_state = S_IDLE;
                else
                    next_state = S_SEND_BYTE;

            default:
                next_state = S_IDLE;
        endcase
    end

    // 데이터 스냅샷, 숫자 변환, UART 요청
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state              <= S_IDLE;

            distance_snapshot  <= 16'd0;
            status_snapshot    <= ST_NO_DATA;

            digit_thousands    <= "0";
            digit_hundreds     <= "0";
            digit_tens         <= "0";
            digit_ones         <= "0";

            char_index         <= 6'd0;
            tx_data            <= 8'd0;
            tx_start           <= 1'b0;
        end else begin
            state    <= next_state;
            tx_start <= 1'b0;  // 기본값: 전송 시작 펄스는 1클럭

            case (state)
                S_IDLE: begin
                    if (fifo_read) begin
                        // FIFO의 현재 맨 앞 항목을 복사
                        distance_snapshot <= fifo_data[15:0];
                        status_snapshot   <= fifo_data[18:16];
                        char_index        <= 6'd0;
                    end
                end

                S_FORMAT: begin
                    // 4자리 십진수 ASCII 변환
                    digit_thousands <=
                        8'h30 + ((distance_snapshot / 16'd1000) % 10);
                    //범위를 비교하여 ASCII 문자를 직접 선택하는 방식으로 변경
                    digit_hundreds <=
                        (distance_snapshot >= 16'd400) ? 8'h34 :
                        (distance_snapshot >= 16'd300) ? 8'h33 :
                        (distance_snapshot >= 16'd200) ? 8'h32 :
                        (distance_snapshot >= 16'd100) ? 8'h31 :
                                                        8'h30;
                    digit_tens <=
                        8'h30 + ((distance_snapshot / 16'd10) % 10);
                    digit_ones <=
                        8'h30 + (distance_snapshot % 10);
                end

                S_SEND_BYTE: begin
                    if (!tx_busy) begin
                        tx_data  <= current_char;
                        tx_start <= 1'b1;
                    end
                end

                S_NEXT_CHAR: begin
                    if (char_index != last_char_index)
                        char_index <= char_index + 1'b1;
                end

                default: begin
                    // 다른 상태에서는 출력 레지스터 유지
                end
            endcase
        end
    end

endmodule