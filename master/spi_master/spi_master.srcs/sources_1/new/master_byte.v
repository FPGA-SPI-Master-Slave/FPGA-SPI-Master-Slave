`timescale 1ns / 1ps
// SPI 모드 0, MSB 우선 전송. 모든 상태는 시스템 클럭으로 구동함.
module master_byte #(parameter HALF_PERIOD = 50)(
    input clk, input reset, input start, input [7:0] tx_data, input miso,
    output reg sclk, output reg mosi, output reg [7:0] rx_data,
    output reg busy, output reg done
);
    reg [31:0] divider;
    reg [2:0] bit_count;
    reg [7:0] tx_shift, rx_shift;
    always @(posedge clk) begin
        if (reset) begin
            divider <= 0; bit_count <= 0; tx_shift <= 0; rx_shift <= 0;
            sclk <= 0; mosi <= 0; rx_data <= 0; busy <= 0; done <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                sclk <= 0;
                if (start) begin
                    busy <= 1; divider <= 0; bit_count <= 0;
                    tx_shift <= tx_data; rx_shift <= 0; mosi <= tx_data[7];
                end
            end else if (divider == HALF_PERIOD - 1) begin
                divider <= 0;
                if (!sclk) begin
                    // 상승 에지에서 MISO를 샘플링함.
                    sclk <= 1; rx_shift <= {rx_shift[6:0], miso};
                end else begin
                    // 하강 에지에서 다음 MOSI 비트를 출력함.
                    sclk <= 0;
                    if (bit_count == 7) begin
                        rx_data <= rx_shift; busy <= 0; done <= 1;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                        tx_shift <= {tx_shift[6:0], 1'b0};
                        mosi <= tx_shift[6];
                    end
                end
            end else divider <= divider + 1'b1;
        end
    end
endmodule
