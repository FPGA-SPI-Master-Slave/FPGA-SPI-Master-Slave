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
        S_REPORT = 3'd5;

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

    wire [15:0] calculated_cm = echo_count_us / 16'd58; //cm = us/58

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

            S_CALCULATE: next_state = S_REPORT;

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
                    if(calculated_cm < MIN_CM || calculated_cm > MAX_CM) begin
                        distance_cm <= 16'd0;
                        status <= ST_OUT_OF_RANGE;
                    end else begin
                        distance_cm <= calculated_cm;
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
