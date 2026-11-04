`timescale 1ns / 1ps
module tb_master;
    // 프로토콜 기대값을 독립적으로 지정함.
    localparam [7:0] STATUS = 8'h10, SEND = 8'h20,
                     BUSY = 8'h00, READY = 8'h01, DUMMY = 8'h00;
    reg clk = 0, start = 0, reset = 1, miso = 0;
    wire sclk, mosi, cs_n;
    wire [15:0] led;
    integer scenario = 0, byte_index = 0, bit_index = 0, polls = 0;
    integer transactions = 0;
    reg [7:0] received = 0, response = 0;
    reg [7:0] complete_byte, status_value;
    time last_edge, last_fall;
    always #5 clk = ~clk;
    master_top #(.STABLE_CYCLES(4), .MAX_POLLS(3)) dut (
        .clk(clk), .start(start), .reset(reset), .spi_miso(miso),
        .spi_sclk(sclk), .spi_mosi(mosi), .spi_cs_n(cs_n), .led(led));

    // 상승 에지에서 MOSI를 받고 하강 에지에서 응답을 갱신함.
    always @(negedge cs_n) begin
        byte_index = 0; bit_index = 0; polls = 0; received = 0; response = 0; miso = 0;
        transactions = transactions + 1;
    end
    always @(posedge sclk) begin
        if (cs_n) $fatal(1, "SCLK while deselected");
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
                    response = 8'ha4 + transactions; byte_index = 3;
                end
                3: begin
                    if (complete_byte !== DUMMY) $fatal(1, "Expected dummy data byte");
                    byte_index = 4; response = 0;
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
        repeat (5) @(negedge clk); reset = 0;
        repeat (10) @(negedge clk);
        press_button;
        wait(cs_n == 0); wait(cs_n == 1); #1;
        if (byte_index != 4 || polls != 3 || led[7:0] !== 8'ha5 || led[9:8] !== 0)
            $fatal(1, "First transaction failed");
        wait(cs_n == 0); wait(cs_n == 1); #1;
        if (transactions != 2 || led[7:0] !== 8'ha6 || led[9:8] !== 0)
            $fatal(1, "Continuous transaction failed");
        reset = 1;
        repeat (5) @(negedge clk);
        reset = 0;
        repeat (10) @(negedge clk);
        if (cs_n !== 1) $fatal(1, "Reset did not stop continuous transfers");
        scenario = 1; press_button;
        wait(cs_n == 0); wait(cs_n == 1); #20;
        if (polls != 3 || led[9:8] !== 2'b01 || led[7:0] !== 8'h00)
            $fatal(1, "Timeout failed polls=%0d leds=%h", polls, led);
        scenario = 2; press_button;
        wait(cs_n == 0); wait(cs_n == 1); #20;
        if (polls != 1 || led[9:8] !== 2'b10) $fatal(1, "Protocol error failed leds=%h", led);
        $display("PASS: repeated transfers, reset, timeout, invalid response; 1 MHz high and low phases");
        $finish;
    end
    initial begin #500000; $fatal(1, "Simulation watchdog expired"); end
endmodule
