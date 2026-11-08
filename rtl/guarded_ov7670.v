`timescale 1ns / 1ps
`default_nettype none

module guarded_ov7670 #(
    parameter integer CAM_CONFIG_CLK      = 100_000_000,
    parameter integer SCCB_F              = 400_000,
    parameter [9:0]  FRAME_WIDTH          = 10'd640,
    parameter [9:0]  FRAME_HEIGHT         = 10'd480,
    parameter [0:0]  USE_RGB_COLOR_BAR    = 1'b0
)(
    // Core clocks, resets, and control
    input  wire        clk,
    input  wire        rstn,
    input  wire        rstn_pclk,
    input  wire        capture_start,
    input  wire        fifo_ready,
    
    output wire        cam_rst,
    output wire        cam_pwdn,
    inout  wire        cam_sda,
    output wire        cam_scl,

    // Core stream and frame status
    output wire        frame_valid,
    output wire        frame_error,
    output wire        valid_data,
    output wire [15:0] data,

    // Configuration and capture status
    output wire        dbg_cam_init_done,
    output wire        dbg_cam_done_pclk,
    output wire        dbg_capture_done,

    // Physical camera interface
    input  wire        cam_pclk,
    input  wire [7:0]  cam_d,
    input  wire        cam_vsync,
    input  wire        cam_href,

    // Debug and raw capture outputs
    output wire [1:0]  dbg_state,
    output wire [3:0]  dbg_error_flags,
    output wire        dbg_frame_start,
    output wire        dbg_frame_done,
    output wire [9:0]  dbg_cam_x,
    output wire [9:0]  dbg_cam_y,
    output wire        dbg_pix_wr,
    output wire [11:0] dbg_pix_data,
    output wire [18:0] dbg_pix_addr
);
    wire        cam_init_done;
    wire        cam_done_pclk;
    wire        capture_done;
    wire        frame_start;
    wire        frame_done;
    wire [9:0]  cam_x;
    wire [9:0]  cam_y;
    wire        pix_wr;
    wire [11:0] pix_data;
    wire [18:0] pix_addr;
    wire [1:0]  state;
    wire [3:0]  error_flags;

    assign dbg_cam_init_done  = cam_init_done;
    assign dbg_cam_done_pclk  = cam_done_pclk;
    assign dbg_capture_done   = capture_done;
    assign dbg_state          = state;
    assign dbg_error_flags    = error_flags;
    assign dbg_frame_start    = frame_start;
    assign dbg_frame_done     = frame_done;
    assign dbg_cam_x          = cam_x;
    assign dbg_cam_y          = cam_y;
    assign dbg_pix_wr         = pix_wr;
    assign dbg_pix_data       = pix_data;
    assign dbg_pix_addr       = pix_addr;

    ov7670_stream #(
        .CAM_CONFIG_CLK(CAM_CONFIG_CLK),
        .SCCB_F        (SCCB_F),
        .FRAME_WIDTH   (FRAME_WIDTH),
        .FRAME_HEIGHT  (FRAME_HEIGHT)
    ) camera_stream (
        .clk           (clk),
        .rstn          (rstn),
        .rstn_pclk     (rstn_pclk),
        .cam_init_start(1'b1),
        .cam_init_done (cam_init_done),
        .cam_done_pclk (cam_done_pclk),
        .capture_start (capture_start),
        .capture_done  (capture_done),
        .pclk          (cam_pclk),
        .pix_byte      (cam_d),
        .vsync         (cam_vsync),
        .href          (cam_href),
        .reset         (cam_rst),
        .pwdn          (cam_pwdn),
        .siod          (cam_sda),
        .sioc          (cam_scl),
        .frame_start   (frame_start),
        .frame_done    (frame_done),
        .cam_x         (cam_x),
        .cam_y         (cam_y),
        .pix_wr        (pix_wr),
        .pix_data      (pix_data),
        .pix_addr      (pix_addr)
    );

    px_watcher #(
        .USE_RGB_COLOR_BAR(USE_RGB_COLOR_BAR),
        .FRAME_WIDTH     (FRAME_WIDTH),
        .FRAME_HEIGHT    (FRAME_HEIGHT)
    ) pixel_guard (
        .cam_cplk         (cam_pclk),
        .sys_rstn         (rstn_pclk),
        .trig_start_stream(capture_start),
        .pixel_data       (pix_data),
        .pixel_valid      (pix_wr),
        .frame_start      (frame_start),
        .frame_done       (frame_done),
        .cam_x            (cam_x),
        .cam_y            (cam_y),
        .cam_conf_done_pclk(cam_done_pclk),
        .fifo_ready       (fifo_ready),
        .state            (state),
        .frame_valid      (frame_valid),
        .frame_error      (frame_error),
        .error_flags      (error_flags),
        .data             (data),
        .valid_data       (valid_data)
    );
endmodule

`default_nettype wire
