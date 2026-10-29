`timescale 1ns / 1ps

module fifo_packer #(
    parameter integer WORD_WIDTH = 16,
    parameter integer DATA_NUM = 8
)(
    input wire clk,
    input wire sys_rstn,

    input wire downstream_ready,

    input wire fifo_rd_valid,
    input wire [WORD_WIDTH-1:0] fifo_rd_in,

    output wire fifo_rd_en,
    output wire valid_out,
    output wire [WORD_WIDTH*DATA_NUM-1:0] dout
);

    wire resetn;
    resetn_sync uut_resetn (
        .clk(clk),
        .arstn(sys_rstn),
        .srstn(resetn)
    );

    localparam integer REQ_CNT_WIDTH = (DATA_NUM <= 1) ? 1 : $clog2(DATA_NUM + 1);

    localparam integer CAP_CNT_WIDTH = (DATA_NUM <= 1) ? 1 : $clog2(DATA_NUM);

    // Collect FSM and Output FSM
    localparam C_WAIT = 1'b0;
    localparam C_COLLECT = 1'b1;

    localparam O_WAIT = 1'b0;
    localparam O_VALID = 1'b1;

    reg collect_state;
    reg output_state;

    // Double buffer
    reg [WORD_WIDTH*DATA_NUM-1:0] buffer_0;
    reg [WORD_WIDTH*DATA_NUM-1:0] buffer_1;
    reg [1:0] buffer_ready;

    reg active_bank;
    reg next_fill_bank;
    reg output_bank;

    reg [REQ_CNT_WIDTH-1:0] request_count;
    reg [CAP_CNT_WIDTH-1:0] capture_count;
    reg read_pending;

    wire output_fire = valid_out && downstream_ready;

    // Last registered FIFO word is ready to capture.
    wire last_capture =
        (collect_state == C_COLLECT)
            && read_pending
                && (capture_count == DATA_NUM - 1);

    wire request_more =
        (collect_state == C_COLLECT)
            && (request_count < DATA_NUM);

    // A buffer released on this clock may be allocated
    // for a new read request.
    wire fill_bank_available =
        !buffer_ready[next_fill_bank]
            || (output_fire && (output_bank == next_fill_bank));

    // Start a new packet, potentially overlapping
    // the final capture of the previous packet.
    wire start_packet =
        resetn
            && fifo_rd_valid
                && ((collect_state == C_WAIT) || last_capture)
                    && fill_bank_available;

    assign fifo_rd_en = resetn && (start_packet || request_more);

    assign valid_out = resetn && (output_state == O_VALID);

    assign dout = output_bank ? buffer_1 : buffer_0;

    // ===================================================
    // COLLECT FSM
    // ===================================================

    always @(posedge clk) begin
        if (!resetn) begin
            collect_state <= C_WAIT;
            active_bank <= 1'b0;
            next_fill_bank <= 1'b0;

            request_count <= 0;
            capture_count <= 0;
            read_pending <= 1'b0;

            buffer_0 <= 0;
            buffer_1 <= 0;
        end
        else begin
            // FIFO read result is captured on the
            // clock following its read request.
            read_pending <= fifo_rd_en;

            if (read_pending) begin

                if (active_bank == 1'b0) begin
                    buffer_0[capture_count*WORD_WIDTH +: WORD_WIDTH] <= fifo_rd_in;
                end
                else begin
                    buffer_1[capture_count*WORD_WIDTH +: WORD_WIDTH] <= fifo_rd_in;
                end

                if (!last_capture) begin
                    capture_count <= capture_count + 1'b1;
                end
            end

            if (collect_state == C_COLLECT) begin

                if (request_more) begin
                    request_count <= request_count + 1'b1;
                end

                if (last_capture) begin
                    collect_state <= C_WAIT;
                end
            end

            // Highest priority: allocate a buffer
            // and start requesting the next packet.
            if (start_packet) begin
                collect_state  <= C_COLLECT;

                active_bank <= next_fill_bank;
                next_fill_bank <= ~next_fill_bank;

                request_count <= 1;
                capture_count <= 0;
            end
        end
    end

    // ===================================================
    // BUFFER OWNERSHIP
    // ===================================================

    wire [1:0] mark_ready = last_capture ? (active_bank ? 2'b10 : 2'b01) : 2'b00;

    wire [1:0] clear_ready = output_fire ? (output_bank ? 2'b10 : 2'b01) : 2'b00;

    always @(posedge clk) begin
        if (!resetn) begin
            buffer_ready <= 2'b00;
        end
        else begin
            buffer_ready <= (buffer_ready & ~clear_ready) | mark_ready;
        end
    end

    // ===================================================
    // OUTPUT FSM
    // ===================================================

    // Include a buffer completing on this clock,
    // avoiding an additional waiting cycle.
    wire current_bank_ready = buffer_ready[output_bank] || (last_capture && active_bank == output_bank);

    wire next_bank_ready = buffer_ready[~output_bank] || (last_capture && active_bank != output_bank);

    always @(posedge clk) begin
        if (!resetn) begin
            output_state <= O_WAIT;
            output_bank  <= 1'b0;
        end
        else begin
            case (output_state)

                O_WAIT: begin
                    if (current_bank_ready) begin
                        output_state <= O_VALID;
                    end
                end

                O_VALID: begin
                    if (downstream_ready) begin

                        output_bank <= ~output_bank;

                        if (next_bank_ready) begin
                            output_state <= O_VALID;
                        end
                        else begin
                            output_state <= O_WAIT;
                        end
                    end
                end

                default: begin
                    output_state <= O_WAIT;
                end

            endcase
        end
    end

endmodule