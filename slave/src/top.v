`timescale 1ns / 1ps

module top(
    input clk,
    input reset,
    input echo,
    input sclk,
    input cs_n,
    input mosi,
    output trig,
    output uart_tx,
    output miso
    );

    wire w_1us_tick;
    
    wire w_busy, w_start;
    wire [15:0] w_measured_dist;
    wire [2:0] w_measured_status;
    wire w_hcsr04_done;

    wire [15:0] w_buffered_hcsr04_dist;
    wire [2:0] w_buffered_status;
    wire w_buffer_valid;
    wire w_buffer_updated;

    
    wire [18:0] w_hcsr04_snapshot;  //CDC 후 {거리[15:0], 상태[2:0]}
    wire w_hcsr04_snapshot_valid;

    wire w_fifo_read;
    wire [18:0] w_fifo_data;
    wire w_fifo_empty;
    wire w_fifo_full;
    wire w_fifo_overflow;

    wire [7:0] w_uart_tx_data;
    wire w_uart_tx_start;
    wire w_uart_tx_busy;
    wire w_uart_tx_done;

    tick_generator #(
        .INPUT_FREQ(100_000_000),
        .TICK_Hz(1_000_000)
    ) u_1us_tick_generator(
        .clk(clk),
        .reset(reset),
        .tick(w_1us_tick)
    );

    measure_scheduler #(
        .MEASURE_PERIOD_US(100_000)
    ) u_measure_scheduler (
    .clk   (clk),
    .reset (reset),
    .tick  (w_1us_tick),
    .busy  (w_busy),
    .start (w_start)
    );

    hcsr04_controller u_hcsr04_controller(
        .clk(clk),
        .reset(reset),
        .tick(w_1us_tick),
        .start(w_start),
        .echo(echo),

        .trig(trig),
        .busy(w_busy),
        .distance_cm(w_measured_dist),
        .status(w_measured_status),
        .hcsr04_done(w_hcsr04_done)
    );

    sensor_data_buffer u_sensor_data_buffer(
        .clk(clk),
        .reset(reset),

        .hcsr04_done(w_hcsr04_done),
        .hcsr04_dist(w_measured_dist),
        .hcsr04_status(w_measured_status),

        .hcsr04_data(w_buffered_hcsr04_dist),
        .status(w_buffered_status),
        .valid(w_buffer_valid),
        .sh_buf_updated(w_buffer_updated)
    );

    sensor_cdc_bridge u_sensor_cdc_bridge (
        .clk                   (clk),
        .sclk                  (sclk),
        .reset                 (reset),

        .hcsr04_dist           (w_buffered_hcsr04_dist),
        .hcsr04_status         (w_buffered_status),
        .hcsr04_valid          (w_buffer_valid),

        .hcsr04_updated        (w_buffer_updated),
        .hcsr04_snapshot       (w_hcsr04_snapshot),
        .hcsr04_snapshot_valid (w_hcsr04_snapshot_valid)
    );

    spi_slave u_spi_slave (
        .sclk  (sclk),
        .reset (reset),
        .cs_n  (cs_n),
        .mosi  (mosi),
        .hcsr04_snapshot(w_hcsr04_snapshot),
        .hcsr04_snapshot_valid(w_hcsr04_snapshot_valid),

        .miso  (miso)
    );

    sensor_result_fifo u_sensor_result_fifo (
        .clk          (clk),
        .reset        (reset),

        .write_en     (w_buffer_updated),
        .write_data   ({w_buffered_status, w_buffered_hcsr04_dist}),

        .read_en      (w_fifo_read),
        .read_data    (w_fifo_data),
        .empty        (w_fifo_empty),
        .full         (w_fifo_full),
        .overflow     (w_fifo_overflow)
    );

    uart_reporter u_uart_reporter(
        .clk(clk),
        .reset(reset),

        .fifo_data(w_fifo_data),
        .fifo_empty(w_fifo_empty),
        .fifo_read(w_fifo_read),

        .tx_busy(w_uart_tx_busy),
        .tx_done(w_uart_tx_done),
        .tx_data(w_uart_tx_data),
        .tx_start(w_uart_tx_start)
    );

    uart_tx #(
    .CLK_FREQ  (100_000_000),
    .BAUD_RATE (115_200)
    ) u_uart_tx (
        .clk      (clk),
        .reset    (reset),

        .tx_data  (w_uart_tx_data),
        .tx_start (w_uart_tx_start),

        .tx       (uart_tx),
        .tx_busy  (w_uart_tx_busy),
        .tx_done  (w_uart_tx_done)
    );

endmodule
