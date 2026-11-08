`timescale 1ns / 1ps
`default_nettype none

module px_watcher #(
    parameter [0:0] USE_RGB_COLOR_BAR = 1'b0,
    parameter [9:0] FRAME_WIDTH        = 10'd640,
    parameter [9:0] FRAME_HEIGHT       = 10'd480
)(
    input wire        cam_cplk,
    input wire        sys_rstn,

    input wire trig_start_stream,

    // Camera input
    input wire [11:0] pixel_data,
    input wire pixel_valid,
    input wire frame_start,
    input wire frame_done,
    input wire [9:0] cam_x,
    input wire [9:0] cam_y,

    input wire cam_conf_done_pclk,
    input wire fifo_ready,

    // Status
    output reg [1:0] state,
    output reg frame_valid,
    output reg frame_error,
    output reg [3:0] error_flags,

    // Streaming output
    output wire [15:0] data,
    output wire valid_data
);

    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] START = 2'b01;
    localparam [1:0] STREAM = 2'b10;
    localparam [1:0] DONE = 2'b11;

    wire resetn;

    resetn_sync uut_resetn (
        .clk   (cam_cplk),
        .arstn (sys_rstn),
        .srstn (resetn)
    );

    // ============================================================
    // REQUEST SYNCHRONIZER
    // ============================================================
    wire request_sync;
    reg request_sync_d;

    cdc_bit_sync u_trigger_cdc (
        .aclk   (cam_cplk),
        .aresetn(sys_rstn),
        .in     (trig_start_stream),
        .out    (request_sync)
    );

    always @(posedge cam_cplk or negedge sys_rstn) begin
        if (!sys_rstn) begin
            request_sync_d <= 1'b0;
        end else begin
            request_sync_d <= request_sync;
        end
    end

    wire request_rise = request_sync && !request_sync_d;

    // ============================================================
    // FRAME CONFIGURATION
    // ============================================================
    localparam integer MAX_PIXEL_STREAM = FRAME_WIDTH * FRAME_HEIGHT;

    reg [18:0] px_cnt;

    reg [9:0] expected_x;
    reg [9:0] expected_y;

    // ============================================================
    // ERROR FLAGS
    // ============================================================
    // bit 0 : Coordinate mismatch
    // bit 1 : Incomplete frame
    // bit 2 : Pixel overflow or FIFO could not accept a pixel
    // bit 3 : Frame interrupted

    // ============================================================
    // RGB444 COLOR BAR GENERATOR
    // ============================================================
    // Resolution : 640 x 480
    // Total bars : 8
    // Bar width  : 80 pixels
    //
    // RGB444 format: [11:8] = red, [7:4] = green, [3:0] = blue.
    // ============================================================

    reg [11:0] rgb444_color_bar;

    always @(*) begin
        if (cam_x < FRAME_WIDTH / 8)
            rgb444_color_bar = 12'hFFF; // White
        else if (cam_x < (FRAME_WIDTH / 8) * 2)
            rgb444_color_bar = 12'hFF0; // Yellow
        else if (cam_x < (FRAME_WIDTH / 8) * 3)
            rgb444_color_bar = 12'h0FF; // Cyan
        else if (cam_x < (FRAME_WIDTH / 8) * 4)
            rgb444_color_bar = 12'h0F0; // Green
        else if (cam_x < (FRAME_WIDTH / 8) * 5)
            rgb444_color_bar = 12'hF0F; // Magenta
        else if (cam_x < (FRAME_WIDTH / 8) * 6)
            rgb444_color_bar = 12'hF00; // Red
        else if (cam_x < (FRAME_WIDTH / 8) * 7)
            rgb444_color_bar = 12'h00F; // Blue
        else if (cam_x < FRAME_WIDTH)
            rgb444_color_bar = 12'h000; // Black
        else
            rgb444_color_bar = 12'h000;
    end

    wire [11:0] pixel_rgb444 = USE_RGB_COLOR_BAR ? rgb444_color_bar : pixel_data;
    assign data = {4'b0000, pixel_rgb444};

    assign valid_data =
        (state == STREAM) && pixel_valid 
            && cam_conf_done_pclk && !frame_start 
                && !frame_done && fifo_ready
                    && (px_cnt < MAX_PIXEL_STREAM);

    always @(posedge cam_cplk) begin
        if (!resetn) begin
            state <= IDLE;
            px_cnt <= 19'd0;
            expected_x <= 10'd0;
            expected_y <= 10'd0;
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
            error_flags <= 4'b0000;

        end else begin
            case (state)
                IDLE: begin
                    if (request_rise) begin
                        frame_valid <= 1'b0;
                        frame_error <= 1'b0;
                        error_flags <= 4'b0000;
                        state <= START;
                    end
                end

                START: begin
                    if (cam_conf_done_pclk && frame_start) begin
                        px_cnt      <= 19'd0;
                        expected_x  <= 10'd0;
                        expected_y  <= 10'd0;
                        error_flags <= 4'b0000;

                        state <= STREAM;
                    end
                end

                STREAM: begin
                    if (!cam_conf_done_pclk) begin
                        error_flags[3] <= 1'b1;
                        frame_error <= 1'b1;
                        state <= DONE;
                    end

                    else if (frame_start) begin
                        error_flags[3] <= 1'b1;
                        frame_error <= 1'b1;
                        state <= DONE;
                    end

                    else if (frame_done) begin

                        if (px_cnt != MAX_PIXEL_STREAM)
                            error_flags[1] <= 1'b1;

                        if ((px_cnt == MAX_PIXEL_STREAM) &&
                            (error_flags == 4'b0000)) begin
                            frame_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end

                        state <= DONE;
                    end

                    else if (pixel_valid) begin

                        if ((px_cnt >= MAX_PIXEL_STREAM) ||
                            !fifo_ready) begin
                            error_flags[2] <= 1'b1;
                        end

                        if (px_cnt < MAX_PIXEL_STREAM) begin

                            if ((cam_x != expected_x) || (cam_y != expected_y)) begin
                                error_flags[0] <= 1'b1;
                            end

                            px_cnt <= px_cnt + 1'b1;

                            if (expected_x == FRAME_WIDTH - 1'b1) begin
                                expected_x <= 10'd0;
                                if (expected_y == FRAME_HEIGHT - 1'b1)
                                    expected_y <= 10'd0;
                                else
                                    expected_y <= expected_y + 1'b1;
                            end else begin
                                expected_x <= expected_x + 1'b1;
                            end
                        end
                    end
                end

                DONE: begin
                    // A later rising trigger can capture another single frame.
                    if (request_rise) begin
                        frame_valid <= 1'b0;
                        frame_error <= 1'b0;
                        error_flags <= 4'b0000;
                        state <= START;
                    end else begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end
    
endmodule

`default_nettype wire
