
module debouncer #(parameter DEBOUNCE_LIMIT = 20'd999_999) (
    input      clk,
    input      reset,
    input [2:0] noisy_btn,  
    output reg [2:0] clean_btn
);
    reg [19:0] r_count;
    reg [2:0] r_btn_state = 0;

    //--- start 2단 FF 동기화기
    reg r_sync1, r_sync2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_sync1 <= 1'b0;
            r_sync2 <= 1'b0;
        end else begin
            r_sync1 <= noisy_btn;   // 메타스터빌리티가 생길 수 있는 FF
            r_sync2 <= r_sync1;     // 안정된 값 -> 아래 디바운스 로직에서 사용
        end                         // 비동기 입력은 2단 FF 동기화 후 FSM에 투입
    end
    //--------------

    always @(posedge clk or posedge reset) begin
        if (reset) begin   // active-high reset
            r_count <= 0;
            r_btn_state <= 0;
            clean_btn <= 0;
        end else if (r_sync2 == r_btn_state) begin  
            r_count <= 0;
        end else begin
            if (r_count < DEBOUNCE_LIMIT)  
                r_count <= r_count + 1;
            else begin  
                r_btn_state <= r_sync2;   // 2단 FF 
                clean_btn <= r_sync2;     // 2단 FF 
                r_count <= 0;  // clear하면 다음 변경을 다시 감지할 수 있음
            end
        end
    end
endmodule