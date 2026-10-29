`timescale 1ns / 1ps

module fifo_unpacker #(
    parameter integer WORD_WIDTH = 16,
    parameter integer DATA_NUM = 8
)(
    input wire clk,
    input wire sys_rstn,

    input wire valid_in,
    input wire [WORD_WIDTH*DATA_NUM-1:0] din,

    output wire trig_upstream,
    output reg fifo_wr_en,
    output reg [WORD_WIDTH-1:0] fifo_wr_in
);

    wire resetn;
    resetn_sync uut_resetn (
        .clk(clk),
        .arstn(sys_rstn),
        .srstn(resetn)
    );

    localparam integer CNT_WIDTH = (DATA_NUM <= 1) ? 1 : $clog2(DATA_NUM);

    reg [WORD_WIDTH-1:0] buff [0:DATA_NUM-1];
    reg [CNT_WIDTH-1:0] stream_cnt;

    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] COLLECTING = 2'b01;
    localparam [1:0] STREAMING = 2'b10;
    localparam [1:0] DONE = 2'b11;

    reg [1:0] state;
    integer i;

    // Only COLLECTING consumes valid_in. Advertising ready in IDLE or DONE
    // silently loses the word presented on that clock.
    assign trig_upstream = resetn && (state == COLLECTING);

    always @(posedge clk) begin
        if (!resetn) begin
            state <= IDLE;
            stream_cnt <= 0;
            fifo_wr_en <= 1'b0;
            fifo_wr_in <= 0;
        end
        else begin
            fifo_wr_en <= 1'b0;

            case (state)

                IDLE: begin
                    state <= COLLECTING;
                end

                COLLECTING: begin
                    if (valid_in) begin

                        for (i = 0; i < DATA_NUM; i = i + 1) begin
                            buff[i] <= din[WORD_WIDTH*i +: WORD_WIDTH];
                        end

                        fifo_wr_in <= din[0 +: WORD_WIDTH];
                        fifo_wr_en <= 1'b1;

                        if (DATA_NUM == 1) begin
                            // state <= DONE;
                            state <= COLLECTING;
                        end
                        else begin
                            stream_cnt <= 1;
                            state <= STREAMING;
                        end
                    end
                end

                STREAMING: begin
                    fifo_wr_in <= buff[stream_cnt];
                    fifo_wr_en <= 1'b1;

                    if (stream_cnt == DATA_NUM - 1) begin
                        state <= DONE;
                    end
                    else begin
                        stream_cnt <= stream_cnt + 1'b1;
                    end
                end

                DONE: begin
                    stream_cnt <= 0;
                    state <= COLLECTING;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
