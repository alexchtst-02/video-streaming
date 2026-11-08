`timescale 1ns / 1ps

module axi_read #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,
    
    input wire start,
    input wire [ADDR_WIDTH-1:0] base_addr,
    
    output wire busy,
    output reg done,
    output reg error,
    output reg [3:0] error_code,
    output wire [AXI_DATA_WIDTH-1:0] fifo_din,
    output wire fifo_valid,
    
    input wire ready_from_fifo,
    
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
    
    input wire [AXI_ID_WIDTH-1:0] m_axi_rid,
    input wire [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    localparam integer BYTES_PER_BEAT = AXI_DATA_WIDTH / 8;
    localparam [7:0] ARLEN_CONST = BURST_BEAT - 1;
    localparam [2:0] ARSIZE_CONST = $clog2(BYTES_PER_BEAT);
    localparam integer COUNT_WIDTH = $clog2(BURST_BEAT + 1);

    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] SEND_AR = 3'd1;
    localparam [2:0] RECEIVE_R = 3'd2;
    localparam [2:0] DRAIN = 3'd3;
    localparam [2:0] FAULT = 3'd4;

    localparam [3:0] ERR_NONE = 4'd0;
    localparam [3:0] ERR_EXOKAY = 4'd1;
    localparam [3:0] ERR_SLVERR = 4'd2;
    localparam [3:0] ERR_DECERR = 4'd3;
    localparam [3:0] ERR_RID = 4'd4;
    localparam [3:0] ERR_RLAST = 4'd5;

    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [COUNT_WIDTH-1:0] r_beat_count;

    assign m_axi_arid = {AXI_ID_WIDTH{1'b0}};
    assign m_axi_araddr = addr_reg;
    assign m_axi_arlen = ARLEN_CONST;
    assign m_axi_arsize = ARSIZE_CONST;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arqos = 4'b0000;

    assign m_axi_arvalid = (state == SEND_AR);
    assign m_axi_rready = ((state == RECEIVE_R) && ready_from_fifo) || state == DRAIN;
    assign fifo_din = m_axi_rdata;

    wire ar_fire = m_axi_arvalid && m_axi_arready;
    wire r_fire = m_axi_rvalid && m_axi_rready;
    wire expected_last = (r_beat_count == BURST_BEAT - 1);

    wire beat_good = m_axi_rid == {AXI_ID_WIDTH{1'b0}} &&
                     m_axi_rresp == 2'b00 && m_axi_rlast == expected_last;
    assign fifo_valid = r_fire && state == RECEIVE_R && beat_good;
    assign busy = (state != IDLE);

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            addr_reg <= {ADDR_WIDTH{1'b0}};
            r_beat_count <= {COUNT_WIDTH{1'b0}};
            done <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
        end else begin
            done <= 1'b0;
            error <= 1'b0;
            case (state)
                IDLE: begin
                    if (start && init_calib_complete) begin
                        addr_reg <= base_addr;
                        r_beat_count <= {COUNT_WIDTH{1'b0}};
                        error_code <= ERR_NONE;
                        state <= SEND_AR;
                    end
                end

                SEND_AR: begin
                    if (ar_fire) state <= RECEIVE_R;
                end

                RECEIVE_R: begin
                    if (r_fire) begin
                        if (m_axi_rid != {AXI_ID_WIDTH{1'b0}}) begin
                            error <= 1'b1;
                            error_code <= ERR_RID;
                            r_beat_count <= r_beat_count + 1'b1;
                            state <= expected_last || m_axi_rlast ? FAULT : DRAIN;
                        end else if (m_axi_rresp != 2'b00) begin
                            error <= 1'b1;
                            error_code <= {2'b00, m_axi_rresp};
                            r_beat_count <= r_beat_count + 1'b1;
                            state <= expected_last || m_axi_rlast ? FAULT : DRAIN;
                        end else if (m_axi_rlast != expected_last) begin
                            error <= 1'b1;
                            error_code <= ERR_RLAST;
                            r_beat_count <= r_beat_count + 1'b1;
                            state <= expected_last || m_axi_rlast ? FAULT : DRAIN;
                        end else if (expected_last) begin
                            done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            r_beat_count <= r_beat_count + 1'b1;
                        end
                    end
                end

                DRAIN: begin
                    if (r_fire) begin
                        if (expected_last || m_axi_rlast)
                            state <= FAULT;
                        else
                            r_beat_count <= r_beat_count + 1'b1;
                    end
                end

                FAULT: begin
                    state <= FAULT;
                end
                default: state <= FAULT;
            endcase
        end
    end

    initial begin
        if (AXI_DATA_WIDTH < 8 || AXI_DATA_WIDTH % 8 != 0 ||
            (BYTES_PER_BEAT & (BYTES_PER_BEAT-1)) != 0 ||
            BURST_BEAT < 1 || BURST_BEAT > 256 || BYTES_PER_BEAT*BURST_BEAT > 4096)
            $fatal(1, "Invalid AXI read burst parameters");
    end
endmodule
