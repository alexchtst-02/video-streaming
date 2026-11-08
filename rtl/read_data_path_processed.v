`timescale 1ns / 1ps
`default_nettype none

// DDR -> one asynchronous pixel FIFO -> frame processor -> VGA.
// AXI commands/status use aclk; processing, threshold and CNN use vga_clk.
module read_data_path_processed #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16,
    parameter integer FIFO_DEPTH = 2048,
    parameter integer DISPLAY_PREFILL = 512,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer ROI_SIZE = 280,
    parameter integer OUTPUT_SIZE = 28,
    parameter integer SAMPLE_OFFSET = 5,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33,
    parameter integer TIMEOUT_CYCLES = 400_000_000,
    parameter integer TRESH_INITIAL_VALUE = 128,
    parameter integer TRESH_DEBOUNCE_CYCLES = 1_000_000
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET aresetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input wire aclk,
    input wire aresetn,
    input wire sys_rstn,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME vga_clk, ASSOCIATED_RESET sys_rstn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 vga_clk CLK" *)
    input wire vga_clk,
    input wire init_calib_complete,
    input wire [1:0] frame_executor_cmd,
    output wire done_one_frame,
    output wire frame_is_valid,
    output wire busy,
    output wire fault,
    output wire [3:0] fault_code,

    input wire [3:0] sw_mode,
    input wire higher_up_tresh,
    input wire lower_down_tresh,
    // CNN pulses use vga_clk. No CNN-specific backpressure/queue is added here.
    output wire [7:0] cnn_dout,
    output wire cnn_valid_out,
    output wire processing_error,

    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire vga_hs,
    output wire vga_vs,
    output wire underflow,

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
    localparam integer FRAME_BYTES = FRAME_WIDTH*FRAME_HEIGHT*2;
    localparam integer BURST_BYTES = (AXI_DATA_WIDTH/8)*BURST_BEAT;
    wire [AXI_DATA_WIDTH-1:0] read_data;
    wire read_valid, read_fifo_ready;

    read_ddr_frame #(
        .ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH), .BURST_BEAT(BURST_BEAT),
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES)
    ) u_reader (
        .aclk(aclk), .aresetn(aresetn), .init_calib_complete(init_calib_complete),
        .frame_executor_cmd(frame_executor_cmd), .done_one_frame(done_one_frame),
        .frame_is_valid(frame_is_valid), .busy(busy), .fault(fault), .fault_code(fault_code),
        .fifo_din(read_data), .fifo_valid(read_valid), .ready_from_fifo(read_fifo_ready),
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

    wire [15:0] raw_pixel;
    wire raw_valid, raw_ready, raw_empty;
    wire [$clog2(FIFO_DEPTH):0] raw_level;
    wire [15:0] display_pixel;
    wire display_valid, display_ready;
    wire display_resetn, control_resetn;
    reg prefilled;
    (* ASYNC_REG = "TRUE" *) reg fault_meta, fault_sync;
    wire display_fault = fault_sync || processing_error;

    resetn_sync u_display_reset (
        .clk(vga_clk), .arstn(sys_rstn), .srstn(display_resetn)
    );
    // AXI reset crosses into the video clock domain before releasing button
    // controller reset. The multi-bit threshold never crosses clock domains.
    resetn_sync u_control_reset (
        .clk(vga_clk), .arstn(sys_rstn && aresetn), .srstn(control_resetn)
    );

    // This is the only stream FIFO. The consumer is now on the VGA clock.
    // Hold input consumption until the FIFO has a startup reserve, then let
    // the processor prime its line/pipeline registers before VGA (0,0).
    attributed_async_fifo #(
        .WORD_WIDTH(16), .DEPTH(FIFO_DEPTH),
        .UNPAKCER_DATA_NUM(AXI_DATA_WIDTH/16), .PAKCER_DATA_NUM(1),
        .ALOWED_SKIP_VALUE(1'b0)
    ) u_read_fifo (
        .sys_rstn(sys_rstn), .wr_clk(aclk), .rd_clk(vga_clk),
        .downstream_ready(raw_ready && prefilled && !display_fault),
        .valid_in(read_valid), .din(read_data),
        .ready_to_upstream(read_fifo_ready), .valid_out(raw_valid), .dout(raw_pixel),
        .full(), .rd_level(raw_level), .wr_level(), .empty(raw_empty)
    );

    wire [7:0] tresh_val;
    tresh_value_control #(
        .INITIAL_VALUE(TRESH_INITIAL_VALUE),
        .DEBOUNCE_CYCLES(TRESH_DEBOUNCE_CYCLES)
    ) u_tresh_control (
        .clk(vga_clk), .rstn(control_resetn),
        .higher_up_tresh(higher_up_tresh), .lower_down_tresh(lower_down_tresh),
        .tresh_value(tresh_val)
    );

    frame_processor #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .ROI_SIZE(ROI_SIZE), .OUTPUT_SIZE(OUTPUT_SIZE), .SAMPLE_OFFSET(SAMPLE_OFFSET)
    ) u_processor (
        .clk(vga_clk), .sys_rstn(sys_rstn), .sw_mode(sw_mode), .tresh_val(tresh_val),
        .fifo_dout(raw_pixel), .fifo_empty(raw_empty),
        .fifo_valid(raw_valid && prefilled && !display_fault),
        .ready_to_fifo(raw_ready),
        .ready_from_downstream(display_ready && !display_fault),
        .dout(display_pixel), .valid_out(display_valid),
        .pixel_x_out(), .pixel_y_out(), .frame_start_out(), .frame_end_out(), .frame_id_out(),
        .cnn_dout(cnn_dout), .cnn_valid_out(cnn_valid_out), .processing_error(processing_error)
    );

    // Only the reader fault crosses a clock boundary. Processing errors are
    // already synchronous to vga_clk. Neither fault stalls HSYNC/VSYNC timing.
    always @(posedge vga_clk) begin
        if (!display_resetn) begin
            prefilled <= 0;
            fault_meta <= 0;
            fault_sync <= 0;
        end else begin
            fault_meta <= fault;
            fault_sync <= fault_meta;
            if (raw_level >= DISPLAY_PREFILL)
                prefilled <= 1;
        end
    end

    vga_rgb444 #(
        .H_VISIBLE(FRAME_WIDTH), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_VISIBLE(FRAME_HEIGHT), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) u_vga (
        .vga_clk(vga_clk), .sys_rstn(sys_rstn), .din(display_pixel),
        .valid_in(display_valid && prefilled && !display_fault),
        .ready_to_upstream(display_ready),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b), .vga_hs(vga_hs), .vga_vs(vga_vs),
        .vga_vblank_start(), .vga_frame_start(), .underflow(underflow)
    );

    // Allow the line-delay/median pipeline to re-prime between video frames.
    // The default 640x480 timing supplies 36160 clocks here (minimum 672).
    localparam integer H_TOTAL = FRAME_WIDTH+H_FRONT+H_SYNC+H_BACK;
    localparam integer FRAME_BLANK_CYCLES = (V_FRONT+V_SYNC+V_BACK)*H_TOTAL+
        H_FRONT+H_SYNC+H_BACK;
    initial begin
        if (FRAME_BLANK_CYCLES < FRAME_WIDTH+32)
            $fatal(1, "Insufficient vertical blanking for the single-FIFO processing pipeline");
        if (ADDR_WIDTH < 21 || AXI_ID_WIDTH < 1 || AXI_DATA_WIDTH < 16 ||
            AXI_DATA_WIDTH > 1024 || AXI_DATA_WIDTH % 16 != 0 ||
            (AXI_DATA_WIDTH & (AXI_DATA_WIDTH-1)) != 0)
            $fatal(1, "Invalid AXI widths for the RGB444 double-buffer layout");
        if (FRAME_WIDTH < 1 || FRAME_HEIGHT < 1 || FRAME_BYTES > 614400 ||
            FRAME_WIDTH+H_FRONT+H_SYNC+H_BACK > 1024 ||
            FRAME_HEIGHT+V_FRONT+V_SYNC+V_BACK > 1024)
            $fatal(1, "Invalid frame dimensions for VGA or the fixed DDR buffer addresses");
        if (BURST_BEAT < 1 || BURST_BEAT > 256 || BURST_BYTES > 4096 ||
            4096 % BURST_BYTES != 0 || FRAME_BYTES % BURST_BYTES != 0)
            $fatal(1, "AXI bursts must divide the frame and 4 KiB boundaries exactly");
        if (FIFO_DEPTH < 16 || (FIFO_DEPTH & (FIFO_DEPTH-1)) != 0 ||
            FIFO_DEPTH < AXI_DATA_WIDTH/16+3 || DISPLAY_PREFILL < 1 ||
            DISPLAY_PREFILL >= FIFO_DEPTH-4 || DISPLAY_PREFILL > FRAME_WIDTH*FRAME_HEIGHT-2)
            $fatal(1, "Invalid FIFO depth or display prefill");
    end
endmodule

`default_nettype wire
