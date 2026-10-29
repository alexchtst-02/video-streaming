`timescale 1ns / 1ps

module attributed_async_fifo #(
    parameter integer WORD_WIDTH = 16,
    parameter integer DEPTH = 2048,
    parameter integer UNPAKCER_DATA_NUM = 8,
    parameter integer PAKCER_DATA_NUM = 1,
    parameter [0:0] ALOWED_SKIP_VALUE = 1
)(
    input wire sys_rstn,
    
    input wire wr_clk,
    input wire rd_clk,
    
    input wire downstream_ready,
    input wire valid_in,
    input wire [WORD_WIDTH*UNPAKCER_DATA_NUM-1:0] din,
    
    output wire ready_to_upstream,
    
    output wire valid_out,
    output wire [WORD_WIDTH*PAKCER_DATA_NUM-1:0] dout,
    
    output wire full,
    output wire [$clog2(DEPTH):0] rd_level,
    output wire [$clog2(DEPTH):0] wr_level,
    output wire empty
);
    // conservative margin as 2 is my favorite number
    localparam integer RESERVED_WORDS = UNPAKCER_DATA_NUM + 2;

    // Reserve capacity for data still in the unpacker pipeline
    wire fifo_can_accept = (wr_level <= DEPTH - RESERVED_WORDS);
    
    wire trig_upstream_unpacker;
    wire unpacker_can_accept = trig_upstream_unpacker && fifo_can_accept;
    
    // Report actual acceptance to the camera-side frame checker. The camera
    // cannot be stalled, so a low ready makes that frame invalid.
    assign ready_to_upstream = unpacker_can_accept;
    
    // Never forward data if insufficient FIFO capacity
    wire valid_in_unpacker = valid_in && unpacker_can_accept;
    
    wire [WORD_WIDTH*UNPAKCER_DATA_NUM-1:0] din_unpacker = din;
    
    wire fifo_wr_en_unpacker;
    wire [WORD_WIDTH-1:0] fifo_wr_in_unpacker;
    
    fifo_unpacker #(
        .WORD_WIDTH(WORD_WIDTH),
        .DATA_NUM(UNPAKCER_DATA_NUM)
    ) uut_unpacker (
        .clk(wr_clk),
        .sys_rstn(sys_rstn),
        
        .valid_in(valid_in_unpacker),
        .din(din_unpacker),
        
        .trig_upstream(trig_upstream_unpacker),
        .fifo_wr_en(fifo_wr_en_unpacker),
        .fifo_wr_in(fifo_wr_in_unpacker)
    );
    
    wire fifo_rd_en_packer;
    
    wire wr_en_async_fifo = fifo_wr_en_unpacker;
    wire [WORD_WIDTH-1:0] wr_in_async_fifo = fifo_wr_in_unpacker;
    wire rd_en_async_fifo;
    assign rd_en_async_fifo = fifo_rd_en_packer;
    wire [WORD_WIDTH-1:0] rd_out_async_fifo;
    
    async_fifo #(
        .WORD_WIDTH(WORD_WIDTH),
        .DEPTH(DEPTH)
    ) uut_async_fifo (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        
        .sys_rstn(sys_rstn),
        
        .wr_en(wr_en_async_fifo),
        .wr_in(wr_in_async_fifo),
        
        .rd_en(rd_en_async_fifo),
        .rd_out(rd_out_async_fifo),
        
        .full(full),
        .rd_level(rd_level),
        .wr_level(wr_level),
        .empty(empty)
    );
    
    wire downstream_ready_packer;
    wire fifo_rd_valid_packer;
    assign fifo_rd_valid_packer = (rd_level >= PAKCER_DATA_NUM) && !empty;
    wire [WORD_WIDTH-1:0] fifo_rd_in_packer;
    assign fifo_rd_in_packer = rd_out_async_fifo;
    
    wire valid_out_packer;
    wire [WORD_WIDTH*PAKCER_DATA_NUM-1:0] dout_packer;
    
    fifo_packer #(
        .WORD_WIDTH(WORD_WIDTH),
        .DATA_NUM(PAKCER_DATA_NUM)
    ) uut_packer (
        .clk(rd_clk),
        .sys_rstn(sys_rstn),
        
        .downstream_ready(downstream_ready_packer),
        
        .fifo_rd_valid(fifo_rd_valid_packer),
        .fifo_rd_in(fifo_rd_in_packer),
        
        .fifo_rd_en(fifo_rd_en_packer),
        .valid_out(valid_out_packer),
        .dout(dout_packer)
    );
    
    assign valid_out = valid_out_packer;
    assign dout = dout_packer;
    
    assign downstream_ready_packer = downstream_ready;

endmodule
