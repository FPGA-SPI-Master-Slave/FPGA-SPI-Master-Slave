`timescale 1ns / 1ps

// SPI Mode 0, MSB 우선, 8비트 명령과 8비트 응답 처리
module spi_slave (
    input  sclk,
    input  reset,
    input  cs_n,
    input  mosi,
    output miso
);
    localparam S_CMD  = 1'b0;
    localparam S_RESP = 1'b1;

    localparam [7:0] CMD_STATUS = 8'h10;
    localparam [7:0] CMD_SEND   = 8'h20;
    localparam [7:0] RESP_READY = 8'h01;
    localparam [7:0] TEST_DATA  = 8'hA5;

    reg       r_state;
    reg [2:0] r_bit_cnt;
    reg [7:0] r_rx_shift;
    reg [7:0] r_response;
    reg       r_tx_load;
    reg [7:0] r_tx_shift;

    wire [7:0] w_rx_byte;
    assign w_rx_byte = {r_rx_shift[6:0], mosi};

    // MOSI는 상승 에지에서 수신했음.
    always @(posedge sclk or posedge reset or posedge cs_n) begin
        if (reset || cs_n) begin
            r_state    <= S_CMD;
            r_bit_cnt  <= 3'd0;
            r_rx_shift <= 8'h00;
            r_response <= 8'h00;
            r_tx_load  <= 1'b0;
        end else begin
            r_tx_load <= 1'b0;

            if (r_bit_cnt == 3'd7)
                r_bit_cnt <= 3'd0;
            else
                r_bit_cnt <= r_bit_cnt + 3'd1;

            case (r_state)
                S_CMD: begin
                    r_rx_shift <= w_rx_byte;

                    if (r_bit_cnt == 3'd7) begin
                        case (w_rx_byte)
                            CMD_STATUS: r_response <= RESP_READY;
                            CMD_SEND:   r_response <= TEST_DATA;
                            default:    r_response <= 8'h00;
                        endcase

                        r_tx_load <= 1'b1;
                        r_state   <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (r_bit_cnt == 3'd7)
                        r_state <= S_CMD;
                end
            endcase
        end
    end

    // MISO는 하강 에지에서 준비했음.
    always @(negedge sclk or posedge reset or posedge cs_n) begin
        if (reset || cs_n)
            r_tx_shift <= 8'h00;
        else if (r_tx_load)
            r_tx_shift <= r_response;
        else
            r_tx_shift <= {r_tx_shift[6:0], 1'b0};
    end

    // CS 비활성 구간에는 MISO를 해제했음.
    assign miso = cs_n ? 1'bz : r_tx_shift[7];
endmodule
