`timescale 1ns / 1ps
module tb_spi_slave_test();
    
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

    // 1바이트 송수신
    // SCLK 1MHz: LOW 500ns + HIGH 500ns
    task transfer_byte;
        input  [7:0] tx_data;
        output [7:0] received;
        integer bit_idx;
        begin
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                mosi = tx_data[bit_idx];

                #500;
                sclk = 1'b1;

                // 상승 에지 직후 MISO 확인
                #1;
                received[bit_idx] = miso;

                #499;
                sclk = 1'b0;

                // DUT의 하강 에지 처리가 끝난 뒤 다음 동작 진행
                #0.001;
            end
        end
    endtask

    // 수신값 비교
    task check_byte;
        input [7:0] actual;
        input [7:0] expected;
        begin
            if (actual === expected) begin
                $display("[%0t] PASS: received=%h", $time, actual);
            end else begin
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

        // --------------------------------------------------
        // 1. STATUS → READY
        // --------------------------------------------------
        $display("TEST 1: STATUS");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h01, rx_data); // STATUS
        check_byte(rx_data, 8'h00);

        transfer_byte(8'h00, rx_data); // DUMMY → READY
        check_byte(rx_data, 8'h01);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 2. SEND → A5
        // --------------------------------------------------
        $display("TEST 2: SEND");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h02, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 3. CS LOW 유지: STATUS → READY → SEND → A5
        // --------------------------------------------------
        $display("TEST 3: STATUS + SEND");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h01, rx_data);
        check_byte(rx_data, 8'h00);

        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'h01);

        transfer_byte(8'h02, rx_data);
        check_byte(rx_data, 8'h00);

        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 4. CS LOW 유지: SEND 반복
        // --------------------------------------------------
        $display("TEST 4: REPEATED SEND");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h02, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        transfer_byte(8'h02, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 5. RESP 중 MOSI의 02를 SEND로 해석하지 않는지
        // --------------------------------------------------
        $display("TEST 5: IGNORE DUMMY");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h01, rx_data); // STATUS
        transfer_byte(8'h02, rx_data); // DUMMY지만 값은 SEND
        check_byte(rx_data, 8'h01);    // READY 응답이어야 함

        transfer_byte(8'h02, rx_data); // 실제 SEND
        check_byte(rx_data, 8'h00);    // 이전 DUMMY로 A5가 예약되면 안 됨

        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 6. 알 수 없는 명령 → 00
        // --------------------------------------------------
        $display("TEST 6: UNKNOWN COMMAND");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'hFF, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'h00);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 7. 명령 3비트 수신 후 CS 해제
        // --------------------------------------------------
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
        cs_n = 1'b1; // 부분 명령 폐기
        #1000;

        // 새 트랜잭션이 정상적으로 시작되는지 확인
        cs_n = 1'b0;
        #500;

        transfer_byte(8'h02, rx_data);
        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'hA5);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 8. 응답 3비트 송신 후 CS 해제
        // --------------------------------------------------
        $display("TEST 8: ABORT RESPONSE");

        cs_n = 1'b0;
        #500;

        transfer_byte(8'h02, rx_data); // SEND

        mosi = 1'b0;

        for (i = 0; i < 3; i = i + 1) begin
            #500;
            sclk = 1'b1;
            #500;
            sclk = 1'b0;
        end

        #100;
        cs_n = 1'b1; // 남은 응답 폐기
        #1000;

        // CMD부터 다시 시작하는지 확인
        cs_n = 1'b0;
        #500;

        transfer_byte(8'h01, rx_data);
        check_byte(rx_data, 8'h00);

        transfer_byte(8'h00, rx_data);
        check_byte(rx_data, 8'h01);

        cs_n = 1'b1;
        #1000;

        // --------------------------------------------------
        // 최종 결과
        // --------------------------------------------------
        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILED: %0d errors", error_count);

        $finish;
    end
endmodule
