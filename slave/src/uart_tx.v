`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
) (
    input clk,
    input reset,

    input [7:0] tx_data,
    input tx_start,

    output reg tx,
    output tx_busy,
    output reg tx_done
    );

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam COUNT_WIDTH  = $clog2(CLKS_PER_BIT);

    localparam [1:0]
        S_IDLE  = 2'd0,
        S_START = 2'd1,
        S_DATA  = 2'd2,
        S_STOP  = 2'd3;

    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] data_reg;

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= S_IDLE;
            baud_count <= {COUNT_WIDTH{1'b0}};
            bit_index  <= 3'd0;
            data_reg   <= 8'd0;
            tx         <= 1'b1; // UART 대기 상태는 HIGH
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0; // 완료 펄스 기본값

            case (state)
                S_IDLE: begin
                    tx         <= 1'b1;
                    baud_count <= {COUNT_WIDTH{1'b0}};
                    bit_index  <= 3'd0;

                    if (tx_start) begin
                        data_reg <= tx_data; // 전송할 바이트 고정
                        tx       <= 1'b0;    // 시작 비트
                        state    <= S_START;
                    end
                end

                S_START: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        tx         <= data_reg[0]; // 첫 데이터 비트: LSB
                        state      <= S_DATA;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                S_DATA: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};

                        if (bit_index == 3'd7) begin
                            tx    <= 1'b1; // 정지 비트
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx        <= data_reg[bit_index + 1'b1];
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                S_STOP: begin
                    if (baud_count == CLKS_PER_BIT - 1) begin
                        baud_count <= {COUNT_WIDTH{1'b0}};
                        tx_done    <= 1'b1;
                        state      <= S_IDLE;
                        // tx는 HIGH 유지
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    tx    <= 1'b1;
                end
            endcase
        end
    end

endmodule