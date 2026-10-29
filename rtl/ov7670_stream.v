`timescale 1ns / 1ps
`default_nettype none

// OV7670 initialization and one-shot RGB444 capture wrapper.
module ov7670_stream #(
    parameter integer CAM_CONFIG_CLK = 100_000_000,
    parameter integer SCCB_F         = 400_000,
    parameter [9:0]  FRAME_WIDTH     = 10'd640,
    parameter [9:0]  FRAME_HEIGHT    = 10'd480
)(
    input  wire        clk,
    input  wire        rstn,
    input  wire        rstn_pclk,

    input  wire        cam_init_start,
    output wire        cam_init_done,
    output wire        cam_done_pclk,

    input  wire        capture_start,
    output wire        capture_done,

    input  wire        pclk,
    input  wire [7:0]  pix_byte,
    input  wire        vsync,
    input  wire        href,

    output wire        reset,
    output wire        pwdn,
    inout  wire        siod,
    output wire        sioc,

    output wire        frame_start,
    output wire        frame_done,
    output wire [9:0]  cam_x,
    output wire [9:0]  cam_y,
    output wire        pix_wr,
    output wire [11:0] pix_data,
    output wire [18:0] pix_addr
);
    wire init_start_db;

    assign reset = 1'b1;
    assign pwdn  = 1'b0;

    debouncer #(
        .DELAY(240_000)
    ) cam_init_debouncer (
        .clk      (clk),
        .btn      (cam_init_start),
        .signal_db(init_start_db)
    );

    camera_initialization #(
        .CLK_F (CAM_CONFIG_CLK),
        .SCCB_F(SCCB_F)
    ) camera_init (
        .clk           (clk),
        .rstn         (rstn),
        .cam_init_start(init_start_db),
        .siod          (siod),
        .sioc          (sioc),
        .cam_init_done (cam_init_done),
        .data_sent_done(),
        .SCCB_dout     ()
    );

    // Cross the configuration-done level into the camera PCLK domain.
    (* ASYNC_REG = "TRUE" *) reg cam_done_meta;
    (* ASYNC_REG = "TRUE" *) reg cam_done_sync;
    reg cam_done_pclk_reg;

    assign cam_done_pclk = cam_done_pclk_reg;

    always @(posedge pclk or negedge rstn_pclk) begin
        if (!rstn_pclk) begin
            cam_done_meta <= 1'b0;
            cam_done_sync <= 1'b0;
            cam_done_pclk_reg <= 1'b0;
        end else begin
            cam_done_meta <= cam_init_done;
            cam_done_sync <= cam_done_meta;
            cam_done_pclk_reg <= cam_done_sync;
        end
    end

    camera_capture #(
        .FRAME_WIDTH (FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) capture (
        .pclk         (pclk),
        .rstn_pclk    (rstn_pclk),
        .cam_done_pclk(cam_done_pclk_reg),
        .capture_start(capture_start),
        .pix_byte     (pix_byte),
        .vsync        (vsync),
        .href         (href),
        .capture_done (capture_done),
        .frame_start  (frame_start),
        .frame_done   (frame_done),
        .cam_x        (cam_x),
        .cam_y        (cam_y),
        .pix_wr       (pix_wr),
        .pix_data     (pix_data),
        .pix_addr     (pix_addr)
    );
endmodule

`default_nettype wire
