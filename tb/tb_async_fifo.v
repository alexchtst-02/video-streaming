`timescale 1ns / 1ps

// Async FIFO test, write clock 100 MHz and read clock 25 MHz:
//   1. clock domain crossing: words come out in the same order
//   2. backpressure: no read, the writer must stop at full (DEPTH words)
//   3. reset: after reset the FIFO is empty again
// Result: tb_async_fifo.txt
module tb_async_fifo;

    localparam integer WORD_WIDTH = 16;
    localparam integer DEPTH = 16;

    reg wr_clk, rd_clk;
    reg sys_rstn;

    reg wr_en;
    reg [WORD_WIDTH-1:0] wr_in;
    reg rd_en;
    wire [WORD_WIDTH-1:0] rd_out;
    wire full, empty;
    wire [$clog2(DEPTH):0] rd_level, wr_level;

    async_fifo #(
        .WORD_WIDTH(WORD_WIDTH),
        .DEPTH(DEPTH)
    ) uut_async_fifo (
        .wr_clk(wr_clk), .rd_clk(rd_clk),
        .sys_rstn(sys_rstn),

        .wr_en(wr_en), .wr_in(wr_in),
        .rd_en(rd_en), .rd_out(rd_out),

        .full(full), .rd_level(rd_level), .wr_level(wr_level), .empty(empty)
    );

    initial begin
        wr_clk = 0;
        forever #5 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 0;
        forever #20 rd_clk = ~rd_clk;
    end

    integer file_fifo;
    integer i, accepted, errors;
    reg [WORD_WIDTH-1:0] value, expected;

    // write one word, returns 1 in accepted if the FIFO was not full
    task write_word(input [WORD_WIDTH-1:0] data);
        begin
            @(negedge wr_clk);
            wr_en = 1;
            wr_in = data;
            if (!full) accepted = accepted + 1;
            @(posedge wr_clk); #1
            wr_en = 0;
        end
    endtask

    // read one word, waits until the FIFO is not empty
    task read_word(output [WORD_WIDTH-1:0] data);
        begin
            @(negedge rd_clk);
            while (empty) @(negedge rd_clk);
            rd_en = 1;
            @(posedge rd_clk); #1
            rd_en = 0;
            data = rd_out;
        end
    endtask

    initial begin
        file_fifo = $fopen("tb_async_fifo.txt", "w");
        errors = 0;
        sys_rstn = 0;
        wr_en = 0; wr_in = 0;
        rd_en = 0;
        #100

        sys_rstn = 1;
        #200

        // ===================== 1. CDC ORDER =====================
        $fdisplay(file_fifo, "1. CDC: write 10 words at 100 MHz, read at 25 MHz");
        accepted = 0;
        for (i = 0; i < 10; i = i + 1)
            write_word(16'hA000 + i);

        for (i = 0; i < 10; i = i + 1) begin
            read_word(value);
            expected = 16'hA000 + i;
            if (value !== expected) errors = errors + 1;
            $fdisplay(file_fifo, "   read %0d = %h expected %h %s", i, value, expected,
                      value === expected ? "PASS" : "FAIL");
        end
        #200
        $fdisplay(file_fifo, "   empty after reading all = %b %s", empty, empty ? "PASS" : "FAIL");
        if (!empty) errors = errors + 1;

        // ===================== 2. BACKPRESSURE =====================
        $fdisplay(file_fifo, "2. Backpressure: write 20 words without reading, DEPTH=%0d", DEPTH);
        accepted = 0;
        for (i = 0; i < 20; i = i + 1)
            write_word(16'hB000 + i);
        $fdisplay(file_fifo, "   accepted = %0d expected %0d %s", accepted, DEPTH,
                  accepted == DEPTH ? "PASS" : "FAIL");
        $fdisplay(file_fifo, "   full = %b %s", full, full ? "PASS" : "FAIL");
        if (accepted != DEPTH || !full) errors = errors + 1;

        for (i = 0; i < DEPTH; i = i + 1) begin
            read_word(value);
            expected = 16'hB000 + i;
            if (value !== expected) errors = errors + 1;
            $fdisplay(file_fifo, "   read %0d = %h expected %h %s", i, value, expected,
                      value === expected ? "PASS" : "FAIL");
        end
        #200
        $fdisplay(file_fifo, "   full after reading = %b, empty = %b %s", full, empty,
                  !full && empty ? "PASS" : "FAIL");
        if (full || !empty) errors = errors + 1;

        // ===================== 3. RESET =====================
        $fdisplay(file_fifo, "3. Reset: write 5 words, then reset");
        for (i = 0; i < 5; i = i + 1)
            write_word(16'hC000 + i);
        #200
        $fdisplay(file_fifo, "   before reset: empty = %b rd_level = %0d", empty, rd_level);
        sys_rstn = 0;
        #100
        sys_rstn = 1;
        #200
        $fdisplay(file_fifo, "   after reset:  empty = %b full = %b rd_level = %0d wr_level = %0d %s",
                  empty, full, rd_level, wr_level,
                  empty && !full && rd_level == 0 && wr_level == 0 ? "PASS" : "FAIL");
        if (!empty || full || rd_level != 0 || wr_level != 0) errors = errors + 1;

        // FIFO still works after reset
        write_word(16'hD000);
        read_word(value);
        $fdisplay(file_fifo, "   write/read after reset = %h expected d000 %s", value,
                  value === 16'hD000 ? "PASS" : "FAIL");
        if (value !== 16'hD000) errors = errors + 1;

        $fdisplay(file_fifo, "RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $display("tb_async_fifo RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $fclose(file_fifo);
        $finish;
    end

endmodule
