`timescale 1ns / 1ps

module monitor_px_counter #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480
)(
    input wire clk,
    input wire rstn,
    input wire clear_frame,
    input wire valid_in,
    input wire ready_from_downstream,
    output reg [9:0] pixel_x,
    output reg [9:0] pixel_y,
    output reg [31:0] frame_id,
    output wire frame_start,
    output wire frame_end,
    output wire pixel_fire
);
    assign pixel_fire = rstn && !clear_frame && valid_in && ready_from_downstream;
    assign frame_start = pixel_fire && pixel_x == 0 && pixel_y == 0;
    assign frame_end = pixel_fire && pixel_x == FRAME_WIDTH-1 && pixel_y == FRAME_HEIGHT-1;

    initial begin
        if (FRAME_WIDTH < 1 || FRAME_WIDTH > 1024 || FRAME_HEIGHT < 1 || FRAME_HEIGHT > 1024)
            $fatal(1, "Invalid coordinate tracker dimensions");
    end

    always @(posedge clk) begin
        if (!rstn || clear_frame) begin
            pixel_x <= 0;
            pixel_y <= 0;
            frame_id <= 0;
        end else if (pixel_fire) begin
            if (pixel_x == FRAME_WIDTH-1) begin
                pixel_x <= 0;
                if (pixel_y == FRAME_HEIGHT-1) begin
                    pixel_y <= 0;
                    frame_id <= frame_id + 1'b1;
                end else begin
                    pixel_y <= pixel_y + 1'b1;
                end
            end else begin
                pixel_x <= pixel_x + 1'b1;
            end
        end
    end
endmodule
