`timescale 1ns / 1ps
module tb_master #(parameter [6:0] DEVICE_ADDRESS = 7'h3c);
    // 프로토콜 기대값을 독립적으로 지정함.
    localparam [7:0] STATUS = 8'h10, 
                     SEND = 8'h20,
                     BUSY = 8'h00, 
                     READY = 8'h01, 
                     DUMMY = 8'h00;
    reg clk = 0, start = 0, reset = 1, miso = 0;
    wire sclk, mosi, cs_n;
    tri1 oled_scl, oled_sda;
    wire [15:0] led;
    integer scenario = 0, byte_index = 0, bit_index = 0, polls = 0;
    integer transactions = 0;
    reg [7:0] received = 0, response = 0;
    reg [7:0] complete_byte, status_value;
    time last_edge, last_fall;
    integer oled_bits = 0, oled_packet_bytes = 0, oled_init_bytes = 0, oled_bytes = 0;
    reg [7:0] oled_shift = 0;
    reg oled_display_checked = 0;
    integer oled_expected_mode = 0, oled_frame_mode = 0;
    integer oled_error_frames = 0, oled_recovery_frames = 0, check_index;
    integer oled_ready_frames = 0;
    reg [7:0] oled_frame [0:32];
    reg oled_frame_dc [0:32];
    reg oled_active = 0, oled_ack_low = 0, oled_present = 1;
    reg oled_address_match = 0;
    reg [7:0] oled_control, oled_payload;
    reg simultaneous_transfers = 0;
    assign oled_sda = oled_ack_low ? 1'b0 : 1'bz;

    function [7:0] expected_oled_byte;
        input integer n;
        begin
            case (n)
                0: expected_oled_byte=8'hb0; 1: expected_oled_byte=8'h00;
                2: expected_oled_byte=8'h10; 3: expected_oled_byte=8'h3e;
                4: expected_oled_byte=8'h51; 5: expected_oled_byte=8'h49;
                6: expected_oled_byte=8'h45; 7: expected_oled_byte=8'h3e;
                9: expected_oled_byte=8'h18; 10: expected_oled_byte=8'h14;
                11: expected_oled_byte=8'h12; 12: expected_oled_byte=8'h7f;
                13: expected_oled_byte=8'h10;
                15,21: expected_oled_byte=8'h01; 16,22: expected_oled_byte=8'h71;
                17,23: expected_oled_byte=8'h09; 18,24: expected_oled_byte=8'h05;
                19,25: expected_oled_byte=8'h03; 27: expected_oled_byte=8'h21;
                28: expected_oled_byte=8'h41; 29,30: expected_oled_byte=8'h49;
                31: expected_oled_byte=8'h36;
                default: expected_oled_byte=8'h00;
            endcase
        end
    endfunction

    function [7:0] expected_ready_byte;
        input integer n;
        begin
            case (n)
                0: expected_ready_byte=8'hb0;
                1: expected_ready_byte=8'h00;
                2: expected_ready_byte=8'h10;
                3,9,21: expected_ready_byte=8'h7f;
                4: expected_ready_byte=8'h09;
                5: expected_ready_byte=8'h19;
                6: expected_ready_byte=8'h29;
                7: expected_ready_byte=8'h46;
                10,11,12: expected_ready_byte=8'h49;
                13,22,23: expected_ready_byte=8'h41;
                15,19: expected_ready_byte=8'h7e;
                16,17,18: expected_ready_byte=8'h11;
                24: expected_ready_byte=8'h22;
                25: expected_ready_byte=8'h1c;
                27,31: expected_ready_byte=8'h03;
                28,30: expected_ready_byte=8'h04;
                29: expected_ready_byte=8'h78;
                default: expected_ready_byte=8'h00;
            endcase
        end
    endfunction

    function [7:0] expected_init_byte;
        input integer n;
        integer p, c;
        begin
            case (n)
                0: expected_init_byte=8'hae; 1: expected_init_byte=8'hd5;
                2: expected_init_byte=8'h80; 3: expected_init_byte=8'ha8;
                4: expected_init_byte=8'h3f; 5: expected_init_byte=8'hd3;
                6: expected_init_byte=8'h00; 7: expected_init_byte=8'h40;
                8: expected_init_byte=8'h8d; 9: expected_init_byte=8'h14;
                10: expected_init_byte=8'h20; 11: expected_init_byte=8'h02;
                12: expected_init_byte=8'ha1; 13: expected_init_byte=8'hc8;
                14: expected_init_byte=8'hda; 15: expected_init_byte=8'h12;
                16: expected_init_byte=8'h81; 17: expected_init_byte=8'h7f;
                18: expected_init_byte=8'hd9; 19: expected_init_byte=8'hf1;
                20: expected_init_byte=8'hdb; 21: expected_init_byte=8'h40;
                22: expected_init_byte=8'ha4; 23: expected_init_byte=8'ha6;
                24: expected_init_byte=8'h2e;
                1073: expected_init_byte=8'haf;
                default: begin
                    p = (n - 25) / 131;
                    c = (n - 25) % 131;
                    case (c)
                        0: expected_init_byte=8'hb0 + p;
                        2: expected_init_byte=8'h10;
                        default: expected_init_byte=0;
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] expected_error_byte;
        input integer n;
        begin
            case (n)
                0: expected_error_byte=8'hb0;
                1: expected_error_byte=8'h00;
                2: expected_error_byte=8'h10;
                3,9,15,27: expected_error_byte=8'h7f;
                4,5,6: expected_error_byte=8'h49;
                7: expected_error_byte=8'h41;
                10,16,28: expected_error_byte=8'h09;
                11,17,29: expected_error_byte=8'h19;
                12,18,30: expected_error_byte=8'h29;
                13,19,31: expected_error_byte=8'h46;
                21,25: expected_error_byte=8'h3e;
                22,23,24: expected_error_byte=8'h41;
                default: expected_error_byte=8'h00;
            endcase
        end
    endfunction

    always #5 clk = ~clk;

    master_top #(.STABLE_CYCLES(4), .MAX_POLLS(3), .OLED_RESET_CYCLES(4),
                 .OLED_I2C_QUARTER_PERIOD(5)) dut (
        .clk(clk), .start(start), .reset(reset), .spi_miso(miso),
        .spi_sclk(sclk), .spi_mosi(mosi), .spi_cs_n(cs_n), .led(led),
        .sclk(oled_scl), .sda(oled_sda));

    always @(posedge reset) begin
        oled_active = 0;
        oled_ack_low = 0;
        oled_init_bytes = 0;
        oled_bytes = 0;
    end
    // I2C 시작, 각 바이트와 ACK, 종료를 실제 배선에서 복호화함.
    always @(negedge oled_sda) if (oled_scl === 1'b1 && !reset) begin
        if (oled_active) $fatal(1, "Unexpected I2C START");
        oled_active = 1;
        oled_bits = 0;
        oled_packet_bytes = 0;
        oled_shift = 0;
        oled_address_match = 0;
    end
    always @(posedge oled_scl) if (oled_active && !reset) begin
        if (!cs_n) simultaneous_transfers = 1;
        if (oled_bits < 8) begin
            oled_shift = {oled_shift[6:0], oled_sda};
            oled_bits = oled_bits + 1;
            if (oled_packet_bytes == 0 && oled_bits == 8)
                oled_address_match = oled_shift == {DEVICE_ADDRESS, 1'b0};
        end else begin
            if (oled_present && oled_address_match && oled_sda !== 0) $fatal(1, "I2C ACK missing");
            case (oled_packet_bytes)
                0: if (oled_shift !== 8'h78 && oled_shift !== 8'h7a)
                    $fatal(1, "Wrong I2C address: %h", oled_shift);
                1: begin
                    if (oled_shift !== 8'h00 && oled_shift !== 8'h40)
                        $fatal(1, "Wrong SSD1306 control byte: %h", oled_shift);
                    oled_control = oled_shift;
                end
                2: oled_payload = oled_shift;
                default: $fatal(1, "Too many I2C bytes");
            endcase
            oled_packet_bytes = oled_packet_bytes + 1;
            oled_bits = 0;
        end
    end
    always @(negedge oled_scl) begin
        oled_ack_low = !reset && oled_active && oled_present && oled_address_match && oled_bits == 8;
    end
    always @(posedge oled_sda) if (oled_scl === 1'b1 && oled_active && !reset) begin
        oled_active = 0;
        if (oled_present && oled_address_match) begin
            if (oled_packet_bytes != 3 || oled_bits != 1) $fatal(1, "Incomplete I2C packet");
            if (oled_init_bytes < 1074) begin
                if (oled_payload !== expected_init_byte(oled_init_bytes) ||
                    oled_control !== ((oled_init_bytes >= 25 && oled_init_bytes < 1073 &&
                                      (oled_init_bytes - 25) % 131 >= 3) ? 8'h40 : 8'h00))
                    $fatal(1, "OLED initialization/clear mismatch at %0d", oled_init_bytes);
                oled_init_bytes = oled_init_bytes + 1;
            end else begin
                if (oled_bytes == 0) oled_frame_mode = oled_expected_mode;
                oled_frame[oled_bytes] = oled_payload;
                oled_frame_dc[oled_bytes] = oled_control == 8'h40;
                oled_bytes = oled_bytes + 1;
                if (oled_bytes == 33) begin
                    check_oled_frame;
                    oled_bytes = 0;
                end
            end
        end else if (oled_packet_bytes != 1) $fatal(1, "NACK did not stop transaction");
    end
    // 화면 갱신 전체를 수신한 뒤 오류 문구와 정상 복구를 검사함.
    task check_oled_frame;
      begin
        for (check_index = 0; check_index < 33; check_index = check_index + 1) begin
            if (oled_frame_dc[check_index] !== (check_index >= 3))
                $fatal(1, "OLED D/C mismatch at byte %0d", check_index);
            if (oled_frame_mode == 1 && oled_frame[check_index] !== expected_error_byte(check_index))
                $fatal(1, "OLED ERROR mismatch at byte %0d: %h", check_index, oled_frame[check_index]);
            if (oled_frame_mode == 3 && oled_frame[check_index] !== expected_ready_byte(check_index))
                $fatal(1, "OLED READY mismatch at byte %0d: %h", check_index, oled_frame[check_index]);
            if ((oled_frame_mode == 0 || oled_frame_mode == 2) &&
                oled_frame[check_index] !== expected_oled_byte(check_index))
                $fatal(1, "OLED recovery mismatch at byte %0d: %h", check_index, oled_frame[check_index]);
        end
        if (oled_frame_mode == 1) oled_error_frames = oled_error_frames + 1;
        if (oled_frame_mode == 2) oled_recovery_frames = oled_recovery_frames + 1;
        if (oled_frame_mode == 0) oled_display_checked = 1;
        if (oled_frame_mode == 3) oled_ready_frames = oled_ready_frames + 1;
      end
    endtask

    // 상승 에지에서 MOSI를 받고 하강 에지에서 응답을 갱신함.
    always @(negedge cs_n) begin
        byte_index = 0; bit_index = 0; polls = 0; received = 0; response = 0; miso = 0;
        transactions = transactions + 1;
    end
    always @(posedge sclk) if (!cs_n) begin
        if (bit_index != 0 && ($time - last_fall) != 500) $fatal(1, "SCLK low width != 500 ns");
        received = {received[6:0], mosi};
        last_edge = $time;
    end
    always @(negedge sclk) if (!cs_n) begin
        last_fall = $time;
        if (($time - last_edge) != 500) $fatal(1, "SCLK high width != 500 ns");
        if (bit_index == 7) begin
            complete_byte = received;
            bit_index = 0;
            case (byte_index)
                0: begin
                    if (complete_byte !== STATUS) $fatal(1, "Expected STATUS, got %h", complete_byte);
                    if (scenario == 2) response = 8'h7e;
                    else if (scenario == 1 || polls < 2) response = BUSY;
                    else response = READY;
                    status_value = response;
                    polls = polls + 1; byte_index = 1;
                end
                1: begin
                    if (complete_byte !== DUMMY) $fatal(1, "Expected dummy status byte");
                    if (status_value == READY) byte_index = 2;
                    else byte_index = 0;
                    response = 0;
                end
                2: begin
                    if (complete_byte !== SEND) $fatal(1, "Expected SEND");
                    response = 8'h12; byte_index = 3;
                end
                3: begin
                    if (complete_byte !== DUMMY) $fatal(1, "Expected dummy data byte");
                    byte_index = 4;
                    response = scenario == 3 ? 8'ha5 : 8'ha4 + transactions;
                end
                4: begin
                    if (complete_byte !== DUMMY) $fatal(1, "Expected dummy low byte");
                    byte_index = 5; response = 8'h5a;
                end
                5: begin
                    if (complete_byte !== DUMMY) $fatal(1, "Expected dummy status byte");
                    byte_index = 6; response = 0;
                end
                default: $fatal(1, "Unexpected byte");
            endcase
            miso = response[7];
        end else begin
            bit_index = bit_index + 1;
            response = {response[6:0], 1'b0};
            miso = response[7];
        end
    end
    task press_button;
        begin
            @(negedge clk); start = 1;
            repeat (12) @(negedge clk);
            start = 0;
            repeat (12) @(negedge clk);
        end
    endtask
    initial begin
        oled_expected_mode = 3;
        repeat (5) @(negedge clk); reset = 0;
        repeat (10) @(negedge clk);
        // 버튼이나 슬레이브 데이터 없이 READY가 출력되는지 검사함.
        wait(oled_ready_frames == 1);
        if (transactions != 0 || cs_n !== 1 || led[10:8] !== 0)
            $fatal(1, "READY required slave traffic or OLED reported an error");
        if (led[12:11] !== 2'b11) $fatal(1, "OLED address/init status LEDs missing");
        oled_expected_mode = 0;
        press_button;
        wait(cs_n == 0); wait(cs_n == 1); #1;
        if (byte_index != 6 || polls != 3 || led[7:0] !== 8'ha5 || led[9:8] !== 0 ||
            dut.distance_high !== 8'h12 || dut.distance_low !== 8'ha5 || dut.distance_status !== 8'h5a)
            $fatal(1, "First transaction failed");
        wait(cs_n == 0); wait(cs_n == 1); #1;
        if (transactions != 2 || led[7:0] !== 8'ha6 || led[9:8] !== 0 ||
            dut.distance_high !== 8'h12 || dut.distance_low !== 8'ha6 || dut.distance_status !== 8'h5a)
            $fatal(1, "Continuous transaction failed");
        scenario = 3;
        wait(oled_display_checked);
        reset = 1;
        repeat (5) @(negedge clk);
        reset = 0;
        repeat (10) @(negedge clk);
        if (cs_n !== 1) $fatal(1, "Reset did not stop continuous transfers");
        oled_expected_mode = 1;
        scenario = 1; press_button;
        wait(cs_n == 0); wait(cs_n == 1); #20;
        if (polls != 3 || led[9:8] !== 2'b01 || led[7:0] !== 8'h00)
            $fatal(1, "Timeout failed polls=%0d leds=%h", polls, led);
        wait(oled_error_frames == 1);
        // 재시작만으로 오류 문구를 지우지 않고 새 수신 후 복구함.
        oled_expected_mode = 2;
        scenario = 3; press_button;
        wait(cs_n == 0); #1;
        if (led[9:8] !== 0 || dut.oled_inst.latest_error !== 1)
            $fatal(1, "OLED error cleared before successful recovery");
        wait(oled_recovery_frames == 1);
        if (led[9:8] !== 0 || dut.oled_inst.latest_error !== 0)
            $fatal(1, "Recovery did not clear error");
        oled_expected_mode = 1;
        scenario = 2;
        wait(led[9] == 1); #20;
        if (polls != 1 || led[9:8] !== 2'b10) $fatal(1, "Protocol error failed leds=%h", led);
        wait(oled_error_frames == 2);
        // 오류 상태에서 리셋하면 화면과 오류 기록을 초기화함.
        reset = 1;
        repeat (5) @(negedge clk);
        if (dut.oled_inst.latest_error !== 0 || dut.oled_inst.display_error !== 0 ||
            oled_scl !== 1 || oled_sda !== 1 || cs_n !== 1)
            $fatal(1, "Reset did not clear OLED error state");
        reset = 0;
        oled_expected_mode = 1;
        scenario = 2; press_button;
        wait(cs_n == 0); wait(cs_n == 1); #20;
        if (polls != 1 || led[9:8] !== 2'b10) $fatal(1, "Protocol error failed leds=%h", led);
        wait(oled_error_frames == 3);
        if (!simultaneous_transfers) $fatal(1, "SPI and I2C never ran concurrently");
        // OLED 미응답 후 재연결해도 슬레이브 SPI가 동작함을 검사함.
        reset = 1;
        repeat (5) @(negedge clk);
        oled_present = 0;
        reset = 0;
        scenario = 3;
        press_button;
        wait(led[10] == 1);
        wait(dut.data_valid == 1);
        if (led[9:8] !== 0) $fatal(1, "OLED NACK stopped slave SPI");
        wait(!dut.oled_i2c_inst.busy);
        oled_present = 1;
        oled_expected_mode = 2;
        wait(led[10] == 0);
        wait(oled_recovery_frames == 2);
        reset = 1;
        repeat (5) @(negedge clk);
        oled_expected_mode = 3;
        reset = 0;
        wait(oled_ready_frames == 2);
        if (cs_n !== 1 || led[10:8] !== 0) $fatal(1, "READY did not return after reset");
        $display("PASS: OLED address %h, startup/reset READY, independent SPI/I2C, digits, ERROR, reconnect, status LEDs", DEVICE_ADDRESS);
        $finish;
    end
    initial begin #40000000; $fatal(1, "Simulation watchdog expired"); end
endmodule

// 주소가 0x3D인 OLED도 같은 통합 검사로 확인함.
module tb_master_3d;
    tb_master #(.DEVICE_ADDRESS(7'h3d)) test();
endmodule
