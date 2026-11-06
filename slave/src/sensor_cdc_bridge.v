`timescale 1ns / 1ps

module sensor_cdc_bridge(
    input clk,      //100MHz
    input sclk,     //1MHz
    input reset,

    input [15:0] hcsr04_dist,       //공유 버퍼에서 가져옴
    input [2:0] hcsr04_status,
    input hcsr04_valid,
    input hcsr04_updated,           //sh_buf_updated

    output reg [18:0] hcsr04_snapshot,   //sclk 도메인 (hcsr04 거리+상태 19bit)
    output reg hcsr04_snapshot_valid   //sclk 도메인
    );

    reg [18:0] hcsr04_dist_stat;
    reg req_toggle, ack_toggle;
    reg pending;

    // SCLK → 100MHz: ack 신호 동기화
    (* ASYNC_REG = "TRUE" *) reg ack_sync1;
    (* ASYNC_REG = "TRUE" *) reg ack_sync2;

    // 100MHz → SCLK: req 신호 동기화
    (* ASYNC_REG = "TRUE" *) reg req_sync1;
    (* ASYNC_REG = "TRUE" *) reg req_sync2;

    wire new_result = hcsr04_updated && hcsr04_valid;   //새로운 측정 결과가 공유버퍼 담김
    wire transfer_done = (req_toggle == ack_sync2);

    //100MHz 도메인
    always @(posedge clk, posedge reset) begin
        if(reset) begin
            hcsr04_dist_stat <= 19'd0;
            req_toggle       <= 1'b0;
            ack_sync1        <= 1'b0;
            ack_sync2        <= 1'b0;
            pending          <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;

            if(new_result)  //전달 중에 새로운 측정 결과 발생
                pending <= 1'b1;
            
            // 이전 전달이 끝나고 보낼 결과가 있으면 최신 공유 버퍼를 복사해옴
            if (transfer_done && (pending || new_result)) begin
                hcsr04_dist_stat <= {hcsr04_dist, hcsr04_status};
                req_toggle <= ~req_toggle;
                pending <= 1'b0;
            end
        end
    end

    // SCLK 도메인(1MHz)
    always @(posedge sclk, posedge reset)begin
        if(reset) begin
            req_sync1 <= 1'b0;
            req_sync2 <= 1'b0;
            ack_toggle <= 1'b0;
            hcsr04_snapshot <= 19'd0;
            hcsr04_snapshot_valid <= 1'b0;
        end else begin
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;

            //동기화된 요청값이 승인값과 다름 -> 새 데이터 도착을 의미
            if(req_sync2 != ack_toggle) begin
                hcsr04_snapshot <= hcsr04_dist_stat;
                hcsr04_snapshot_valid <= 1'b1;
                ack_toggle <= req_sync2;
            end
        end
    end
endmodule
