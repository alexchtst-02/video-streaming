`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: cam_capture.v
// author : amsacks

module camera_capture #(
    parameter [9:0] FRAME_WIDTH  = 10'd640,
    parameter [9:0] FRAME_HEIGHT = 10'd480
)(
    input  wire        pclk,
    input  wire        rstn_pclk,
    input  wire        cam_done_pclk,
    input  wire        capture_start,
    input  wire [7:0]  pix_byte,
    input  wire        vsync,
    input  wire        href,

    output reg         capture_done = 1'b0,
    output reg         frame_start  = 1'b0,
    output reg         frame_done   = 1'b0,
    output reg  [9:0]  cam_x        = 10'd0,
    output reg  [9:0]  cam_y        = 10'd0,
    output reg         pix_wr       = 1'b0,
    output reg  [11:0] pix_data     = 12'd0,
    output reg  [18:0] pix_addr     = 19'd0
);
    wire pclk_resetn;

    resetn_sync u_capture_pclk_reset (
        .clk   (pclk),
        .arstn (rstn_pclk),
        .srstn (pclk_resetn)
    );

    // Synchronize the one-shot request from the system/AXI clock domain.
    (* ASYNC_REG = "TRUE" *) reg capture_req_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg capture_req_sync = 1'b0;
    reg capture_req_sync_d = 1'b0;
    wire capture_req_rise = capture_req_sync && !capture_req_sync_d;

    always @(posedge pclk or negedge rstn_pclk) begin
        if (!rstn_pclk) begin
            capture_req_meta   <= 1'b0;
            capture_req_sync   <= 1'b0;
            capture_req_sync_d <= 1'b0;
        end else begin
            capture_req_meta   <= capture_start;
            capture_req_sync   <= capture_req_meta;
            capture_req_sync_d <= capture_req_sync;
        end
    end

    // OV7670 uses the falling VSYNC boundary as the start of a frame and
    // the rising boundary as the end of a frame.
    reg vsync_d1 = 1'b0;
    reg vsync_d2 = 1'b0;
    wire camera_frame_start = !vsync_d1 &&  vsync_d2;
    wire camera_frame_done  =  vsync_d1 && !vsync_d2;

    always @(posedge pclk or negedge rstn_pclk) begin
        if (!rstn_pclk) begin
            vsync_d1 <= 1'b0;
            vsync_d2 <= 1'b0;
        end else begin
            vsync_d1 <= vsync;
            vsync_d2 <= vsync_d1;
        end
    end

    reg capture_pending = 1'b0;
    reg capture_active = 1'b0;
    reg byte_phase = 1'b0;
    reg [3:0] red_nibble = 4'd0;
    reg [9:0] next_x = 10'd0;
    reg [9:0] next_y = 10'd0;
    reg [18:0] next_pixel_addr = 19'd0;

    always @(posedge pclk) begin
        if (!pclk_resetn) begin
            capture_pending <= 1'b0;
            capture_active  <= 1'b0;
            capture_done    <= 1'b0;
            byte_phase      <= 1'b0;
            red_nibble      <= 4'd0;
            next_x          <= 10'd0;
            next_y          <= 10'd0;
            next_pixel_addr <= 19'd0;

            frame_start <= 1'b0;
            frame_done  <= 1'b0;
            cam_x       <= 10'd0;
            cam_y       <= 10'd0;
            pix_wr      <= 1'b0;
            pix_data    <= 12'd0;
            pix_addr    <= 19'd0;
        end else begin
            frame_start <= 1'b0;
            frame_done  <= 1'b0;
            pix_wr      <= 1'b0;

            if (!href)
                byte_phase <= 1'b0;

            if (capture_req_rise && !capture_pending && !capture_active) begin
                capture_pending <= 1'b1;
                capture_done    <= 1'b0;
            end

            // Start at the next complete frame boundary after the request.
            if (capture_pending && cam_done_pclk && camera_frame_start) begin
                capture_pending <= 1'b0;
                capture_active  <= 1'b1;
                byte_phase      <= 1'b0;
                next_x          <= 10'd0;
                next_y          <= 10'd0;
                next_pixel_addr <= 19'd0;
                frame_start     <= 1'b1;
            end else if (capture_active && camera_frame_done) begin
                capture_active <= 1'b0;
                capture_done   <= 1'b1;
                byte_phase     <= 1'b0;
                frame_done     <= 1'b1;
            end else if (capture_active && href) begin
                if (!byte_phase) begin
                    // First byte contains the red nibble in its low bits.
                    red_nibble <= pix_byte[3:0];
                    byte_phase <= 1'b1;
                end else begin
                    // The second byte contains the green and blue nibbles.
                    byte_phase      <= 1'b0;
                    pix_data        <= {red_nibble, pix_byte};
                    pix_wr          <= 1'b1;
                    cam_x           <= next_x;
                    cam_y           <= next_y;
                    pix_addr        <= next_pixel_addr;
                    next_pixel_addr <= next_pixel_addr + 1'b1;

                    if (next_x == FRAME_WIDTH - 1'b1) begin
                        next_x <= 10'd0;
                        if (next_y == FRAME_HEIGHT - 1'b1)
                            next_y <= 10'd0;
                        else
                            next_y <= next_y + 1'b1;
                    end else begin
                        next_x <= next_x + 1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
