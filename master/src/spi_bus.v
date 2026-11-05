`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/05 13:04:32
// Design Name: 
// Module Name: spi_bus
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spi_bus(
    input clk, input reset,
    input slave_request, input oled_request,
    output wire slave_grant, output wire oled_grant,
    input slave_start, input [7:0] slave_tx, input slave_cs_n,
    input oled_start, input [7:0] oled_tx, input oled_cs_n,
    output wire byte_start, output wire [7:0] byte_tx,
    input byte_busy, input byte_done,
    output wire slave_done, output wire oled_done,
    output wire spi_cs_n, output wire oled_cs_out_n
);
    localparam NONE = 2'd0, SLAVE = 2'd1, OLED = 2'd2;
    reg [1:0] owner;

    assign slave_grant = owner == SLAVE;
    assign oled_grant = owner == OLED;
    assign byte_start = slave_grant ? slave_start : oled_grant ? oled_start : 1'b0;
    assign byte_tx = slave_grant ? slave_tx : oled_grant ? oled_tx : 8'h00;
    assign slave_done = slave_grant && byte_done;
    assign oled_done = oled_grant && byte_done;
    assign spi_cs_n = !slave_grant || slave_cs_n;
    assign oled_cs_out_n = !oled_grant || oled_cs_n;

    always @(posedge clk) begin
        if (reset) owner <= NONE;
        else case (owner)
            NONE: if (oled_request) owner <= OLED;
                  else if (slave_request) owner <= SLAVE;
            SLAVE: if (!slave_request && !byte_busy) owner <= NONE;
            OLED: if (!oled_request && !byte_busy) owner <= NONE;
            default: owner <= NONE;
        endcase
    end
endmodule
