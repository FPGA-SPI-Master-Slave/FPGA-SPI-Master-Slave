`timescale 1ns / 1ps
module tb_oled_controller;
    reg clk = 0, reset = 1, data_valid = 0, comm_error = 0;
    reg [15:0] distance = 0;
    wire byte_start, dc, link_error, initialized;
    wire [7:0] byte_tx;
    reg byte_done = 0;
    integer init_bytes = 0, frame_bytes = 0, frames = 0, expected_mode = 2;
    integer expected_value = 0, digit_number, column_number, divisor, n;
    reg [39:0] expected_glyph;
    reg [7:0] expected_byte;
    reg [15:0] samples [0:12];
    reg [15:0] random_value = 16'hace1;
    always #5 clk = ~clk;
    oled_controller #(.RESET_CYCLES(4), .REFRESH_CYCLES(1000)) dut (
        .clk(clk), .reset(reset), .distance(distance), .data_valid(data_valid),
        .comm_error(comm_error), .byte_start(byte_start), .byte_tx(byte_tx),
        .byte_done(byte_done), .byte_error(1'b0), .dc(dc), .link_error(link_error), .initialized(initialized)
    );

    function [39:0] glyph;
        input integer digit;
        begin
            case (digit)
                0: glyph=40'h3e5149453e; 1: glyph=40'h00427f4000;
                2: glyph=40'h4261514946; 3: glyph=40'h2141494936;
                4: glyph=40'h1814127f10; 5: glyph=40'h2745454539;
                6: glyph=40'h3c4a494930; 7: glyph=40'h0171090503;
                8: glyph=40'h3649494936; 9: glyph=40'h064949291e;
                default: glyph=0;
            endcase
        end
    endfunction

    // 변환 결과를 독립적인 십진 계산과 전송 바이트로 비교함.
    always @(posedge clk) begin
        byte_done <= byte_start;
        if (!reset && byte_start) begin
            if (init_bytes < 1074) init_bytes = init_bytes + 1;
            else begin
                expected_byte = 0;
                if (frame_bytes == 0) expected_byte = 8'hb0;
                else if (frame_bytes == 2) expected_byte = 8'h10;
                else if (frame_bytes >= 3) begin
                    digit_number = (frame_bytes - 3) / 6;
                    column_number = (frame_bytes - 3) % 6;
                    expected_glyph = 0;
                    if (expected_mode == 2) begin
                        case (digit_number)
                            0: expected_glyph=40'h7f09192946;
                            1: expected_glyph=40'h7f49494941;
                            2: expected_glyph=40'h7e1111117e;
                            3: expected_glyph=40'h7f4141221c;
                            4: expected_glyph=40'h0304780403;
                        endcase
                    end else if (expected_mode == 1) begin
                        case (digit_number)
                            0: expected_glyph=40'h7f49494941;
                            1,2,4: expected_glyph=40'h7f09192946;
                            3: expected_glyph=40'h3e4141413e;
                        endcase
                    end else begin
                        case (digit_number)
                            0: divisor=10000; 1: divisor=1000; 2: divisor=100;
                            3: divisor=10; default: divisor=1;
                        endcase
                        expected_glyph = glyph((expected_value / divisor) % 10);
                    end
                    if (column_number < 5) expected_byte = expected_glyph >> (8 * (4 - column_number));
                end
                if (dc !== (frame_bytes >= 3) || byte_tx !== expected_byte)
                    $fatal(1, "OLED byte mismatch value=%0d byte=%0d got=%h expected=%h", expected_value, frame_bytes, byte_tx, expected_byte);
                frame_bytes = frame_bytes + 1;
                if (frame_bytes == 33) begin
                    frames = frames + 1;
                    frame_bytes = 0;
                end
            end
        end
    end

    task send_value;
        input [15:0] value;
        begin
            @(negedge clk); distance = value; data_valid = 1;
            @(negedge clk); data_valid = 0;
        end
    endtask
    task check_value;
        input [15:0] value;
        integer previous_frames;
        begin
            previous_frames = frames;
            expected_mode = 0;
            expected_value = value;
            send_value(value);
            wait(frames > previous_frames);
            repeat (5) @(negedge clk);
        end
    endtask

    initial begin
        samples[0]=0; samples[1]=1; samples[2]=9; samples[3]=10;
        samples[4]=99; samples[5]=100; samples[6]=999; samples[7]=1000;
        samples[8]=9999; samples[9]=10000; samples[10]=32768;
        samples[11]=65534; samples[12]=65535;
        repeat (5) @(negedge clk); reset = 0;
        wait(frames == 1);
        if (!initialized) $fatal(1, "READY displayed before initialization completed");
        repeat (5) @(negedge clk);
        for (n=0; n<13; n=n+1) check_value(samples[n]);
        for (n=0; n<32; n=n+1) begin
            random_value = {random_value[14:0], random_value[15] ^ random_value[13] ^ random_value[12] ^ random_value[10]};
            check_value(random_value);
        end
        // 변환 도중 수신 값이 바뀌어도 한 화면의 값은 유지함.
        expected_value = 12345;
        send_value(12345);
        wait(dut.state == 5 && dut.convert_bit == 7);
        send_value(54321);
        wait(frames == 47);
        expected_value = 54321;
        wait(frames == 48);
        repeat (5) @(negedge clk);
        expected_mode = 1;
        comm_error = 1;
        wait(frames == 49);
        repeat (5) @(negedge clk);
        comm_error = 0;
        check_value(0);
        if (link_error) $fatal(1, "Unexpected OLED link error");
        $display("PASS: 45 decimal boundary/random values, conversion snapshot, READY, ERROR and numeric recovery");
        $finish;
    end
    initial begin #2000000; $fatal(1, "OLED conversion watchdog expired"); end
endmodule
