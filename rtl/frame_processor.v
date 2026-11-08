`timescale 1ns / 1ps

module frame_processor #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer ROI_SIZE = 280,
    parameter integer OUTPUT_SIZE = 28,
    parameter integer SAMPLE_OFFSET = 5
)(
    input wire clk,
    input wire sys_rstn,
    
    input wire [3:0] sw_mode,
    input wire [7:0] tresh_val,
    
    input wire [15:0] fifo_dout,
    input wire fifo_empty,
    input wire fifo_valid,
    input wire ready_from_downstream,
    
    output wire ready_to_fifo,
    output reg [15:0] dout,
    output reg valid_out,
    
    output reg [9:0] pixel_x_out,
    output reg [9:0] pixel_y_out,
    
    output reg frame_start_out,
    output reg frame_end_out,
    output reg [31:0] frame_id_out,
    
    output wire [7:0] cnn_dout,
    output wire cnn_valid_out,
    output reg processing_error
);
    localparam integer ROI_X = (FRAME_WIDTH-ROI_SIZE) / 2;
    localparam integer ROI_Y = (FRAME_HEIGHT-ROI_SIZE) / 2;
    wire resetn;
    resetn_sync uut_resetn (.clk(clk), .arstn(sys_rstn), .srstn(resetn));
    (* ASYNC_REG = "TRUE" *) reg [3:0] switch_meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] switch_sync;
    always @(posedge clk) begin
        if (!resetn) begin
            switch_meta <= 0;
            switch_sync <= 0;
        end else begin
            switch_meta <= sw_mode;
            switch_sync <= switch_meta;
        end
    end

    wire [9:0] source_x, source_y;
    monitor_px_counter #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)) input_coordinates (
        .clk(clk), 
        .rstn(resetn), 
        .clear_frame(1'b0),
        .valid_in(fifo_valid), 
        .ready_from_downstream(ready_to_fifo),
        .pixel_x(source_x), 
        .pixel_y(source_y), 
        .frame_id(),
        .frame_start(), 
        .frame_end(), 
        .pixel_fire()
    );
    
    reg [2:0] gray_mode;
    always @(*) begin
        case (switch_sync[2:0])
            3'b001: gray_mode = 3'b001;
            3'b010: gray_mode = 3'b010;
            3'b100: gray_mode = 3'b011;
            3'b111: gray_mode = 3'b000;
            default: gray_mode = 3'b100;
        endcase
    end
    
    wire [7:0] source_gray;
    rgb444_to_grayscale grayscale (
        .valid_in(fifo_valid), 
        .rgb444(fifo_dout), 
        .mode(gray_mode),
        .valid_out(), 
        .gray8(source_gray)
    );

    wire output_slot = !valid_out || ready_from_downstream;
    wire [15:0] delayed_rgb;
    wire delayed_valid, median_valid;
    wire [7:0] median_gray;
    wire [9:0] delayed_x, delayed_y;
    wire delayed_start, delayed_end;
    wire [31:0] delayed_id;
    noise_median_cancle #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT), .ROI_SIZE(ROI_SIZE)
    ) median_filter (
        .clk(clk), .sys_rstn(resetn), .fifo_dout(fifo_dout),
        .fifo_empty(fifo_empty), .fifo_valid(fifo_valid), .gray8(source_gray),
        .pixel_x(source_x), .pixel_y(source_y), .ready_from_downstream(output_slot),
        .ready_to_upstream(ready_to_fifo), .dout(delayed_rgb), .valid_out(delayed_valid),
        .median8(median_gray), .median_valid(median_valid),
        .pixel_x_out(delayed_x), .pixel_y_out(delayed_y),
        .frame_start_out(delayed_start), .frame_end_out(delayed_end), .frame_id_out(delayed_id)
    );
    wire delayed_roi = delayed_x >= ROI_X && delayed_x < ROI_X+ROI_SIZE &&
                       delayed_y >= ROI_Y && delayed_y < ROI_Y+ROI_SIZE;
    wire [7:0] threshold_pixel;
    wire threshold_valid;
    tresholding threshold_filter (
        .valid_in(delayed_valid && median_valid && delayed_roi),
        .val(median_gray), .tresh_val(tresh_val),
        .valid_out(threshold_valid), .dout(threshold_pixel)
    );
    
    // delayer
    reg [7:0] threshold_pixel_q;
    reg threshold_valid_q;
    always @(posedge clk) begin
        if (!resetn) begin
            dout <= 0;
            valid_out <= 0;
            pixel_x_out <= 0;
            pixel_y_out <= 0;
            frame_id_out <= 0;
            frame_start_out <= 0;
            frame_end_out <= 0;
            threshold_pixel_q <= 0;
            threshold_valid_q <= 0;
            processing_error <= 0;
        end else if (output_slot) begin
        
            valid_out <= delayed_valid;
            pixel_x_out <= delayed_x;
            pixel_y_out <= delayed_y;
            
            frame_id_out <= delayed_id;
            frame_start_out <= delayed_start;
            frame_end_out <= delayed_end;
            
            threshold_pixel_q <= threshold_pixel;
            threshold_valid_q <= threshold_valid;
            
            dout <= switch_sync[3] && threshold_valid ? {4'd0, threshold_pixel[7:4], threshold_pixel[7:4], threshold_pixel[7:4]} : delayed_rgb;
            
            if (delayed_valid && delayed_roi && !median_valid)
                processing_error <= 1;
        end
    end

    wire output_fire = resetn && valid_out && ready_from_downstream;
    wire [15:0] sampled_data;
    nearest_neighborhood #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .ROI_SIZE(ROI_SIZE), .OUTPUT_SIZE(OUTPUT_SIZE), .SAMPLE_OFFSET(SAMPLE_OFFSET)
    ) resize (
        .valid_in(output_fire && threshold_valid_q), 
        .din({8'd0, threshold_pixel_q}),
        .cam_x(pixel_x_out), 
        .cam_y(pixel_y_out),
        .valid_out(cnn_valid_out), 
        .dout(sampled_data)
    );
    assign cnn_dout = sampled_data[7:0];
endmodule

