`timescale 1ns / 1ps

module measure_scheduler #(
    parameter MEASURE_PERIOD_US = 100_000
) (
    input clk,
    input reset,
    input tick,    // 1us마다 1클럭 HIGH
    input busy,    // hcsr04_controller의 busy

    output reg  start    // 측정 시작 요청: 1클럭 펄스
    );

    localparam COUNT_WIDTH =
        (MEASURE_PERIOD_US <= 1) ? 1 : $clog2(MEASURE_PERIOD_US);

    reg [COUNT_WIDTH-1:0] period_count_us;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            period_count_us <= {COUNT_WIDTH{1'b0}};
            start           <= 1'b0;
        end else begin
            start <= 1'b0;

            if (tick) begin
                if (period_count_us == MEASURE_PERIOD_US - 1) begin
                    if (!busy) begin
                        // 주기가 지났고 센서가 대기 중이면 측정 요청
                        start           <= 1'b1;
                        period_count_us <= {COUNT_WIDTH{1'b0}};
                    end
                    // busy=1이면 최댓값에서 대기
                end else begin
                    period_count_us <= period_count_us + 1'b1;
                end
            end
        end
    end

endmodule