`timescale 1ns / 1ps

module spi_slave(
    input sclk,     //1MHz
    input reset,
    input cs_n,     //Active Low
    input mosi,     //Master -> Slave
    output miso     //Slave -> Master
    );
    //상태 정의
    localparam S_CMD  = 1'b0;
    localparam S_RESP = 1'b1;  

    //master 명령어
    localparam [7:0] CMD_STATUS = 8'h10;
    localparam [7:0] CMD_SEND   = 8'h20;

    localparam [7:0] RESP_READY = 8'h01;
    localparam [7:0] TEST_DATA  = 8'hA5;
    
    reg r_state;            //명령 수신/응답 송신 상태
    reg [2:0] r_bit_cnt;    //8비트 송/수신 카운트

    reg [7:0] r_rx_shift;   //rx shift registor
    reg [7:0] r_rx_buf;     //rx 1바이트 명령 보관 버퍼
    reg r_rx_valid;         //rx 바이트 수신 완료(S_CMD일때)

    reg [7:0] r_tx_shift;   //tx shift reg.
    reg [7:0] r_tx_buf = TEST_DATA;     //tx 최신 데이터 보관 버퍼

    reg [7:0] r_response;   // 명령에 따라 응답할 값 보관(status의 응답이면 READY/BUSY send의 응답이면 tx_buf)
    reg r_tx_load;          //tx buf에서 tx shift regi로 응답 로드 지시

    wire [7:0] w_rx_byte;
    assign w_rx_byte = {r_rx_shift[6:0], mosi};     // 기존 수신값 하위 7비트 + 현재 mosi

    wire w_spi_reset;
    assign w_spi_reset = reset | cs_n;  //reset또는 cs 비활성화 시 SPI 프레임 초기화

    //SCLK 상승 에지에서 명령에 따라 응답 선택
    always @(posedge sclk, posedge w_spi_reset) begin
        if(w_spi_reset) begin
            r_state <= S_CMD;
            r_bit_cnt <= 3'd0;
            r_rx_shift <= 8'h00;
            r_rx_buf <= 8'h00;
            r_rx_valid <= 1'b0;
            r_response <= 8'h00;
            r_tx_load <= 1'b0;
        end else begin
            r_rx_valid <= 1'b0;
            r_tx_load <= 1'b0;

            if(r_bit_cnt == 3'd7)
                r_bit_cnt <= 3'b0;
            else r_bit_cnt <= r_bit_cnt + 1;

            case(r_state)
                S_CMD: begin
                    r_rx_shift <= w_rx_byte;    //rx shift reg에 mosi값 반영
                    if(r_bit_cnt == 3'd7) begin
                        r_rx_buf <= w_rx_byte;  //마지막 8비트까지 포함한 명령 바이트 저장
                        r_rx_valid <= 1'b1;     //수신 완료

                        case (w_rx_byte)    //명령
                            CMD_STATUS: //통신 연결 테스트용, CDC 미구현, 항상 ready 송신
                                r_response <= RESP_READY;
                            CMD_SEND: 
                                r_response <= r_tx_buf;  //테스트용 데이터 8'hA5
                            default: r_response <= 8'h00;   //알 수 없는 명령
                        endcase

                        r_tx_load <= 1'b1;  // 명령에 따라 선택한 response를 다음 하강 에지에서 로드하도록
                        r_state <= S_RESP;    // RESP 모드 전환
                    end
                end

                S_RESP: begin
                    if(r_bit_cnt == 3'd7) 
                        r_state <= S_CMD;   //RESP 중에는 mosi 무시. 명령으로 해석하지 않고 8비트 dummy 처리, 명령 수신 모드로 전환
                end
            endcase
        end
    end

    //SCLK 하강 에지에서 전송할 응답 로드
    always @(negedge sclk, posedge w_spi_reset) begin
        if(w_spi_reset) begin
            r_tx_shift <= 8'h00;
        end else begin
            if(r_tx_load)
                r_tx_shift <= r_response;
            else r_tx_shift <= {r_tx_shift[6:0], 1'b0}; //왼쪽으로 시프트, miso에는 최상위 비트 연결
        end
    end

    assign miso = cs_n ? 1'bz : r_tx_shift[7];  //최상위 비트 연결

endmodule
