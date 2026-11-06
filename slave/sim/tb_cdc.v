`timescale 1ns / 1ps

module tb_sensor_cdc_bridge;

    reg clk = 1'b0;
    reg sclk = 1'b0;
    reg reset = 1'b1;

    reg [15:0] hcsr04_dist = 16'd0;
    reg [2:0]  hcsr04_status = 3'd0;
    reg hcsr04_valid = 1'b0;
    reg hcsr04_updated = 1'b0;

    wire [18:0] hcsr04_snapshot;
    wire hcsr04_snapshot_valid;

    integer errors = 0;

    // 시스템 클럭: 100MHz
    always #5 clk = ~clk;

    sensor_cdc_bridge dut (
        .clk(clk),
        .sclk(sclk),
        .reset(reset),
        .hcsr04_dist(hcsr04_dist),
        .hcsr04_status(hcsr04_status),
        .hcsr04_valid(hcsr04_valid),
        .hcsr04_updated(hcsr04_updated),
        .hcsr04_snapshot(hcsr04_snapshot),
        .hcsr04_snapshot_valid(hcsr04_snapshot_valid)
    );

    // 센서 결과 1건 발생: updated를 100MHz 한 클럭 동안 유지
    task publish_result;
        input [15:0] distance;
        input [2:0] status;
        begin
            @(negedge clk);
            hcsr04_dist = distance;
            hcsr04_status = status;
            hcsr04_valid = 1'b1;
            hcsr04_updated = 1'b1;

            @(negedge clk);
            hcsr04_updated = 1'b0;
        end
    endtask

    // 필요할 때만 SCLK를 발생시킴: 1MHz, Mode 0
    task run_sclk;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                #500 sclk = 1'b1;
                #500 sclk = 1'b0;
            end
        end
    endtask

    task check_snapshot;
        input [15:0] expected_distance;
        input [2:0] expected_status;
        reg [18:0] expected;
        begin
            expected = {expected_distance, expected_status};

            if (hcsr04_snapshot_valid !== 1'b1 ||
                hcsr04_snapshot !== expected) begin
                $display("FAIL: expected dist=%h status=%h, got valid=%b packet=%h",
                         expected_distance, expected_status,
                         hcsr04_snapshot_valid, hcsr04_snapshot);
                errors = errors + 1;
            end else begin
                $display("PASS: dist=%h status=%h",
                         expected_distance, expected_status);
            end
        end
    endtask

    initial begin
        #22 reset = 1'b0;

        // 1. 첫 결과가 생겨도 SCLK가 멈춰 있으면 아직 전달되지 않아야 함
        $display("TEST 1: SCLK stopped before first transfer");
        publish_result(16'h0123, 3'h1);
        #20;

        if (hcsr04_snapshot_valid !== 1'b0) begin
            $display("FAIL: snapshot became valid without SCLK");
            errors = errors + 1;
        end else
            $display("PASS: snapshot waits for SCLK");

        // 요청 2단 동기화 후 다음 SCLK 상승 에지에서 복사
        run_sclk(3);
        check_snapshot(16'h0123, 3'h1);

        // 2. SCLK 정지 중 B와 C가 들어오면,
        //    전달 중이던 B를 먼저 보내고 이후 최신값 C를 보내야 함
        $display("TEST 2: updates while SCLK is stopped");
        publish_result(16'h0045, 3'h2); // B: 전달 시작
        publish_result(16'h0067, 3'h3); // C: pending에 기록

        // SCLK가 없으므로 SPI 측 값은 여전히 A
        check_snapshot(16'h0123, 3'h1);

        run_sclk(3);
        check_snapshot(16'h0045, 3'h2); // 고정된 B 확인

        run_sclk(3);
        check_snapshot(16'h0067, 3'h3); // 이후 최신값 C 확인

        // 3. 새 측정 없이 SCLK만 더 발생시켜도 값이 변하면 안 됨
        $display("TEST 3: no duplicate transfer");
        run_sclk(5);
        check_snapshot(16'h0067, 3'h3);

        // 4. SCLK 정지 상태에서도 reset은 출력을 초기화해야 함
        $display("TEST 4: reset");
        reset = 1'b1;
        #1;

        if (hcsr04_snapshot_valid !== 1'b0 ||
            hcsr04_snapshot !== 19'd0) begin
            $display("FAIL: reset did not clear snapshot");
            errors = errors + 1;
        end else
            $display("PASS: reset cleared snapshot");

        if (errors == 0)
            $display("ALL CDC TESTS PASSED");
        else
            $display("CDC TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule