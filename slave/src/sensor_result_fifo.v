`timescale 1ns / 1ps

module sensor_result_fifo #(
    parameter DEPTH = 4
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        write_en,
    input  wire [18:0] write_data,  // {status[2:0], distance_cm[15:0]}

    input  wire        read_en,
    output wire [18:0] read_data,

    output wire        empty,
    output wire        full,
    output reg         overflow
);

    localparam PTR_WIDTH   = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam COUNT_WIDTH = $clog2(DEPTH + 1);

    reg [18:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [COUNT_WIDTH-1:0] count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    // 현재 FIFO 맨 앞의 데이터를 보여줍니다.
    // empty일 때는 유효한 항목이 없으므로 0을 출력합니다.
    assign read_data = empty ? 19'd0 : memory[read_ptr];

    // 비어 있으면 읽지 않습니다.
    wire do_read = read_en && !empty;

    // 가득 차 있어도 같은 클럭에 읽는다면 한 칸이 생기므로 쓸 수 있습니다.
    wire do_write = write_en && (!full || do_read);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_ptr <= {PTR_WIDTH{1'b0}};
            read_ptr  <= {PTR_WIDTH{1'b0}};
            count     <= {COUNT_WIDTH{1'b0}};
            overflow  <= 1'b0;
        end else begin
            // 쓰기가 수락되면 현재 write_ptr 위치에 저장
            if (do_write) begin
                memory[write_ptr] <= write_data;

                if (write_ptr == DEPTH - 1)
                    write_ptr <= {PTR_WIDTH{1'b0}};
                else
                    write_ptr <= write_ptr + 1'b1;
            end

            // 읽기가 수락되면 다음 항목으로 이동
            if (do_read) begin
                if (read_ptr == DEPTH - 1)
                    read_ptr <= {PTR_WIDTH{1'b0}};
                else
                    read_ptr <= read_ptr + 1'b1;
            end

            // 저장된 항목 수 갱신
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1; // 쓰기만
                2'b01: count <= count - 1'b1; // 읽기만
                default: count <= count;      // 둘 다 또는 둘 다 없음
            endcase

            // 가득 차서 새 결과를 버렸다면 기록
            if (write_en && !do_write)
                overflow <= 1'b1;
        end
    end

endmodule