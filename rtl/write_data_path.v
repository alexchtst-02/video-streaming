`timescale 1ns / 1ps
`default_nettype none

// OV7670 -> 16-bit pixel FIFO -> AXI frame writer, using RTL modules only.
// clk is the camera configuration clock; aclk is the MIG AXI/UI clock.
// Camera XCLK, clock generators, MIG, interconnect and frame manager remain
// outside this wrapper. Frame size matches write_frame_exec: 640 x 480.
module write_data_path #(
    parameter integer CAM_CONFIG_CLK = 100_000_000,
    parameter integer SCCB_F = 400_000,
    parameter integer ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16,
    parameter integer FIFO_DEPTH = 2048
)(
    // Keep the configuration clock as a plain RTL pin so Vivado does not
    // automatically associate this independent clock with the AXI bus.
    (* X_INTERFACE_IGNORE = "true" *)
    input wire clk,
    input wire sys_rstn,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,

    // Command/status on aclk, directly compatible with frame_manager.
    input wire [1:0] frame_executor_cmd,
    output wire done_one_frame,
    output wire frame_is_valid,

    // OV7670 pins. Supply cam_xclk separately, as in the existing block design.
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cam_pclk, ASSOCIATED_RESET sys_rstn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 cam_pclk CLK" *)
    input wire cam_pclk,
    input wire [7:0] cam_d,
    input wire cam_vsync,
    input wire cam_href,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cam_rst, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 cam_rst RST" *)
    output wire cam_rst,
    output wire cam_pwdn,
    inout wire cam_sda,
    output wire cam_scl,

    // AXI write address channel.
    output wire [AXI_ID_WIDTH-1:0] m_axi_awid,
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awlock,
    output wire [3:0] m_axi_awcache,
    output wire [2:0] m_axi_awprot,
    output wire [3:0] m_axi_awqos,
    output wire m_axi_awvalid,
    input wire m_axi_awready,

    // AXI write data channel.
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,

    // AXI write response channel.
    input wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    localparam integer PIXELS_PER_BEAT = AXI_DATA_WIDTH / 16;
    localparam integer BURST_BYTES = (AXI_DATA_WIDTH / 8) * BURST_BEAT;

    wire capture_start;
    wire capture_valid;
    wire capture_error;
    wire [15:0] pixel_data;
    wire pixel_valid;
    wire pixel_ready;
    wire [AXI_DATA_WIDTH-1:0] fifo_data;
    wire fifo_valid;
    wire fifo_ready;

    guarded_ov7670 #(
        .CAM_CONFIG_CLK(CAM_CONFIG_CLK),
        .SCCB_F(SCCB_F),
        .FRAME_WIDTH(10'd640),
        .FRAME_HEIGHT(10'd480),
        .USE_RGB_COLOR_BAR(1'b0)
    ) u_camera (
        .clk(clk),
        .rstn(sys_rstn),
        .rstn_pclk(sys_rstn),
        .capture_start(capture_start),
        .fifo_ready(pixel_ready),
        .cam_rst(cam_rst),
        .cam_pwdn(cam_pwdn),
        .cam_sda(cam_sda),
        .cam_scl(cam_scl),
        .frame_valid(capture_valid),
        .frame_error(capture_error),
        .valid_data(pixel_valid),
        .data(pixel_data),
        .cam_pclk(cam_pclk),
        .cam_d(cam_d),
        .cam_vsync(cam_vsync),
        .cam_href(cam_href),
        .dbg_cam_init_done(),
        .dbg_cam_done_pclk(),
        .dbg_capture_done(),
        .dbg_state(),
        .dbg_error_flags(),
        .dbg_frame_start(),
        .dbg_frame_done(),
        .dbg_cam_x(),
        .dbg_cam_y(),
        .dbg_pix_wr(),
        .dbg_pix_data(),
        .dbg_pix_addr()
    );

    attributed_async_fifo #(
        .WORD_WIDTH(16),
        .DEPTH(FIFO_DEPTH),
        .UNPAKCER_DATA_NUM(1),
        .PAKCER_DATA_NUM(PIXELS_PER_BEAT),
        .ALOWED_SKIP_VALUE(1'b0)
    ) u_write_fifo (
        .sys_rstn(sys_rstn),
        .wr_clk(cam_pclk),
        .rd_clk(aclk),
        .downstream_ready(fifo_ready),
        .valid_in(pixel_valid),
        .din(pixel_data),
        .ready_to_upstream(pixel_ready),
        .valid_out(fifo_valid),
        .dout(fifo_data),
        .full(),
        .rd_level(),
        .wr_level(),
        .empty()
    );

    write_ov7670_frame #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BURST_BEAT(BURST_BEAT)
    ) u_writer (
        .aclk(aclk),
        .aresetn(aresetn),
        .init_calib_complete(init_calib_complete),
        .frame_executor_cmd(frame_executor_cmd),
        .capture_frame_valid(capture_valid),
        .capture_frame_error(capture_error),
        .send_trig_safe_pixel_frame(capture_start),
        .done_one_frame(done_one_frame),
        .frame_is_valid(frame_is_valid),
        .fifo_valid(fifo_valid),
        .fifo_dout(fifo_data),
        .ready_to_upstream(fifo_ready),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    initial begin
        if (ADDR_WIDTH < 21 || AXI_ID_WIDTH < 1 || AXI_DATA_WIDTH < 16 ||
            AXI_DATA_WIDTH > 1024 || AXI_DATA_WIDTH % 16 != 0 ||
            (AXI_DATA_WIDTH & (AXI_DATA_WIDTH-1)) != 0)
            $fatal(1, "Invalid AXI widths for the RGB444 double-buffer layout");
        if (BURST_BEAT < 1 || BURST_BEAT > 256 || BURST_BYTES > 4096 ||
            4096 % BURST_BYTES != 0 || 614400 % BURST_BYTES != 0)
            $fatal(1, "AXI bursts must divide the frame and 4 KiB boundaries exactly");
        if (FIFO_DEPTH < 16 || (FIFO_DEPTH & (FIFO_DEPTH-1)) != 0 ||
            FIFO_DEPTH < PIXELS_PER_BEAT + 3)
            $fatal(1, "FIFO_DEPTH must be a sufficient power of two");
    end
endmodule

`default_nettype wire
