`timescale 1ns / 1ps
`default_nettype none

module frame_manager #(
    // Keep the camera request low long enough to cross back to cam_pclk
    // before the next capture. At ui_clk ~= 81 MHz and pclk = 25 MHz,
    // 32 cycles exceed four camera clocks.
    parameter integer WRITE_REARM_CYCLES = 32
)(
    input wire aclk,
    input wire aresetn,
    
    input wire init_calib_complete,
    
    // write_ov7670_frame
    input wire write_ov7670_frame_done_one_frame,
    input wire write_ov7670_frame_frame_is_valid,
    
    // read_ddr_frame
    input wire read_ddr_frame_done_one_frame,
    input wire read_ddr_frame_frame_is_valid,
    input wire read_ddr_frame_busy,
    input wire read_ddr_frame_fault,
    input wire [3:0] read_ddr_frame_fault_code,
    
    output wire [1:0] write_frame_executor_cmd,
    output wire [1:0] read_frame_executor_cmd,

    output wire dbg_use_buff_a,
    output wire dbg_use_buff_b
);
    localparam integer REARM_WIDTH = WRITE_REARM_CYCLES > 0 ?
        $clog2(WRITE_REARM_CYCLES + 1) : 1;

    reg started;
    reg have_display_frame;
    reg write_active;
    reg read_active;
    reg write_bank;
    reg read_bank;
    reg pending_valid;
    reg pending_bank;
    reg [REARM_WIDTH-1:0] write_rearm_count;
    reg [1:0] write_cmd;
    reg [1:0] read_cmd;

    wire write_complete = write_active && write_ov7670_frame_done_one_frame;
    wire read_complete = read_active && read_ddr_frame_done_one_frame;

    // A failed writer may be stuck in FAULT or leave partial pixels in its
    // FIFO. Stop issuing commands until a coordinated system reset.
    // All reader fault codes have the same stop policy; fault_code remains
    // available on the reader itself for diagnostics.
    wire halt_request = read_ddr_frame_fault ||
        (started && !init_calib_complete) ||
        (write_complete && !write_ov7670_frame_frame_is_valid) ||
        (read_complete && !read_ddr_frame_frame_is_valid);
    wire halted;
    high_latcher halt_latch (
        .clk(aclk), .rstn(aresetn), .clear(1'b0),
        .din(halt_request), .dout(halted)
    );

    wire running = aresetn && init_calib_complete && !halted && !halt_request;
    assign write_frame_executor_cmd = running ? write_cmd : 2'b00;
    assign read_frame_executor_cmd = running ? read_cmd : 2'b00;

    // These LEDs indicate an actual DDR frame read, not a start pulse or
    // historical use. Reader busy is also high in FAULT, so gate it above.
    assign dbg_use_buff_a = running && read_active && read_ddr_frame_busy &&
        !read_ddr_frame_done_one_frame && !read_bank;
    assign dbg_use_buff_b = running && read_active && read_ddr_frame_busy &&
        !read_ddr_frame_done_one_frame && read_bank;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            started <= 1'b0;
            have_display_frame <= 1'b0;
            write_active <= 1'b0;
            read_active <= 1'b0;
            write_bank <= 1'b0;
            read_bank <= 1'b0;
            pending_valid <= 1'b0;
            pending_bank <= 1'b0;
            write_rearm_count <= 0;
            write_cmd <= 2'b00;
            read_cmd <= 2'b00;
        end else begin
            // Each executor sees exactly one clock of start enable.
            write_cmd <= 2'b00;
            read_cmd <= 2'b00;

            if (running) begin
                if (write_rearm_count != 0)
                    write_rearm_count <= write_rearm_count - 1'b1;

                if (write_complete) begin
                    write_active <= 1'b0;
                    pending_valid <= 1'b1;
                    pending_bank <= write_bank;
                    write_rearm_count <= WRITE_REARM_CYCLES;
                end

                if (read_complete)
                    read_active <= 1'b0;

                // Before the first display, fill A. Afterwards, fill only
                // the other bank. A completed pending frame is frozen until
                // the reader switches to it; it must not be overwritten.
                if (!write_active && !pending_valid &&
                    write_rearm_count == 0 &&
                    (!have_display_frame || write_bank != read_bank)) begin
                    write_cmd <= {1'b1, write_bank};
                    write_active <= 1'b1;
                    started <= 1'b1;
                end

                // Read a whole valid frame at a time. Prefer a completed
                // new frame, otherwise repeat the current display bank.
                // Releasing the old bank here is safe: its last DDR read
                // has completed, including delivery into the downstream FIFO.
                if (!read_active && !read_ddr_frame_busy &&
                    (have_display_frame || pending_valid)) begin
                    read_active <= 1'b1;
                    have_display_frame <= 1'b1;
                    if (pending_valid) begin
                        read_cmd <= {1'b1, pending_bank};
                        read_bank <= pending_bank;
                        pending_valid <= 1'b0;
                        write_bank <= !pending_bank;
                    end else begin
                        read_cmd <= {1'b1, read_bank};
                    end
                end
                // A write completion on the same clock as a read launch
                // becomes pending for the following read. One extra repeat
                // is allowed; a partial/newly written frame is never read.
            end
        end
    end

    initial begin
        if (WRITE_REARM_CYCLES < 0)
            $fatal(1, "WRITE_REARM_CYCLES must not be negative");
    end
endmodule

`default_nettype wire
