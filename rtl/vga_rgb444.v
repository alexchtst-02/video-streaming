`timescale 1ns / 1ps

module vga_rgb444 #(
    parameter integer H_VISIBLE = 640,
    parameter integer H_FRONT = 16,
    parameter integer H_SYNC = 96,
    parameter integer H_BACK = 48,
    parameter integer V_VISIBLE = 480,
    parameter integer V_FRONT = 10,
    parameter integer V_SYNC = 2,
    parameter integer V_BACK = 33
)(
    input wire vga_clk,
    input wire sys_rstn,
    
    input wire valid_in,
    input wire [15:0] din,
    
    output wire ready_to_upstream,
    
    output reg [3:0] vga_r,
    output reg [3:0] vga_g,
    output reg [3:0] vga_b,
    output reg vga_hs,
    output reg vga_vs,
    
    output reg vga_vblank_start,
    output reg vga_frame_start,
    output reg underflow
);
    localparam integer H_TOTAL = H_VISIBLE+H_FRONT+H_SYNC+H_BACK;
    localparam integer V_TOTAL = V_VISIBLE+V_FRONT+V_SYNC+V_BACK;
    wire resetn;
    resetn_sync uut_resetn (.clk(vga_clk), .arstn(sys_rstn), .srstn(resetn));
    reg [9:0] horizontal_count, vertical_count;
    reg display_enabled;
    wire active_video = horizontal_count < H_VISIBLE && vertical_count < V_VISIBLE;
    wire start_position = horizontal_count == 0 && vertical_count == 0;
    wire displaying = !underflow && (display_enabled || (start_position && valid_in));
    assign ready_to_upstream = resetn && active_video && displaying;

    initial begin
        if (H_TOTAL > 1024 || V_TOTAL > 1024 || H_VISIBLE < 1 || V_VISIBLE < 1)
            $fatal(1, "Invalid VGA timing parameters");
    end

    always @(posedge vga_clk) begin
        if (!resetn) begin
            horizontal_count <= 0;
            vertical_count <= 0;
            display_enabled <= 0;
            vga_r <= 0;
            vga_g <= 0;
            vga_b <= 0;
            vga_hs <= 1;
            vga_vs <= 1;
            vga_vblank_start <= 0;
            vga_frame_start <= 0;
            underflow <= 0;
        end else begin
            vga_frame_start <= start_position;
            vga_vblank_start <= horizontal_count == 0 && vertical_count == V_VISIBLE;
            vga_hs <= !(horizontal_count >= H_VISIBLE+H_FRONT &&
                        horizontal_count < H_VISIBLE+H_FRONT+H_SYNC);
            vga_vs <= !(vertical_count >= V_VISIBLE+V_FRONT &&
                        vertical_count < V_VISIBLE+V_FRONT+V_SYNC);
            if (start_position)
                display_enabled <= valid_in && !underflow;
            if (active_video && displaying && valid_in) begin
                vga_r <= din[11:8];
                vga_g <= din[7:4];
                vga_b <= din[3:0];
            end else begin
                vga_r <= 0;
                vga_g <= 0;
                vga_b <= 0;
            end
            if (active_video && displaying && !valid_in) begin
                underflow <= 1;
                display_enabled <= 0;
            end
            if (horizontal_count == H_TOTAL-1) begin
                horizontal_count <= 0;
                if (vertical_count == V_TOTAL-1)
                    vertical_count <= 0;
                else
                    vertical_count <= vertical_count+1'b1;
            end else begin
                horizontal_count <= horizontal_count+1'b1;
            end
        end
    end
endmodule
