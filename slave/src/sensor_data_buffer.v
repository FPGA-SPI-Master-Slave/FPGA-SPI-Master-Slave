`timescale 1ns / 1ps

module sensor_data_buffer(
    input clk,
    input reset,

    input hcsr04_done,
    input [15:0] hcsr04_dist,
    input [2:0] hcsr04_status,

    output reg [15:0] hcsr04_data,
    output reg [2:0] status,
    output reg valid,
    output reg sh_buf_updated  //버퍼 갱신 신호
    );

    localparam [2:0] ST_NO_DATA = 3'd0;

    always @(posedge clk, posedge reset) begin
        if(reset) begin
            hcsr04_data <= 16'd0;
            status <= ST_NO_DATA;
            valid <= 1'b0;
            sh_buf_updated <= 1'b0;
        end else begin
            sh_buf_updated <= 1'b0;

            if(hcsr04_done) begin
                hcsr04_data <= hcsr04_dist;
                status <= hcsr04_status;
                valid <= 1'b1;
                sh_buf_updated <= 1'b1;
            end
        end
    end
endmodule
