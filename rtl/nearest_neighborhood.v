`timescale 1ns / 1ps

module nearest_neighborhood #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer ROI_SIZE = 280,
    parameter integer OUTPUT_SIZE = 28,
    parameter integer SAMPLE_OFFSET = 5
)(
    input wire valid_in,
    input wire [15:0] din,
    input wire [9:0] cam_x,
    input wire [9:0] cam_y,
    output wire valid_out,
    output wire [15:0] dout
);
    localparam integer ROI_X = (FRAME_WIDTH - ROI_SIZE) / 2;
    localparam integer ROI_Y = (FRAME_HEIGHT - ROI_SIZE) / 2;
    localparam integer SCALE = ROI_SIZE / OUTPUT_SIZE;

    initial begin
        if (OUTPUT_SIZE < 1 || ROI_SIZE < OUTPUT_SIZE ||
            ROI_SIZE % OUTPUT_SIZE != 0 ||
            ROI_SIZE > FRAME_WIDTH || ROI_SIZE > FRAME_HEIGHT ||
            FRAME_WIDTH > 1024 || FRAME_HEIGHT > 1024 ||
            SAMPLE_OFFSET < 0 || SAMPLE_OFFSET >= SCALE)
            $fatal(1, "Invalid ROI/nearest-neighbor parameters");
    end

    wire [OUTPUT_SIZE-1:0] selected_x;
    wire [OUTPUT_SIZE-1:0] selected_y;
    genvar sample_index;
    generate
        for (sample_index = 0; sample_index < OUTPUT_SIZE; sample_index = sample_index+1) begin : sample_position
            localparam [9:0] SAMPLE_X = ROI_X+SAMPLE_OFFSET+sample_index*SCALE;
            localparam [9:0] SAMPLE_Y = ROI_Y+SAMPLE_OFFSET+sample_index*SCALE;
            assign selected_x[sample_index] = cam_x == SAMPLE_X;
            assign selected_y[sample_index] = cam_y == SAMPLE_Y;
        end
    endgenerate
    assign valid_out = valid_in && |selected_x && |selected_y;

    assign dout = din;
endmodule
