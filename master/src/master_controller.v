`timescale 1ns / 1ps
// 명령 다음 더미 바이트에서 상태 또는 센서 데이터를 수신함.
// 응답 타이밍은 슬레이브와 협의 필요.
module master_controller #(
    parameter [7:0] CMD_STATUS = 8'h10,
                    CMD_SEND = 8'h20,
                    RSP_BUSY = 8'h00, 
                    RSP_READY = 8'h01,
                    DUMMY = 8'h00,
    parameter integer MAX_POLLS = 1000
)(
    input clk, 
    input reset, 
    input start, 
    input byte_done, 
    input [7:0] byte_rx,
    output reg byte_start, 
    output reg [7:0] byte_tx, 
    output reg cs_n,
    output reg [7:0] sensor_data,
    output reg [7:0] distance_high,
    output reg [7:0] distance_low,
    output reg [7:0] distance_status,
    output reg data_valid,
    output reg timeout, 
    output reg protocol_error
);

    localparam IDLE=0, 
               STATUS_START=1, 
               STATUS_WAIT=2, 
               RESPONSE_START=3,
               RESPONSE_WAIT=4, 
               SEND_START=5, 
               SEND_WAIT=6,
               DATA_START=7, 
               DATA_WAIT=8, RESTART=9,
               DATA_LOW_START=10, DATA_LOW_WAIT=11,
               DATA_STATUS_START=12, DATA_STATUS_WAIT=13;

    reg [3:0] state;
    reg [31:0] polls;
    reg [7:0] high_pending, low_pending;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            cs_n <= 1;
            byte_start <= 0;
            byte_tx <= 0;
            sensor_data <= 0;
            distance_high <= 0;
            distance_low <= 0;
            distance_status <= 0;
            high_pending <= 0;
            low_pending <= 0;
            data_valid <= 0;
            timeout <= 0;
            protocol_error <= 0;
            polls <= 0;
        end else begin
            byte_start <= 0;
            data_valid <= 0;

            case (state)
                IDLE: if (start) begin
                    cs_n <= 0;
                    polls <= 0;
                    timeout <= 0;
                    protocol_error <= 0;
                    state <= STATUS_START;
                end
                STATUS_START: begin
                    byte_tx <= CMD_STATUS;
                    byte_start <= 1;
                    state <= STATUS_WAIT;
                end
                // 8비트를 전송하는데 시간이 필요하기 때문에 wait 필요.
                STATUS_WAIT: if (byte_done) state <= RESPONSE_START;

                RESPONSE_START: begin
                    byte_tx <= DUMMY;
                    byte_start <= 1;
                    state <= RESPONSE_WAIT;
                end
                RESPONSE_WAIT: if (byte_done) begin
                    if (byte_rx == RSP_READY) state <= SEND_START;
                    else if (byte_rx == RSP_BUSY) begin
                        if (polls + 1 >= MAX_POLLS) begin
                            timeout <= 1;
                            cs_n <= 1;
                            state <= IDLE;
                        end else begin
                            polls <= polls + 1'b1;
                            state <= STATUS_START;
                        end
                    end else begin
                        protocol_error <= 1;
                        cs_n <= 1;
                        state <= IDLE;
                    end
                end
                SEND_START: begin
                    byte_tx <= CMD_SEND;
                    byte_start <= 1;
                    state <= SEND_WAIT;
                end
                SEND_WAIT: if (byte_done) state <= DATA_START;
                
                DATA_START: begin
                    byte_tx <= DUMMY;
                    byte_start <= 1;
                    state <= DATA_WAIT;
                end
                DATA_WAIT: if (byte_done) begin
                    high_pending <= byte_rx;
                    state <= DATA_LOW_START;
                end
                DATA_LOW_START: begin
                    byte_tx <= DUMMY;
                    byte_start <= 1;
                    state <= DATA_LOW_WAIT;
                end
                DATA_LOW_WAIT: if (byte_done) begin
                    low_pending <= byte_rx;
                    state <= DATA_STATUS_START;
                end
                DATA_STATUS_START: begin
                    byte_tx <= DUMMY;
                    byte_start <= 1;
                    state <= DATA_STATUS_WAIT;
                end
                DATA_STATUS_WAIT: if (byte_done) begin
                    distance_high <= high_pending;
                    distance_low <= low_pending;
                    distance_status <= byte_rx;
                    sensor_data <= low_pending;
                    data_valid <= 1;
                    cs_n <= 1;
                    polls <= 0;
                    state <= RESTART;
                end
                RESTART: begin
                    cs_n <= 0;
                    state <= STATUS_START;
                end
                default: begin
                    cs_n <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
