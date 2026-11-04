`timescale 1ns / 1ps
// 버튼 입력을 동기화하고 안정된 누름에 펄스를 출력함.
module button_debounce10ms #(parameter integer STABLE_CYCLES = 1000000)(
    input clk, 
    input reset,
    input button, 
    output reg level, 
    output reg pulse
);
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    reg [31:0] count;

    always @(posedge clk) begin
        if (reset) begin 
            sync1 <= 0; 
            sync2 <= 0; 
        end
        else begin 
            sync1 <= button; 
            sync2 <= sync1; 
        end
    end

    // 버튼이 눌렸을 때 한 펄스만큼만 출력
    // level : 버튼을 누르고 있는지 아닌지
    always @(posedge clk) begin
        if (reset) begin 
            count <= 0; 
            level <= 0; 
            pulse <= 0; 
        end
        else begin
            pulse <= 0;
            if (sync2 == level) count <= 0;
            else if (count == STABLE_CYCLES - 1) begin
                count <= 0; 
                level <= sync2; 
                if (sync2) pulse <= 1;
            end 
            else count <= count + 1'b1;
        end
    end

endmodule