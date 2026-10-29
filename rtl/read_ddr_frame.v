`timescale 1ns / 1ps

module read_ddr_frame #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer TIMEOUT_CYCLES = 400_000_000
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,

    // Frame control
    input wire [1:0] frame_executor_cmd,
    output wire done_one_frame,
    output wire frame_is_valid,
    output wire busy,
    output wire fault,
    output wire [3:0] fault_code,

    // FIFO downstream interface
    output wire fifo_valid,
    output wire [AXI_DATA_WIDTH-1:0] fifo_din,
    input wire ready_from_fifo,

    // AXI read address channel
    output wire [AXI_ID_WIDTH-1:0] m_axi_arid,
    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arlock,
    output wire [3:0] m_axi_arcache,
    output wire [2:0] m_axi_arprot,
    output wire [3:0] m_axi_arqos,
    output wire m_axi_arvalid,
    input wire m_axi_arready,

    // AXI read data channel
    input wire [AXI_ID_WIDTH-1:0] m_axi_rid,
    input wire [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    wire start_axi;
    wire [ADDR_WIDTH-1:0] base_addr_axi;
    wire axi_busy;
    wire axi_done;
    wire axi_error;
    wire [3:0] axi_error_code;

    read_frame_exec #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BURST_BEAT(BURST_BEAT),
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) uut_frame_exec (
        .aclk(aclk),
        .aresetn(aresetn),
        .init_calib_complete(init_calib_complete),
        .frame_executor_cmd(frame_executor_cmd),
        .axi_busy(axi_busy),
        .axi_done(axi_done),
        .axi_error(axi_error),
        .axi_error_code(axi_error_code),
        .start_axi(start_axi),
        .base_addr_axi(base_addr_axi),
        .done_one_frame(done_one_frame),
        .frame_is_valid(frame_is_valid),
        .busy(busy),
        .fault(fault),
        .fault_code(fault_code)
    );

    axi_read #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .BURST_BEAT(BURST_BEAT)
    ) uut_axi_read (
        .aclk(aclk),
        .aresetn(aresetn),
        .init_calib_complete(init_calib_complete),
        .start(start_axi),
        .base_addr(base_addr_axi),
        .busy(axi_busy),
        .done(axi_done),
        .error(axi_error),
        .error_code(axi_error_code),
        .fifo_din(fifo_din),
        .fifo_valid(fifo_valid),
        .ready_from_fifo(ready_from_fifo),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

endmodule
