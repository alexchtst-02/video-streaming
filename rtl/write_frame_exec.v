`timescale 1ns / 1ps
`default_nettype none

module write_frame_exec #(
    parameter integer ADDR_WIDTH     = 28,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH   = 4,
    parameter integer BURST_BEAT     = 16
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,

    input wire [1:0] frame_executor_cmd,

    input wire axi_busy,
    input wire axi_done,
    input wire axi_error,
    input wire [3:0] axi_error_code,

    input wire capture_frame_valid,
    input wire capture_frame_error,

    output reg start_axi,
    output reg [ADDR_WIDTH-1:0] base_addr_axi,

    output reg send_trig_safe_pixel_frame,
    output reg done_one_frame,
    output reg frame_is_valid
);
    localparam integer FRAME_WIDTH  = 640;
    localparam integer FRAME_HEIGHT = 480;
    localparam integer PIXEL_BYTES  = 2;

    localparam integer FRAME_BYTES = FRAME_WIDTH * FRAME_HEIGHT * PIXEL_BYTES;
    localparam integer ADDR_INCR = (AXI_DATA_WIDTH / 8) * BURST_BEAT;
    localparam integer TOTAL_BURST =
        (FRAME_BYTES + ADDR_INCR - 1) / ADDR_INCR;
    localparam integer BURST_COUNT_WIDTH =
        (TOTAL_BURST > 1) ? $clog2(TOTAL_BURST) : 1;

    localparam integer CAPTURE_TIMEOUT_CYCLES = 40_000_000;
    localparam integer TIMEOUT_WIDTH = $clog2(CAPTURE_TIMEOUT_CYCLES);

    wire allow_running = frame_executor_cmd[1];
    wire base_address_id = frame_executor_cmd[0];

    localparam [ADDR_WIDTH-1:0] BASE_0 = 'h0000000;
    localparam [ADDR_WIDTH-1:0] BASE_1 = 'h0096000;

    localparam [2:0] IDLE       = 3'd0;
    localparam [2:0] BURST      = 3'd1;
    localparam [2:0] WAIT_BURST = 3'd2;
    localparam [2:0] DONE       = 3'd3;
    localparam [2:0] FAULT      = 3'd4;

    localparam [3:0] ERR_BID = 4'd4;

    reg [2:0] state;
    reg [BURST_COUNT_WIDTH-1:0] burst_count;
    reg [TIMEOUT_WIDTH-1:0] timeout_count;
    reg frame_error_seen;

    wire capture_valid_sync;
    wire capture_error_sync;

    cdc_bit_sync u_capture_valid_cdc (
        .aclk   (aclk),
        .aresetn(aresetn),
        .in     (capture_frame_valid),
        .out    (capture_valid_sync)
    );

    cdc_bit_sync u_capture_error_cdc (
        .aclk   (aclk),
        .aresetn(aresetn),
        .in     (capture_frame_error),
        .out    (capture_error_sync)
    );

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            burst_count <= 0;
            timeout_count <= 0;
            base_addr_axi <= 0;

            start_axi <= 1'b0;
            send_trig_safe_pixel_frame <= 1'b0;
            done_one_frame <= 1'b0;
            frame_is_valid <= 1'b0;
            frame_error_seen <= 1'b0;
        end else begin
            start_axi <= 1'b0;
            done_one_frame <= 1'b0;

            if (state == IDLE)
                timeout_count <= 0;
            else if (state != FAULT)
                timeout_count <= timeout_count + 1'b1;

            if (capture_error_sync && state != IDLE)
                frame_error_seen <= 1'b1;

            if (state != IDLE && state != FAULT &&
                timeout_count == CAPTURE_TIMEOUT_CYCLES - 1) begin
                send_trig_safe_pixel_frame <= 1'b0;
                frame_is_valid <= 1'b0;
                done_one_frame <= 1'b1;
                state <= FAULT;
            end else begin
                case (state)
                    IDLE: begin
                        if (allow_running &&
                            init_calib_complete &&
                            !axi_busy) begin
                            base_addr_axi <=
                                base_address_id ? BASE_1 : BASE_0;
                            burst_count <= 0;
                            frame_error_seen <= 1'b0;
                            frame_is_valid <= 1'b0;
                            send_trig_safe_pixel_frame <= 1'b1;
                            state <= BURST;
                        end
                    end

                    BURST: begin
                        if (!axi_busy) begin
                            start_axi <= 1'b1;
                            state <= WAIT_BURST;
                        end
                    end

                    WAIT_BURST: begin
                        if (axi_error && axi_error_code == ERR_BID) begin
                            frame_error_seen <= 1'b1;
                            frame_is_valid <= 1'b0;
                            send_trig_safe_pixel_frame <= 1'b0;
                            done_one_frame <= 1'b1;
                            state <= FAULT;
                        end else if (axi_done || axi_error) begin
                            if (axi_error)
                                frame_error_seen <= 1'b1;

                            if (burst_count == TOTAL_BURST - 1) begin
                                state <= DONE;
                            end else begin
                                burst_count <= burst_count + 1'b1;
                                base_addr_axi <= base_addr_axi + ADDR_INCR;
                                state <= BURST;
                            end
                        end
                    end

                    DONE: begin
                        if (capture_valid_sync || capture_error_sync) begin
                            done_one_frame <= 1'b1;
                            frame_is_valid <= capture_valid_sync &&
                                              !capture_error_sync &&
                                              !frame_error_seen;
                            send_trig_safe_pixel_frame <= 1'b0;
                            state <= IDLE;
                        end
                    end

                    FAULT: begin
                        state <= FAULT;
                    end

                    default: begin
                        state <= IDLE;
                    end
                endcase
            end
        end
    end
endmodule

`default_nettype wire
