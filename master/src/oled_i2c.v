`timescale 1ns / 1ps
// 주소, 명령 구분, 화면 바이트를 한 I2C 거래로 전송함.
module oled_i2c #(
    parameter [6:0] ADDRESS = 7'h3c,
    parameter integer AUTO_ADDRESS = 1,
    parameter integer QUARTER_PERIOD = 250,
    parameter integer TIMEOUT_CYCLES = 1000000
)(
    input clk, 
    input reset, 
    input start,
    input [7:0] tx_data, 
    input dc,
    inout wire scl, 
    inout wire sda,
    output reg busy, 
    output reg done, 
    output reg error,
    output reg address_ack
);
    localparam IDLE=0, 
               START_SETUP=1, 
               START_HOLD=2,
               TX_HOLD=3, 
               TX_SETUP=4, 
               TX_RISE=5, 
               TX_HIGH=6,
               ACK_HOLD=7, 
               ACK_SETUP=8, 
               ACK_RISE=9, 
               ACK_HIGH=10,
               STOP_HOLD=11, 
               STOP_SETUP=12, 
               STOP_RISE=13,
               STOP_HIGH=14, 
               BUS_FREE=15;

    reg [3:0] state;
    reg scl_low, sda_low, packet_error;
    reg [31:0] count, timeout_count;
    reg [7:0] payload, control, shift;
    reg [2:0] bit_index;
    reg [1:0] packet_index;
    reg [6:0] selected_address;
    
    (* ASYNC_REG = "TRUE" *) reg [1:0] scl_sync, sda_sync;

    // 높은 전압을 직접 구동하지 않고 풀업으로 선을 해제함.
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (reset) begin
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
        end else begin
            scl_sync <= {scl_sync[0], scl};
            sda_sync <= {sda_sync[0], sda};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            scl_low <= 0;
            sda_low <= 0;
            busy <= 0;
            done <= 0;
            error <= 0;
            address_ack <= 0;
            selected_address <= ADDRESS;
            packet_error <= 0;
            count <= 0;
            timeout_count <= 0;
            payload <= 0;
            control <= 0;
            shift <= 0;
            bit_index <= 7;
            packet_index <= 0;
        end else begin
            done <= 0;
            error <= 0;
            if (busy) timeout_count <= timeout_count + 1'b1;
            // 응답이 없거나 클럭이 계속 낮으면 두 선을 해제함.
            if (busy && timeout_count >= TIMEOUT_CYCLES - 1) begin
                address_ack <= 0;
                state <= IDLE;
                scl_low <= 0;
                sda_low <= 0;
                busy <= 0;
                done <= 1;
                error <= 1;
            end else case (state)
                IDLE: if (start) begin
                    payload <= tx_data;
                    control <= dc ? 8'h40 : 8'h00;
                    shift <= {selected_address, 1'b0};
                    bit_index <= 7;
                    packet_index <= 0;
                    packet_error <= 0;
                    count <= 0;
                    timeout_count <= 0;
                    busy <= 1;
                    state <= START_SETUP;
                end
                START_SETUP: begin
                    if (!scl_sync[1] || !sda_sync[1]) count <= 0;
                    else if (count == 2 * QUARTER_PERIOD - 1) begin
                        sda_low <= 1;
                        count <= 0;
                        state <= START_HOLD;
                    end else count <= count + 1'b1;
                end
                START_HOLD: if (count == 2 * QUARTER_PERIOD - 1) begin
                    scl_low <= 1;
                    count <= 0;
                    state <= TX_HOLD;
                end else count <= count + 1'b1;
                TX_HOLD: if (count == QUARTER_PERIOD - 1) begin
                    sda_low <= !shift[bit_index];
                    count <= 0;
                    state <= TX_SETUP;
                end else count <= count + 1'b1;
                TX_SETUP: if (count == QUARTER_PERIOD - 1) begin
                    scl_low <= 0;
                    count <= 0;
                    state <= TX_RISE;
                end else count <= count + 1'b1;
                TX_RISE: if (scl_sync[1]) state <= TX_HIGH;
                TX_HIGH: if (count == 2 * QUARTER_PERIOD - 1) begin
                    scl_low <= 1;
                    count <= 0;
                    if (bit_index == 0) state <= ACK_HOLD;
                    else begin
                        bit_index <= bit_index - 1'b1;
                        state <= TX_HOLD;
                    end
                end else count <= count + 1'b1;
                ACK_HOLD: if (count == QUARTER_PERIOD - 1) begin
                    sda_low <= 0;
                    count <= 0;
                    state <= ACK_SETUP;
                end else count <= count + 1'b1;
                ACK_SETUP: if (count == QUARTER_PERIOD - 1) begin
                    scl_low <= 0;
                    count <= 0;
                    state <= ACK_RISE;
                end else count <= count + 1'b1;
                ACK_RISE: if (scl_sync[1]) state <= ACK_HIGH;
                ACK_HIGH: if (count == 2 * QUARTER_PERIOD - 1) begin
                    scl_low <= 1;
                    count <= 0;
                    if (sda_sync[1]) begin
                        packet_error <= 1;
                        if (packet_index == 0) begin
                            address_ack <= 0;
                            // 주소 미응답일 때만 SSD1306의 다른 주소를 재시도함.
                            if (AUTO_ADDRESS && (selected_address == 7'h3c || selected_address == 7'h3d))
                                selected_address <= selected_address ^ 7'h01;
                        end
                        state <= STOP_HOLD;
                    end else if (packet_index == 2) state <= STOP_HOLD;
                    else begin
                        if (packet_index == 0) address_ack <= 1;
                        shift <= packet_index == 0 ? control : payload;
                        packet_index <= packet_index + 1'b1;
                        bit_index <= 7;
                        state <= TX_HOLD;
                    end
                end else count <= count + 1'b1;
                STOP_HOLD: if (count == QUARTER_PERIOD - 1) begin
                    sda_low <= 1;
                    count <= 0;
                    state <= STOP_SETUP;
                end else count <= count + 1'b1;
                STOP_SETUP: if (count == QUARTER_PERIOD - 1) begin
                    scl_low <= 0;
                    count <= 0;
                    state <= STOP_RISE;
                end else count <= count + 1'b1;
                STOP_RISE: if (scl_sync[1]) state <= STOP_HIGH;
                STOP_HIGH: if (count == 2 * QUARTER_PERIOD - 1) begin
                    sda_low <= 0;
                    count <= 0;
                    state <= BUS_FREE;
                end else count <= count + 1'b1;
                BUS_FREE: if (count == 2 * QUARTER_PERIOD - 1) begin
                    busy <= 0;
                    done <= 1;
                    error <= packet_error;
                    state <= IDLE;
                end else count <= count + 1'b1;
                default: begin
                    state <= IDLE;
                    scl_low <= 0;
                    sda_low <= 0;
                    busy <= 0;
                end
            endcase
        end
    end
endmodule
