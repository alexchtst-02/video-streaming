`timescale 1ns / 1ps

module noise_median_cancle #(
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer ROI_SIZE = 280
)(
    input wire clk,
    input wire sys_rstn,
    
    input wire [15:0] fifo_dout,
    input wire fifo_empty,
    input wire fifo_valid,
    
    input wire [7:0] gray8,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire ready_from_downstream,
    
    output wire ready_to_upstream,
    output wire [15:0] dout,
    output wire valid_out,
    
    output wire [7:0] median8,
    output wire median_valid,
    output wire [9:0] pixel_x_out,
    output wire [9:0] pixel_y_out,
    output wire frame_start_out,
    output wire frame_end_out,
    output wire [31:0] frame_id_out
);
    localparam integer ROI_X = (FRAME_WIDTH-ROI_SIZE)/2;
    localparam integer ROI_Y = (FRAME_HEIGHT-ROI_SIZE)/2;
    localparam integer RAW_DELAY = FRAME_WIDTH+1;
    localparam integer POINTER_WIDTH = $clog2(RAW_DELAY);
    localparam integer COUNT_WIDTH = $clog2(RAW_DELAY+1);
    localparam integer MEDIAN_STAGES = 9;

    wire resetn;
    resetn_sync reset_sync (.clk(clk), .arstn(sys_rstn), .srstn(resetn));

    reg [MEDIAN_STAGES-1:0] raw_valid_pipe;
    wire advance = resetn && (!raw_valid_pipe[MEDIAN_STAGES-1] || ready_from_downstream);
    
    reg flushing;
    reg [COUNT_WIDTH-1:0] flush_remaining;
    reg [COUNT_WIDTH-1:0] filled;
    reg [POINTER_WIDTH-1:0] write_pointer;
    
    assign ready_to_upstream = resetn && advance && !flushing;
    
    wire input_fire = fifo_valid && ready_to_upstream;
    wire step = advance && (input_fire || flushing);
    wire delayed_pixel_fire = step && filled == RAW_DELAY;

    (* ram_style = "block" *) reg [15:0] raw_memory [0:RAW_DELAY-1];
    reg [15:0] raw_read_data;
    always @(posedge clk) begin
        if (step) begin
            raw_read_data <= raw_memory[write_pointer];
            raw_memory[write_pointer] <= flushing ? 16'd0 : fifo_dout;
        end
    end

    wire [9:0] delayed_x, delayed_y;
    wire [31:0] delayed_frame_id;
    wire delayed_start, delayed_end;
    monitor_px_counter #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)) delayed_coordinates (
        .clk(clk), .rstn(resetn), .clear_frame(1'b0),
        .valid_in(delayed_pixel_fire), .ready_from_downstream(advance),
        .pixel_x(delayed_x), .pixel_y(delayed_y), .frame_id(delayed_frame_id),
        .frame_start(delayed_start), .frame_end(delayed_end), .pixel_fire()
    );

    reg raw_read_valid, raw_window_valid;
    reg [15:0] raw_window_data;
    reg [9:0] raw_read_x, raw_read_y, raw_window_x, raw_window_y;
    reg [31:0] raw_read_id, raw_window_id;
    reg raw_read_start, raw_read_end, raw_window_start, raw_window_end;
    
    reg [15:0] raw_data_pipe [0:MEDIAN_STAGES-1];
    reg [9:0] raw_x_pipe [0:MEDIAN_STAGES-1];
    reg [9:0] raw_y_pipe [0:MEDIAN_STAGES-1];
    reg [31:0] raw_id_pipe [0:MEDIAN_STAGES-1];
    reg [MEDIAN_STAGES-1:0] raw_start_pipe, raw_end_pipe;
    
    integer stage_index;

    always @(posedge clk) begin
        if (!resetn) begin
            flushing <= 0;
            flush_remaining <= 0;
            filled <= 0;
            write_pointer <= 0;
            
            raw_read_valid <= 0;
            raw_window_valid <= 0;
            raw_window_data <= 0;
            raw_read_x <= 0;
            raw_read_y <= 0;
            raw_window_x <= 0;
            raw_window_y <= 0;
            
            raw_read_id <= 0;
            raw_window_id <= 0;
            raw_read_start <= 0;
            raw_read_end <= 0;
            
            raw_window_start <= 0;
            raw_window_end <= 0;
            
            raw_valid_pipe <= 0;
            raw_start_pipe <= 0;
            raw_end_pipe <= 0;
            
            for (stage_index = 0; stage_index < MEDIAN_STAGES; stage_index = stage_index+1) begin
                raw_data_pipe[stage_index] <= 0;
                raw_x_pipe[stage_index] <= 0;
                raw_y_pipe[stage_index] <= 0;
                raw_id_pipe[stage_index] <= 0;
            end
        end else if (advance) begin
            raw_read_valid <= delayed_pixel_fire;
            raw_read_x <= delayed_x;
            raw_read_y <= delayed_y;
            
            raw_read_id <= delayed_frame_id;
            raw_read_start <= delayed_start;
            raw_read_end <= delayed_end;
            
            raw_window_data <= raw_read_data;
            raw_window_valid <= raw_read_valid;
            raw_window_x <= raw_read_x;
            raw_window_y <= raw_read_y;
            raw_window_id <= raw_read_id;
            raw_window_start <= raw_read_start;
            raw_window_end <= raw_read_end;
            
            raw_valid_pipe[0] <= raw_window_valid;
            raw_data_pipe[0] <= raw_window_data;
            raw_x_pipe[0] <= raw_window_x;
            raw_y_pipe[0] <= raw_window_y;
            raw_id_pipe[0] <= raw_window_id;
            raw_start_pipe[0] <= raw_window_start;
            raw_end_pipe[0] <= raw_window_end;
            
            for (stage_index = 1; stage_index < MEDIAN_STAGES; stage_index = stage_index+1) begin
                raw_valid_pipe[stage_index] <= raw_valid_pipe[stage_index-1];
                raw_data_pipe[stage_index] <= raw_data_pipe[stage_index-1];
                raw_x_pipe[stage_index] <= raw_x_pipe[stage_index-1];
                raw_y_pipe[stage_index] <= raw_y_pipe[stage_index-1];
                raw_id_pipe[stage_index] <= raw_id_pipe[stage_index-1];
                raw_start_pipe[stage_index] <= raw_start_pipe[stage_index-1];
                raw_end_pipe[stage_index] <= raw_end_pipe[stage_index-1];
            end
            if (step) begin
                if (write_pointer == RAW_DELAY-1)
                    write_pointer <= 0;
                else
                    write_pointer <= write_pointer+1'b1;
                if (filled < RAW_DELAY)
                    filled <= filled+1'b1;
                if (flushing) begin
                    flush_remaining <= flush_remaining-1'b1;
                    if (flush_remaining == 1) begin
                        flushing <= 0;
                        filled <= 0;
                        write_pointer <= 0;
                    end
                end else if (pixel_x == FRAME_WIDTH-1 && pixel_y == FRAME_HEIGHT-1) begin
                    flushing <= 1;
                    flush_remaining <= RAW_DELAY;
                end
            end
        end
    end

    wire extended_roi = input_fire && pixel_x >= ROI_X 
            && pixel_x <= ROI_X+ROI_SIZE 
                && pixel_y >= ROI_Y 
                    && pixel_y <= ROI_Y+ROI_SIZE;
                    
    wire [9:0] local_x = pixel_x-ROI_X;
    wire [9:0] local_y = pixel_y-ROI_Y;
    wire [71:0] window_data;
    wire window_valid;
    
    med_noise_cancle_kernel_3x3_reconstructor #(.DATA_WIDTH(8), .LINE_WIDTH(ROI_SIZE)) window_generator (
        .clk(clk), .rstn(resetn), .clear_reset_kernel(1'b0), .enable(advance),
        .valid_in(extended_roi), .din(gray8), .pixel_x(local_x), .pixel_y(local_y),
        .valid_out(window_valid), .dout(window_data), .center_x(), .center_y()
    );
    
    median9_pipeline median_core (
        .clk(clk), .rstn(resetn), .enable(advance),
        .valid_in(window_valid), .din(window_data),
        .valid_out(median_valid), .dout(median8)
    );

    assign dout = raw_data_pipe[MEDIAN_STAGES-1];
    assign valid_out = raw_valid_pipe[MEDIAN_STAGES-1];
    assign pixel_x_out = raw_x_pipe[MEDIAN_STAGES-1];
    assign pixel_y_out = raw_y_pipe[MEDIAN_STAGES-1];
    assign frame_id_out = raw_id_pipe[MEDIAN_STAGES-1];
    assign frame_start_out = raw_start_pipe[MEDIAN_STAGES-1];
    assign frame_end_out = raw_end_pipe[MEDIAN_STAGES-1];

    initial begin
        if (ROI_SIZE < 3 || ROI_SIZE > 1023 || ROI_X < 1 || ROI_Y < 1 ||
            ROI_X+ROI_SIZE >= FRAME_WIDTH || ROI_Y+ROI_SIZE >= FRAME_HEIGHT)
            $fatal(1, "Median ROI requires one surrounding VGA row/column for replicated borders");
    end
endmodule
