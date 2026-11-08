`timescale 1ns / 1ps

// AXI test: axi_write writes two bursts into a simple memory model, then
// axi_read reads them back. Every read beat must equal the written beat.
// Result: tb_axi.txt
module tb_axi;

    localparam integer ADDR_WIDTH = 32;
    localparam integer DATA_WIDTH = 128;
    localparam integer BURST_BEAT = 16;

    reg aclk, aresetn;
    reg init_calib_complete;

    // ===================== AXI WRITE MASTER =====================
    reg wr_start;
    reg [ADDR_WIDTH-1:0] wr_base_addr;
    wire wr_busy, wr_done, wr_error;
    wire [3:0] wr_error_code;

    wire fifo_valid = 1'b1;
    reg [31:0] wr_counter;
    wire [DATA_WIDTH-1:0] fifo_dout = {4{wr_counter}};
    wire ready_to_upstream;

    wire [3:0] awid;
    wire [ADDR_WIDTH-1:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awlock;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire [3:0] awqos;
    wire awvalid;
    wire awready = 1'b1;
    wire [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH/8-1:0] wstrb;
    wire wlast, wvalid;
    wire wready = 1'b1;
    reg bvalid;
    wire bready;

    axi_write #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ID_WIDTH(4),
        .BURST_BEAT(BURST_BEAT)
    ) uut_axi_write (
        .aclk(aclk), .aresetn(aresetn), .init_calib_complete(init_calib_complete),

        .start(wr_start), .base_addr(wr_base_addr),
        .busy(wr_busy), .done(wr_done), .error(wr_error), .error_code(wr_error_code),

        .fifo_valid(fifo_valid), .fifo_dout(fifo_dout), .ready_to_upstream(ready_to_upstream),

        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache),
        .m_axi_awprot(awprot), .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),

        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),

        .m_axi_bid(4'd0), .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // ===================== AXI READ MASTER =====================
    reg rd_start;
    reg [ADDR_WIDTH-1:0] rd_base_addr;
    wire rd_busy, rd_done, rd_error;
    wire [3:0] rd_error_code;
    wire [DATA_WIDTH-1:0] fifo_din;
    wire fifo_din_valid;

    wire [3:0] arid;
    wire [ADDR_WIDTH-1:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire [3:0] arqos;
    wire arvalid;
    wire arready = 1'b1;
    reg rvalid;
    wire rlast;
    wire [DATA_WIDTH-1:0] rdata;
    wire rready;

    axi_read #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(DATA_WIDTH),
        .AXI_ID_WIDTH(4),
        .BURST_BEAT(BURST_BEAT)
    ) uut_axi_read (
        .aclk(aclk), .aresetn(aresetn), .init_calib_complete(init_calib_complete),

        .start(rd_start), .base_addr(rd_base_addr),
        .busy(rd_busy), .done(rd_done), .error(rd_error), .error_code(rd_error_code),

        .fifo_din(fifo_din), .fifo_valid(fifo_din_valid), .ready_from_fifo(1'b1),

        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),

        .m_axi_rid(4'd0), .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    // ===================== MEMORY MODEL (AXI SLAVE) =====================
    reg [DATA_WIDTH-1:0] mem [0:255];
    reg [ADDR_WIDTH-1:0] waddr, raddr;
    reg [7:0] wcnt, rcnt;

    // one beat = 16 bytes
    assign rdata = mem[raddr/16 + rcnt];
    assign rlast = rvalid && (rcnt == BURST_BEAT - 1);

    always @(posedge aclk) begin
        if (!aresetn) begin
            bvalid <= 0;
            rvalid <= 0;
            wcnt <= 0;
            rcnt <= 0;
        end else begin
            // write address + data
            if (awvalid && awready) begin
                waddr <= awaddr;
                wcnt <= 0;
            end
            if (wvalid && wready) begin
                mem[waddr/16 + wcnt] <= wdata;
                wcnt <= wcnt + 1;
                if (wlast) bvalid <= 1;
            end
            if (bvalid && bready) bvalid <= 0;

            // read address + data
            if (arvalid && arready) begin
                raddr <= araddr;
                rcnt <= 0;
                rvalid <= 1;
            end
            if (rvalid && rready) begin
                rcnt <= rcnt + 1;
                if (rlast) rvalid <= 0;
            end
        end
    end

    // write data counter: next value after every accepted beat
    always @(posedge aclk) begin
        if (!aresetn)
            wr_counter <= 32'h1000;
        else if (ready_to_upstream && fifo_valid)
            wr_counter <= wr_counter + 1;
    end

    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // ===================== CHECKER =====================
    integer file_axi;
    integer read_beat, errors;
    reg [31:0] expected;

    always @(posedge aclk) begin
        if (wvalid && wready)
            $fdisplay(file_axi, "WRITE addr=%h beat=%0d data=%h last=%b", waddr, wcnt, wdata, wlast);

        if (fifo_din_valid) begin
            expected = 32'h1000 + read_beat;
            if (fifo_din !== {4{expected}}) begin
                errors = errors + 1;
                $fdisplay(file_axi, "READ  beat=%0d data=%h expected=%h FAIL", read_beat, fifo_din, {4{expected}});
            end else begin
                $fdisplay(file_axi, "READ  beat=%0d data=%h PASS", read_beat, fifo_din);
            end
            read_beat = read_beat + 1;
        end
    end

    task write_burst(input [ADDR_WIDTH-1:0] addr);
        begin
            @(negedge aclk);
            wr_base_addr = addr;
            wr_start = 1;
            @(negedge aclk);
            wr_start = 0;
            @(posedge wr_done or posedge wr_error);
            $fdisplay(file_axi, "WRITE burst addr=%h done=%b error=%b code=%0d", addr, wr_done, wr_error, wr_error_code);
            if (wr_error) errors = errors + 1;
        end
    endtask

    task read_burst(input [ADDR_WIDTH-1:0] addr);
        begin
            @(negedge aclk);
            rd_base_addr = addr;
            rd_start = 1;
            @(negedge aclk);
            rd_start = 0;
            @(posedge rd_done or posedge rd_error);
            $fdisplay(file_axi, "READ  burst addr=%h done=%b error=%b code=%0d", addr, rd_done, rd_error, rd_error_code);
            if (rd_error) errors = errors + 1;
        end
    endtask

    initial begin
        file_axi = $fopen("tb_axi.txt", "w");
        read_beat = 0;
        errors = 0;

        aresetn = 0;
        init_calib_complete = 0;
        wr_start = 0; wr_base_addr = 0;
        rd_start = 0; rd_base_addr = 0;
        #20

        aresetn = 1;
        init_calib_complete = 1;
        #20

        // two bursts of 16 beats x 16 bytes = 256 bytes each
        write_burst(32'h0000_0000);
        write_burst(32'h0000_0100);

        read_burst(32'h0000_0000);
        read_burst(32'h0000_0100);
        #50

        if (read_beat != 2*BURST_BEAT) errors = errors + 1;
        $fdisplay(file_axi, "beats read=%0d expected=%0d", read_beat, 2*BURST_BEAT);
        $fdisplay(file_axi, "RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $display("tb_axi RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $fclose(file_axi);
        $finish;
    end

endmodule
