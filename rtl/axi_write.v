`timescale 1ns / 1ps

module axi_write #(
    parameter integer ADDR_WIDTH = 28,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,
    
    // frame_executor interface
    input wire start,
    input wire [ADDR_WIDTH-1:0] base_addr,
    
    output wire busy,
    output reg done,
    output reg error,
    output reg [3:0] error_code,
    
    // FIFO upstream interface
    input  wire fifo_valid,
    input  wire [AXI_DATA_WIDTH-1:0] fifo_dout,
    output wire ready_to_upstream,
    
    // axi write address chanel
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
    
    // axi write data chanel
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    // valid to write data in byte
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    
    // axi write response chanel
    input wire [AXI_ID_WIDTH-1:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);

    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] SEND_AW = 3'd1;
    localparam [2:0] WRITE_W = 3'd2;
    localparam [2:0] WAIT_B = 3'd3;
    localparam [2:0] FAULT = 3'd4;
    
    
    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [8:0] w_beat_count;
    
    // 2. Error encoding
    localparam [3:0] ERR_NONE = 4'd0;
    localparam [3:0] ERR_EXOKAY = 4'd1;
    localparam [3:0] ERR_SLVERR = 4'd2;
    localparam [3:0] ERR_DECERR = 4'd3;
    localparam [3:0] ERR_BID = 4'd4;
    
    // AXI WRITE ADDRESS CHANNEL
    
    localparam integer BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    
    assign m_axi_awid = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_awaddr = addr_reg;
    assign m_axi_awlen = BURST_BEAT - 1;
    assign m_axi_awsize = $clog2(BYTES_PER_BEAT);
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awqos = 4'b0000;
    
    // AXI WRITE CHANNEL
    
    assign m_axi_wdata = fifo_dout;
    assign m_axi_wstrb = {(AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_wvalid = (state == WRITE_W) && fifo_valid;
    assign ready_to_upstream = (state == WRITE_W) && m_axi_wready;
    assign m_axi_wlast =
        m_axi_wvalid
            && (w_beat_count == BURST_BEAT - 1);

    wire w_fire = m_axi_wvalid && m_axi_wready;
    
    assign busy = (state != IDLE);
    assign m_axi_awvalid = (state == SEND_AW);
    wire aw_fire = m_axi_awvalid && m_axi_awready;
    
    assign m_axi_bready = (state == WAIT_B);
    wire b_fire = m_axi_bvalid && m_axi_bready;
    
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            addr_reg <= {ADDR_WIDTH{1'b0}};
            w_beat_count <= 9'd0;
    
            done <= 1'b0;
            error <= 1'b0;
            error_code <= 4'd0;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
    
            case (state)
                IDLE: begin
                    if (start && init_calib_complete) begin
                        addr_reg <= base_addr;
                        w_beat_count <= 9'd0;
                        error_code <= 4'd0;
    
                        state <= SEND_AW;
                    end
                end
    
                SEND_AW: begin
                    if (aw_fire) begin
                        state <= WRITE_W;
                    end
                end
    
                WRITE_W: begin
                    if (w_fire) begin
                        if (w_beat_count == BURST_BEAT - 1) begin
                            state <= WAIT_B;
                        end else begin
                            w_beat_count <= w_beat_count + 1'b1;
                        end
                    end
                end

                WAIT_B: begin
                    if (b_fire) begin
                        // critical error
                        if (m_axi_bid != {AXI_ID_WIDTH{1'b0}}) begin
                            error <= 1'b1;
                            error_code <= ERR_BID;
                            state <= FAULT;
                        end else begin
                            error_code <= {2'b00, m_axi_bresp};
                
                            if (m_axi_bresp == 2'b00)
                                done <= 1'b1;
                            else
                                error <= 1'b1;
                
                            state <= IDLE;
                        end
                    end
                end
                
                // deadlock hehe
                FAULT: begin
                    state <= FAULT;
                end
    
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
endmodule
