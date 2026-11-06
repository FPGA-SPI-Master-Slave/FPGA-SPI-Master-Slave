`timescale 1ns / 1ps

module hcsr04_controller #(
    parameter TRIG_US = 10,
    parameter TIMEOUT_US = 30_000,
    parameter MIN_CM = 2,
    parameter MAX_CM = 400
) (
    input clk,
    input reset,
    input tick,         //1us 주기
    input start,
    input echo,

    output reg trig,
    output busy,
    output reg [15:0] distance_cm,
    output reg [2:0] status,
    output reg hcsr04_done  //측정 종료 신호(정상/타임 아웃/범위 초과)
    );

    localparam [2:0] 
        S_IDLE = 3'd0,
        S_TRIGGER = 3'd1,
        S_WAIT_ECHO = 3'd2,
        S_MEASURE = 3'd3,
        S_CALCULATE = 3'd4,
        S_REPORT = 3'd5,
        S_CHECK = 3'd6;

    localparam [2:0]
        ST_NO_DATA = 3'd0,
        ST_OK = 3'd1,
        ST_NO_ECHO = 3'd2,
        ST_ECHO_TIMEOUT = 3'd3,
        ST_OUT_OF_RANGE = 3'd4;


    reg [2:0] state, next_state;

    reg [15:0] trig_count_us;   //최대 30,000us, 16bit
    reg [15:0] wait_count_us;
    reg [15:0] echo_count_us;

    reg [15:0] calculated_cm_reg; // 나눗셈이 끝난 뒤의 거리(cm), 소수점 이하는 버림

    // us/58 = cm
    // 한 클럭에 나누면 계산 경로가 길어지므로, 이진수의 나눗셈을 한 자리씩 진행
    // 입력의 높은 자리부터 매 클럭 한 비트씩 처리하여 총 16클럭에 몫을 완성
    reg [15:0] divide_shift;     // 처음에는 Echo 시간, 계산 중에는 남은 입력과 구한 몫을 함께 보관
    reg [5:0] divide_remainder;  // 앞 단계에서 남은 나머지(0~57)
    reg [3:0] divide_step;       // 현재 처리할 단계: 0~15

    // 나머지를 두 배로 하고 다음 입력 비트를 붙인다. 최대 115이므로 7비트 필요
    wire [6:0] remainder_shift = {divide_remainder, divide_shift[15]};
    // 58 이상이면 이번 몫의 비트는 1, 58 미만이면 0
    wire quotient_bit = (remainder_shift >= 7'd58);
    // 몫이 1이면 58을 빼고, 0이면 나머지로 사용
    wire [6:0] remainder_next = quotient_bit ?
        remainder_shift - 7'd58 : remainder_shift;

    //외부 echo 입력 동기화 - 2stage flip-flop
    (* ASYNC_REG = "TRUE" *) reg echo_sync1;
    (* ASYNC_REG = "TRUE" *) reg echo_sync2;
    reg echo_prev;

    always @(posedge clk, posedge reset) begin
        if(reset) begin
            echo_sync1 <= 1'b0;
            echo_sync2 <= 1'b0;
            echo_prev <= 1'b0;
        end else begin
            echo_sync1 <= echo;
            echo_sync2 <= echo_sync1;
            echo_prev <= echo_sync2;
        end
    end

    wire echo_rise =  echo_sync2 & ~echo_prev;
    wire echo_fall = ~echo_sync2 &  echo_prev;

    assign busy = (state != S_IDLE);

    //상태 결정
    always @(*) begin
        next_state = state; //기본값: 현재 상태 유지

        case(state)
            S_IDLE:
                if(start)
                    next_state = S_TRIGGER;
            
            S_TRIGGER:
                if(tick && trig_count_us == TRIG_US - 1)
                    next_state = S_WAIT_ECHO;

            S_WAIT_ECHO:
                if(echo_rise)
                    next_state = S_MEASURE;
                else if(tick && wait_count_us == TIMEOUT_US - 1)
                    next_state = S_REPORT;

            S_MEASURE:
                if(echo_fall)
                    next_state = S_CALCULATE;
                else if(tick && echo_count_us == TIMEOUT_US - 1)
                    next_state = S_REPORT;

            S_CALCULATE:
                if(divide_step == 4'd15)
                    next_state = S_CHECK;

            S_CHECK: next_state = S_REPORT;

            S_REPORT: next_state = S_IDLE;
            
            default: next_state = S_IDLE;
        endcase      
    end

    //측정 FSM
    always @(posedge clk, posedge reset) begin
        if(reset) begin
            state <= S_IDLE;
            trig <= 1'b0;
            trig_count_us <= 16'd0;
            wait_count_us <= 16'd0;
            echo_count_us <= 16'd0;
            distance_cm <= 16'd0;
            status <= ST_NO_DATA;
            hcsr04_done <= 1'b0;
            calculated_cm_reg <= 16'd0;
            divide_shift <= 16'd0;
            divide_remainder <= 6'd0;
            divide_step <= 4'd0;
        end else begin
            state <= next_state;
            hcsr04_done <= 1'b0;    //result_done 기본값 0

            case(state)
                S_IDLE: begin
                    trig <= 1'b0;

                    if(start) begin
                        trig <= 1'b1;
                        trig_count_us <= 16'd0;
                        wait_count_us <= 16'd0;
                        echo_count_us <= 16'd0;
                    end
                end
                
                S_TRIGGER: begin
                    if(tick) begin
                        if(trig_count_us == TRIG_US - 1) begin
                            trig <= 1'b0;
                            trig_count_us <= 16'd0;
                            wait_count_us <= 16'd0;
                        end else begin
                            trig_count_us <= trig_count_us + 1'b1;
                        end
                    end
                end

                S_WAIT_ECHO: begin
                    if(echo_rise)
                        echo_count_us <= 16'd0;
                    else if(tick && wait_count_us != TIMEOUT_US - 1)
                        wait_count_us <= wait_count_us + 1'b1;
                    
                    if(!echo_rise && tick && wait_count_us == TIMEOUT_US -1) begin
                        distance_cm <= 16'd0;
                        status <= ST_NO_ECHO;
                    end
                end

                S_MEASURE: begin
                    if(echo_fall) begin
                        // Echo 측정이 끝나면 나눌 시간을 복사하고 계산을 준비한다.
                        divide_shift <= echo_count_us;
                        divide_remainder <= 6'd0;
                        divide_step <= 4'd0;
                    end
                    if(!echo_fall && tick) begin
                        if(echo_count_us == TIMEOUT_US - 1) begin
                            distance_cm <= 16'b0;
                            status <= ST_ECHO_TIMEOUT;
                        end else begin
                            echo_count_us <= echo_count_us + 1'b1;
                        end
                    end
                end

                S_CALCULATE: begin
                    // 높은 자리의 입력 비트를 처리한 뒤 왼쪽으로 밀고, 낮은 자리에 몫 한 비트를 붙임
                    divide_shift <= {divide_shift[14:0], quotient_bit};
                    divide_remainder <= remainder_next[5:0];
                    divide_step <= divide_step + 1'b1;
                    // 마지막(16번째) 비트까지 반영한 몫을 저장
                    // divide_shift만 읽으면 <= 갱신 전 값이라 마지막 비트가 빠지므로
                    if(divide_step == 4'd15)
                        calculated_cm_reg <= {divide_shift[14:0], quotient_bit};
                end

                S_CHECK: begin
                    // 완성된 거리를 다음 클럭에서 판정하여 나눗셈과 범위 비교의 경로를 분리
                    if (calculated_cm_reg < MIN_CM ||
                        calculated_cm_reg > MAX_CM) begin
                        distance_cm <= 16'd0;
                        status <= ST_OUT_OF_RANGE;
                    end else begin
                        distance_cm <= calculated_cm_reg;
                        status <= ST_OK;
                    end
                end

                S_REPORT: begin
                    hcsr04_done <= 1'b1;
                end

                default: trig <= 1'b0;
            endcase
        end
        
    end

endmodule
