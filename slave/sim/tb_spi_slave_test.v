`timescale 1ns / 1ps

module tb_spi_slave_test;
    localparam [7:0] CMD_STATUS = 8'h10;
    localparam [7:0] CMD_SEND   = 8'h20;
    localparam [7:0] RESP_READY = 8'h01;
    localparam [7:0] TEST_DATA  = 8'hA5;

    reg sclk;
    reg reset;
    reg cs_n;
    reg mosi;
    wire miso;

    reg [7:0] rx_data;
    integer error_count;
    integer i;

    spi_slave dut (
        .sclk  (sclk),
        .reset (reset),
        .cs_n  (cs_n),
        .mosi  (mosi),
        .miso  (miso)
    );

    // 1바이트를 MSB부터 전송했음.
    task transfer_byte;
        input  [7:0] tx_data;
        output [7:0] received;
        integer bit_idx;
        begin
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                mosi = tx_data[bit_idx];
                #500;
                sclk = 1'b1;
                #1;
                received[bit_idx] = miso;
                #499;
                sclk = 1'b0;
                #0.001;
            end
        end
    endtask

    // 수신값을 비교했음.
    task check_byte;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual === expected)
                $display("[%0t] PASS: received=%h", $time, actual);
            else begin
                $display("[%0t] FAIL: received=%h, expected=%h",
                         $time, actual, expected);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        sclk        = 1'b0;
        reset       = 1'b1;
        cs_n        = 1'b1;
        mosi        = 1'b0;
        error_count = 0;

        #1000;
        reset = 1'b0;
        #1000;

        // STATUS 명령의 READY 응답 확인
        $display("TEST 1: STATUS");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_STATUS, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, RESP_READY);
        cs_n = 1'b1;
        #1000;

        // SEND 명령의 테스트 데이터 응답 확인
        $display("TEST 2: SEND");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_SEND, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        cs_n = 1'b1;
        #1000;

        // CS 유지 중 명령 두 개 확인
        $display("TEST 3: STATUS + SEND");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_STATUS, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, RESP_READY);
        transfer_byte(CMD_SEND, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        cs_n = 1'b1;
        #1000;

        // SEND 반복 확인
        $display("TEST 4: REPEATED SEND");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_SEND, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        transfer_byte(CMD_SEND, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        cs_n = 1'b1;
        #1000;

        // 응답 구간의 MOSI는 명령으로 처리하지 않음
        $display("TEST 5: IGNORE DUMMY");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_STATUS, rx_data);
        transfer_byte(CMD_SEND, rx_data);
        check_byte(rx_data, RESP_READY);
        transfer_byte(CMD_SEND, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        cs_n = 1'b1;
        #1000;

        // 정의되지 않은 명령 확인
        $display("TEST 6: UNKNOWN COMMAND");
        cs_n = 1'b0;
        #500;
        transfer_byte(8'hFF, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'h00);
        cs_n = 1'b1;
        #1000;

        // 명령 수신 중 CS 해제 확인
        $display("TEST 7: ABORT COMMAND");
        cs_n = 1'b0;
        #500;
        for (i = 0; i < 3; i = i + 1) begin
            mosi = 1'b1;
            #500;
            sclk = 1'b1;
            #500;
            sclk = 1'b0;
        end
        #100;
        cs_n = 1'b1;
        #1000;
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_SEND, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, TEST_DATA);
        cs_n = 1'b1;
        #1000;

        // 응답 송신 중 CS 해제 확인
        $display("TEST 8: ABORT RESPONSE");
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_SEND, rx_data);
        mosi = 1'b0;
        for (i = 0; i < 3; i = i + 1) begin
            #500;
            sclk = 1'b1;
            #500;
            sclk = 1'b0;
        end
        #100;
        cs_n = 1'b1;
        #1000;
        cs_n = 1'b0;
        #500;
        transfer_byte(CMD_STATUS, rx_data);
        check_byte(rx_data, 8'h00);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, RESP_READY);
        cs_n = 1'b1;
        #1000;

        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d errors", error_count);

        $finish;
    end
endmodule
