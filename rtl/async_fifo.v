`timescale 1ns / 1ps

module async_fifo #(
    parameter integer WORD_WIDTH = 16,
    parameter integer DEPTH = 2048
)(
    input wire wr_clk,
    input wire rd_clk,
    
    input wire sys_rstn,
    
    input wire wr_en,
    input wire [WORD_WIDTH-1:0] wr_in,
    
    input wire rd_en,
    output wire [WORD_WIDTH-1:0] rd_out,
    
    output wire full,
    output wire [$clog2(DEPTH):0] rd_level,
    output wire [$clog2(DEPTH):0] wr_level,
    output wire empty
);
    localparam integer PTR_WIDTH = $clog2(DEPTH);
    
    wire resetn_read;
    resetn_sync uut_resetn_read (
        .clk(rd_clk),
        .arstn(sys_rstn),
        .srstn(resetn_read)
    );
    
    wire resetn_write;
    resetn_sync uut_resetn_write (
        .clk(wr_clk),
        .arstn(sys_rstn),
        .srstn(resetn_write)
    );
    
    (* ram_style = "block" *)
    reg [WORD_WIDTH-1:0] mem [0:DEPTH-1];

    // Binary pointers
    reg [PTR_WIDTH:0] wr_bin_ptr;
    reg [PTR_WIDTH:0] rd_bin_ptr;
    
    // Gray pointers
    reg [PTR_WIDTH:0] wr_gray_ptr;
    reg [PTR_WIDTH:0] rd_gray_ptr;
    
    wire wr_fire = wr_en && !full && resetn_write;
    
    wire [PTR_WIDTH:0] wr_bin_next;
    wire [PTR_WIDTH:0] wr_gray_next;
    
    assign wr_bin_next = wr_bin_ptr + wr_fire;
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    
    // The binary pointer drives the BRAM address. A synchronous reset keeps
    // its address inputs timed during reset as required by RAMB36 inference.
    always @(posedge wr_clk) begin
        if (!resetn_write) begin
            wr_bin_ptr <= 0;
        end
        else begin
            wr_bin_ptr <= wr_bin_next;
        end
    end

    always @(posedge wr_clk or negedge resetn_write) begin
        if (!resetn_write)
            wr_gray_ptr <= 0;
        else
            wr_gray_ptr <= wr_gray_next;
    end
    
    always @(posedge wr_clk) begin
        if (wr_fire) begin
            mem[wr_bin_ptr[PTR_WIDTH-1:0]] <= wr_in;
        end
    end
    
    wire rd_fire = rd_en && !empty && resetn_read;
    
    wire [PTR_WIDTH:0] rd_bin_next;
    wire [PTR_WIDTH:0] rd_gray_next;
    
    assign rd_bin_next = rd_bin_ptr + rd_fire;
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;
    
    always @(posedge rd_clk) begin
        if (!resetn_read) begin
            rd_bin_ptr <= 0;
        end
        else begin
            rd_bin_ptr <= rd_bin_next;
        end
    end

    always @(posedge rd_clk or negedge resetn_read) begin
        if (!resetn_read)
            rd_gray_ptr <= 0;
        else
            rd_gray_ptr <= rd_gray_next;
    end
    
    reg [WORD_WIDTH-1:0] rd_data_reg;
    assign rd_out = rd_data_reg;
    
    always @(posedge rd_clk) begin
        if (rd_fire) begin
            rd_data_reg <= mem[rd_bin_ptr[PTR_WIDTH-1:0]];
        end
    end
    
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_WIDTH:0] rd_gray_sync1;
    
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_WIDTH:0] rd_gray_sync2;
    
    always @(posedge wr_clk or negedge resetn_write) begin
        if (!resetn_write) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end
        else begin
            rd_gray_sync1 <= rd_gray_ptr;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end
    
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_WIDTH:0] wr_gray_sync1;
    
    (* ASYNC_REG = "TRUE" *)
    reg [PTR_WIDTH:0] wr_gray_sync2;
    
    always @(posedge rd_clk or negedge resetn_read) begin
        if (!resetn_read) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end
        else begin
            wr_gray_sync1 <= wr_gray_ptr;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end
    
    wire full_next;
    assign full_next = (wr_gray_next == { ~rd_gray_sync2[PTR_WIDTH:PTR_WIDTH-1], rd_gray_sync2[PTR_WIDTH-2:0] });
    
    reg full_reg;

    always @(posedge wr_clk or negedge resetn_write) begin
        if (!resetn_write)
            full_reg <= 1'b0;
        else
            full_reg <= full_next;
    end
    
    assign full = full_reg;
    
    wire empty_next;
    reg empty_reg;
    
    assign empty_next = (rd_gray_next == wr_gray_sync2);
    
    always @(posedge rd_clk or negedge resetn_read) begin
        if (!resetn_read)
            empty_reg <= 1'b1;
        else
            empty_reg <= empty_next;
    end
    
    assign empty = empty_reg;
    
    // for level read and write, we need it
    // afraid of 12 bit xor 
    // (cross flip flop, pray vivado mapped it into into LUT FPGA Correctly)
    function [PTR_WIDTH:0] gray_to_bin;
        input [PTR_WIDTH:0] gray;
        integer i;
        begin
            gray_to_bin[PTR_WIDTH] = gray[PTR_WIDTH];
    
            for (i = PTR_WIDTH-1; i >= 0; i = i-1) begin
                gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
            end
        end
    endfunction
    
    wire [PTR_WIDTH:0] rd_bin_sync;
    wire [PTR_WIDTH:0] wr_bin_sync;
    
    assign rd_bin_sync = gray_to_bin(rd_gray_sync2);
    assign wr_bin_sync = gray_to_bin(wr_gray_sync2);
    
    assign wr_level = wr_bin_ptr - rd_bin_sync;
    assign rd_level = wr_bin_sync - rd_bin_ptr;

endmodule
