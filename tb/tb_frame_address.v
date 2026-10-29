`timescale 1ns / 1ps

// Frame address test: write_frame_exec and read_frame_exec must split one
// 640x480 RGB444 frame (614400 bytes) into 2400 bursts of 256 bytes,
// starting at BASE_0 = 0x00000 or BASE_1 = 0x96000.
// A fake AXI master finishes every burst after a few cycles.
// Result: tb_frame_address.txt (every burst address + summary)
module tb_frame_address;

    localparam integer ADDR_WIDTH = 32;
    localparam integer TOTAL_BURST = 640*480*2/256;
    localparam integer ADDR_INCR = 256;

    reg aclk, aresetn;
    reg init_calib_complete;

    // ===================== WRITE FRAME EXECUTOR =====================
    reg [1:0] wr_cmd;
    reg wr_axi_busy, wr_axi_done;
    wire wr_start_axi;
    wire [ADDR_WIDTH-1:0] wr_base_addr;
    wire wr_trig, wr_done_one_frame, wr_frame_is_valid;

    write_frame_exec #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(128),
        .AXI_ID_WIDTH(4),
        .BURST_BEAT(16)
    ) uut_write_frame_exec (
        .aclk(aclk), .aresetn(aresetn), .init_calib_complete(init_calib_complete),
        .frame_executor_cmd(wr_cmd),

        .axi_busy(wr_axi_busy), .axi_done(wr_axi_done),
        .axi_error(1'b0), .axi_error_code(4'd0),

        // camera always reports a good frame
        .capture_frame_valid(1'b1), .capture_frame_error(1'b0),

        .start_axi(wr_start_axi), .base_addr_axi(wr_base_addr),
        .send_trig_safe_pixel_frame(wr_trig),
        .done_one_frame(wr_done_one_frame), .frame_is_valid(wr_frame_is_valid)
    );

    // ===================== READ FRAME EXECUTOR =====================
    reg [1:0] rd_cmd;
    reg rd_axi_busy, rd_axi_done;
    wire rd_start_axi;
    wire [ADDR_WIDTH-1:0] rd_base_addr;
    wire rd_done_one_frame, rd_frame_is_valid, rd_busy, rd_fault;
    wire [3:0] rd_fault_code;

    read_frame_exec #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(128),
        .AXI_ID_WIDTH(4),
        .BURST_BEAT(16)
    ) uut_read_frame_exec (
        .aclk(aclk), .aresetn(aresetn), .init_calib_complete(init_calib_complete),
        .frame_executor_cmd(rd_cmd),

        .axi_busy(rd_axi_busy), .axi_done(rd_axi_done),
        .axi_error(1'b0), .axi_error_code(4'd0),

        .start_axi(rd_start_axi), .base_addr_axi(rd_base_addr),
        .done_one_frame(rd_done_one_frame), .frame_is_valid(rd_frame_is_valid),
        .busy(rd_busy), .fault(rd_fault), .fault_code(rd_fault_code)
    );

    // ===================== FAKE AXI MASTERS =====================
    // busy for 4 cycles after start, then a one-cycle done pulse
    reg [2:0] wr_cnt, rd_cnt;
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_axi_busy <= 0; wr_axi_done <= 0; wr_cnt <= 0;
            rd_axi_busy <= 0; rd_axi_done <= 0; rd_cnt <= 0;
        end else begin
            wr_axi_done <= 0;
            if (wr_start_axi) begin
                wr_axi_busy <= 1; wr_cnt <= 3;
            end else if (wr_axi_busy) begin
                if (wr_cnt == 0) begin wr_axi_busy <= 0; wr_axi_done <= 1; end
                else wr_cnt <= wr_cnt - 1;
            end

            rd_axi_done <= 0;
            if (rd_start_axi) begin
                rd_axi_busy <= 1; rd_cnt <= 3;
            end else if (rd_axi_busy) begin
                if (rd_cnt == 0) begin rd_axi_busy <= 0; rd_axi_done <= 1; end
                else rd_cnt <= rd_cnt - 1;
            end
        end
    end

    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // ===================== CHECKER =====================
    integer file_addr;
    integer errors;
    integer wr_bursts, rd_bursts;
    reg [ADDR_WIDTH-1:0] wr_expected, rd_expected;

    always @(posedge aclk) begin
        if (wr_start_axi) begin
            if (wr_base_addr !== wr_expected) errors = errors + 1;
            $fdisplay(file_addr, "WRITE burst %0d addr=%h expected=%h %s", wr_bursts, wr_base_addr, wr_expected,
                      wr_base_addr === wr_expected ? "PASS" : "FAIL");
            wr_bursts = wr_bursts + 1;
            wr_expected = wr_expected + ADDR_INCR;
        end
        if (rd_start_axi) begin
            if (rd_base_addr !== rd_expected) errors = errors + 1;
            $fdisplay(file_addr, "READ  burst %0d addr=%h expected=%h %s", rd_bursts, rd_base_addr, rd_expected,
                      rd_base_addr === rd_expected ? "PASS" : "FAIL");
            rd_bursts = rd_bursts + 1;
            rd_expected = rd_expected + ADDR_INCR;
        end
    end

    task write_frame(input buffer_id, input [ADDR_WIDTH-1:0] base);
        begin
            wr_bursts = 0;
            wr_expected = base;
            @(negedge aclk);
            wr_cmd = {1'b1, buffer_id};
            @(posedge wr_done_one_frame);
            wr_cmd = 2'b00;
            $fdisplay(file_addr, "WRITE frame buff_%0d: bursts=%0d expected=%0d last addr=%h frame_is_valid=%b %s",
                      buffer_id, wr_bursts, TOTAL_BURST, wr_expected - ADDR_INCR, wr_frame_is_valid,
                      wr_bursts == TOTAL_BURST && wr_frame_is_valid ? "PASS" : "FAIL");
            if (wr_bursts != TOTAL_BURST || !wr_frame_is_valid) errors = errors + 1;
            #100;
        end
    endtask

    task read_frame(input buffer_id, input [ADDR_WIDTH-1:0] base);
        begin
            rd_bursts = 0;
            rd_expected = base;
            @(negedge aclk);
            rd_cmd = {1'b1, buffer_id};
            @(posedge rd_done_one_frame);
            rd_cmd = 2'b00;
            $fdisplay(file_addr, "READ  frame buff_%0d: bursts=%0d expected=%0d last addr=%h frame_is_valid=%b %s",
                      buffer_id, rd_bursts, TOTAL_BURST, rd_expected - ADDR_INCR, rd_frame_is_valid,
                      rd_bursts == TOTAL_BURST && rd_frame_is_valid ? "PASS" : "FAIL");
            if (rd_bursts != TOTAL_BURST || !rd_frame_is_valid) errors = errors + 1;
            #100;
        end
    endtask

    initial begin
        file_addr = $fopen("tb_frame_address.txt", "w");
        errors = 0;
        wr_bursts = 0; rd_bursts = 0;
        wr_expected = 0; rd_expected = 0;

        aresetn = 0;
        init_calib_complete = 0;
        wr_cmd = 2'b00;
        rd_cmd = 2'b00;
        #20

        aresetn = 1;
        init_calib_complete = 1;
        #20

        write_frame(1'b0, 32'h0000_0000);
        write_frame(1'b1, 32'h0009_6000);
        read_frame(1'b0, 32'h0000_0000);
        read_frame(1'b1, 32'h0009_6000);

        $fdisplay(file_addr, "RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $display("tb_frame_address RESULT %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
        $fclose(file_addr);
        $finish;
    end

endmodule
