//cs가 low일 때 sclk가 100ms이상 오지 않으면 에러
//sclk를 받아 spi 통신을 할 때 led 점멸 -> 시간이 짧으므로 늘려서 점멸하도록 함
`timescale 1ns / 1ps

module spi_act_led #(
    parameter integer SYSCLK = 100_000_000,
    parameter integer SCLK_STALL_MS = 100,
    parameter integer HOLD_MS = 200,    //마지막 SPI 활동 이후 200ms동안 led hold
    parameter integer BLINK_HALF_MS = 100   //100ms마다 led 토글
) (
    input clk,
    input sclk,
    input reset,
    input cs_n,
    output activity_led,
    output reg sclk_stall_led
    );

    localparam integer SCLK_STALL_CYCLES = (SYSCLK / 1000) * SCLK_STALL_MS; //100ms: 10_000_000클럭
    localparam integer HOLD_CYCLES = (SYSCLK / 1000) * HOLD_MS;
    localparam integer BLINK_CYCLES = (SYSCLK / 1000) * BLINK_HALF_MS;

    //spi 신호를 sysclk에 동기화: 2-stage flip-flop
    (* ASYNC_REG = "TRUE" *) reg sclk_sync1;
    (* ASYNC_REG = "TRUE" *) reg sclk_sync2;
    (* ASYNC_REG = "TRUE" *) reg cs_sync1;
    (* ASYNC_REG = "TRUE" *) reg cs_sync2;

    reg prev_sclk;
    reg [31:0] quiet_count, hold_count, blink_count;
    reg blink_on;
    
    wire sclk_edge = sclk_sync2 ^ prev_sclk;    //sclk의 상승/하강 에지

    assign activity_led = (hold_count != 0) && blink_on;

    always @(posedge clk, posedge reset) begin
        if(reset) begin
            sclk_sync1 <= 0;
            sclk_sync2 <= 0;
            cs_sync1 <= 1'b1;
            cs_sync2 <= 1'b1;
            prev_sclk <= 0;
        end else begin
            sclk_sync1 <= sclk;
            sclk_sync2 <= sclk_sync1;

            cs_sync1 <= cs_n;
            cs_sync2 <= cs_sync1;

            prev_sclk <= sclk_sync2;    //이전 sclk값 저장
        end
    end

    always @(posedge clk, posedge reset) begin
        if(reset) begin
            quiet_count <= 0;
            hold_count <= 0;
            blink_count <= 0;
            blink_on <= 0;
            sclk_stall_led <= 0;            
        end else begin
            if(cs_sync2 || sclk_edge) begin //sclk 정지 감시: cs가 high이거나 sclk edge가 올 때 -> 정상
                quiet_count <= 0;
                sclk_stall_led <= 0;
            end else if (quiet_count < SCLK_STALL_CYCLES -1) begin
                quiet_count <= quiet_count + 1;
            end else sclk_stall_led <= 1;

            //cs가 low이고 sclk edge가 있을 때 led 점멸
            if(!cs_sync2 && sclk_edge)
                hold_count <= HOLD_CYCLES;
            else if(hold_count != 0)
                hold_count <= hold_count -1;
            
            if(hold_count == 0) begin
                blink_count <= 0;
                blink_on <= 1;
            end else if(blink_count == BLINK_CYCLES -1) begin
                blink_count <= 0;
                blink_on <= ~blink_on;
            end else blink_count <= blink_count + 1;
        end
    end
endmodule
