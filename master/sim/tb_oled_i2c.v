`timescale 1ns / 1ps
module tb_oled_i2c;
    reg clk = 0, reset = 1, start = 0, dc = 0;
    reg [7:0] tx_data = 0;
    tri1 scl, sda;
    wire busy, done, error, address_ack;
    reg ack_low = 0, hold_scl = 0, hold_sda = 0, active = 0;
    reg monitor_enable = 1;
    integer bits = 0, bytes = 0, nack_byte = -1, starts = 0, stops = 0;
    reg [7:0] shift = 0, expected_control, expected_payload;
    reg [7:0] expected_address = 8'h7a;
    time rise_time = 0, fall_time = 0, transaction_start;
    reg check_width = 0;
    assign sda = (ack_low || hold_sda) ? 1'b0 : 1'bz;
    assign scl = hold_scl ? 1'b0 : 1'bz;
    always #5 clk = ~clk;

    oled_i2c #(.ADDRESS(7'h3d), .TIMEOUT_CYCLES(40000)) dut (
        .clk(clk), .reset(reset), .start(start), .tx_data(tx_data), .dc(dc),
        .scl(scl), .sda(sda), .busy(busy), .done(done), .error(error), .address_ack(address_ack)
    );

    always @(posedge reset) begin active = 0; ack_low = 0; check_width = 0; end
    always @(negedge sda) if (scl === 1'b1 && !reset && monitor_enable) begin
        if (active) $fatal(1, "Unexpected START while SCL high");
        active = 1; bits = 0; bytes = 0; shift = 0;
        starts = starts + 1;
        check_width = 0;
    end
    always @(posedge scl) if (active && !reset && monitor_enable) begin
        if (check_width && $time - fall_time < 5000) $fatal(1, "I2C low period too short");
        rise_time = $time;
        check_width = 1;
        if (bits < 8) begin
            shift = {shift[6:0], sda};
            bits = bits + 1;
        end else begin
            case (bytes)
                0: if (shift !== expected_address) $fatal(1, "Address parameter or write bit mismatch");
                1: if (shift !== expected_control) $fatal(1, "Control byte mismatch");
                2: if (shift !== expected_payload) $fatal(1, "Payload changed during transfer");
                default: $fatal(1, "Unexpected extra byte");
            endcase
            bytes = bytes + 1;
            bits = 0;
        end
    end
    always @(negedge scl) if (!reset && monitor_enable) begin
        if (active && check_width && $time - rise_time < 5000)
            $fatal(1, "I2C high period too short");
        fall_time = $time;
        ack_low = active && bits == 8 && bytes != nack_byte;
    end
    always @(posedge sda) if (scl === 1'b1 && active && !reset && monitor_enable) begin
        active = 0;
        stops = stops + 1;
        if (bytes != (nack_byte < 0 ? 3 : nack_byte + 1) || bits != 1)
            $fatal(1, "Wrong packet length or missing ACK cycle");
    end

    task launch;
        input mode;
        input [7:0] value;
        begin
            @(negedge clk);
            expected_control = mode ? 8'h40 : 8'h00;
            expected_payload = value;
            dc = mode; tx_data = value; start = 1;
            @(negedge clk); start = 0;
            // 전송 중 입력이 바뀌어도 처음 요청한 바이트를 유지함.
            dc = !mode; tx_data = ~value;
        end
    endtask
    task check_done;
        input expected_error;
        begin
            wait(done); #1;
            if (error !== expected_error || busy !== 0 || scl !== 1 || sda !== 1)
                $fatal(1, "I2C completion/error/bus release mismatch");
            if (active || starts != stops) $fatal(1, "STOP missing");
            if (address_ack !== (nack_byte != 0)) $fatal(1, "Address ACK status mismatch");
            repeat (3) @(negedge clk);
            if (done !== 0 || error !== 0) $fatal(1, "Completion must be a pulse");
        end
    endtask

    initial begin
        repeat (5) @(negedge clk); reset = 0;
        launch(0, 8'hae); check_done(0);
        launch(1, 8'ha5); check_done(0);
        for (nack_byte = 0; nack_byte < 3; nack_byte = nack_byte + 1) begin
            launch(1, 8'h96); check_done(1);
            // 제어·내용 미응답에서는 주소가 바뀌지 않아야 함.
            if (nack_byte == 0) expected_address = expected_address ^ 8'h02;
        end
        nack_byte = -1;
        // 클럭을 늘려도 비트나 ACK를 건너뛰지 않는지 검사함.
        transaction_start = $time;
        fork
            begin launch(1, 8'h5a); check_done(0); end
            begin
                @(negedge scl); hold_scl = 1;
                #30000; hold_scl = 0;
            end
        join
        if ($time - transaction_start < 320000) $fatal(1, "Clock stretching was ignored");

        // 낮게 고정된 선의 시간 제한과 복구를 검사함.
        monitor_enable = 0;
        hold_scl = 1;
        launch(0, 8'hae);
        wait(done); #1;
        if (!error || busy || sda !== 1) $fatal(1, "SCL timeout failed");
        hold_scl = 0;
        repeat (5) @(negedge clk);
        hold_sda = 1;
        launch(0, 8'hae);
        wait(done); #1;
        if (!error || busy || scl !== 1) $fatal(1, "SDA timeout failed");
        hold_sda = 0;
        repeat (5) @(negedge clk);
        monitor_enable = 1;
        launch(0, 8'haf); check_done(0);

        launch(1, 8'hff);
        @(negedge scl);
        @(negedge clk); reset = 1;
        repeat (3) @(negedge clk);
        if (busy || done || error || scl !== 1 || sda !== 1)
            $fatal(1, "Reset did not release I2C");
        reset = 0;
        expected_address = 8'h7a;
        starts = 0; stops = 0;
        launch(1, 8'h00); check_done(0);
        $display("PASS: 100 kHz, address fallback on address NACK only, control/data, stretching, stuck lines, reset");
        $finish;
    end
    initial begin #6000000; $fatal(1, "I2C watchdog expired"); end
endmodule
