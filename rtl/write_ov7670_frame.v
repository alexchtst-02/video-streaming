`timescale 1ns / 1ps

module write_ov7670_frame #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,

    // Frame control
    input wire [1:0] frame_executor_cmd,
    input wire capture_frame_valid,
    input wire capture_frame_error,

    output wire send_trig_safe_pixel_frame,
    output wire done_one_frame,
    output wire frame_is_valid,

    // FIFO upstream interface
    input wire fifo_valid,
    input wire [AXI_DATA_WIDTH-1:0] fifo_dout,
    output wire ready_to_upstream,

    // AXI write address channel
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

    // AXI write data channel
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,

    // AXI write response channel
    input wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);

    // Internal frame executor / AXI write interface
    wire start_axi;
    wire [ADDR_WIDTH-1:0] base_addr_axi;

    wire axi_busy;
    wire axi_done;
    wire axi_error;
    wire [3:0] axi_error_code;

    // Frame executor
    write_frame_exec #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BURST_BEAT(BURST_BEAT)
    ) uut_frame_exec (
        .aclk(aclk),
        .aresetn(aresetn),
        .init_calib_complete(init_calib_complete),

        .frame_executor_cmd(frame_executor_cmd),

        .axi_busy(axi_busy),
        .axi_done(axi_done),
        .axi_error(axi_error),
        .axi_error_code(axi_error_code),

        .capture_frame_valid(capture_frame_valid),
        .capture_frame_error(capture_frame_error),

        .start_axi(start_axi),
        .base_addr_axi(base_addr_axi),

        .send_trig_safe_pixel_frame(send_trig_safe_pixel_frame),
        .done_one_frame(done_one_frame),
        .frame_is_valid(frame_is_valid)
    );

    // AXI write master
    axi_write #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BURST_BEAT(BURST_BEAT)
    ) uut_axi_write (
        .aclk(aclk),
        .aresetn(aresetn),
        .init_calib_complete(init_calib_complete),

        // Frame executor interface
        .start(start_axi),
        .base_addr(base_addr_axi),

        .busy(axi_busy),
        .done(axi_done),
        .error(axi_error),
        .error_code(axi_error_code),

        // FIFO upstream interface
        .fifo_valid(fifo_valid),
        .fifo_dout(fifo_dout),
        .ready_to_upstream(ready_to_upstream),

        // AXI write address channel
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

        // AXI write data channel
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),

        // AXI write response channel
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

endmodule
