`timescale 1ns / 1ps
// start로 전송을 시작하고 reset로 초기화함.
module master_top #(
    parameter integer HALF_PERIOD = 50,
    parameter integer STABLE_CYCLES = 1000000,
    parameter integer MAX_POLLS = 1000
)(
    input clk, 
    input start, 
    input reset, 
    input spi_miso,
    output spi_sclk, 
    output spi_mosi, 
    output spi_cs_n, 
    output [15:0] led
);
    // -------- 비동기 신호를 동기화하는데 사용 (동기화 회로) ---------
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync = 2'b11;
    always @(posedge clk or posedge reset)
        if (reset) reset_sync <= 2'b11;

        // 리셋 해제 동기화 (2단 플립플롭)
        else reset_sync <= {reset_sync[0], 1'b0};

    wire reset_synced = reset_sync[1];
    wire press, button_level, byte_start, byte_done, byte_busy;
    wire [7:0] byte_tx, byte_rx, sensor_data;
    wire [7:0] distance_high, distance_low, distance_status;
    wire data_valid, timeout, protocol_error;

    // 버튼 디바운스 모듈 안에 parameter 지정 STABLE_CYCLES
    // 괄호 안에 어떤 값을 쓸지 지정 
    button_debounce10ms #(
        .STABLE_CYCLES(STABLE_CYCLES)
        ) 
    button_inst 
    (
        .clk(clk), 
        .reset(reset_synced), 
        .button(start), 
        .level(button_level), 
        .pulse(press)
    );

    master_controller #(
        .MAX_POLLS(MAX_POLLS)
        ) 
    controller_inst (
        .clk(clk), 
        .reset(reset_synced), 
        .start(press), 
        .byte_done(byte_done), 
        .byte_rx(byte_rx),
        .byte_start(byte_start), 
        .byte_tx(byte_tx), 
        .cs_n(spi_cs_n),
        .sensor_data(sensor_data), 
        .distance_high(distance_high),
        .distance_low(distance_low),
        .distance_status(distance_status),
        .data_valid(data_valid), .timeout(timeout),
        .protocol_error(protocol_error)
    );

    master_byte #(
        .HALF_PERIOD(HALF_PERIOD)
        ) 
    byte_inst (
        .clk(clk), 
        .reset(reset_synced), 
        .start(byte_start), 
        .tx_data(byte_tx), 
        .miso(spi_miso),
        .sclk(spi_sclk), 
        .mosi(spi_mosi), 
        .rx_data(byte_rx), 
        .busy(byte_busy), 
        .done(byte_done)
        );

    // LED 8은 타임아웃, LED 9는 응답 오류를 표시함.
    assign led = {6'b0, protocol_error, timeout, sensor_data};

endmodule
