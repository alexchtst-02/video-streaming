`timescale 1ns / 1ps

module med_noise_cancle_kernel_3x3_reconstructor #(
    parameter integer DATA_WIDTH = 8,
    parameter integer LINE_WIDTH = 280
)(
    input wire clk,
    input wire rstn,
    input wire clear_reset_kernel,
    input wire enable,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] din,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    output reg valid_out,
    output reg [DATA_WIDTH*9-1:0] dout,
    output reg [9:0] center_x,
    output reg [9:0] center_y
);
    (* ram_style = "block" *) 
    reg [DATA_WIDTH*2-1:0] row_memory [0:LINE_WIDTH-1];
    
    reg [DATA_WIDTH*2-1:0] row_word;
    reg [DATA_WIDTH-1:0] current_pixel;
    
    reg [9:0] column_q, row_q;
    reg read_valid;
    
    wire memory_read = rstn && !clear_reset_kernel && enable && valid_in && pixel_x < LINE_WIDTH;
    wire memory_write = rstn && !clear_reset_kernel && enable && read_valid && column_q < LINE_WIDTH && row_q < LINE_WIDTH;

    always @(posedge clk) begin
        if (memory_read)
            row_word <= row_memory[pixel_x];
        if (memory_write)
            row_memory[column_q] <= row_q == 0 ? {current_pixel, current_pixel} :
                                                       {row_word[DATA_WIDTH-1:0], current_pixel};
    end

    reg [DATA_WIDTH-1:0] top_left, top_middle;
    reg [DATA_WIDTH-1:0] middle_left, middle_middle;
    reg [DATA_WIDTH-1:0] bottom_left, bottom_middle;
    reg [DATA_WIDTH-1:0] last_top, last_middle, last_bottom;
    wire [DATA_WIDTH-1:0] column_top = row_q == 0 ? current_pixel : row_word[DATA_WIDTH*2-1:DATA_WIDTH];
    wire [DATA_WIDTH-1:0] column_middle = row_q == 0 ? current_pixel : row_word[DATA_WIDTH-1:0];
    wire [DATA_WIDTH-1:0] column_bottom = row_q == LINE_WIDTH ? row_word[DATA_WIDTH-1:0] : current_pixel;

    initial begin
        if (DATA_WIDTH < 1 || LINE_WIDTH < 3 || LINE_WIDTH > 1023)
            $fatal(1, "Invalid median window parameters");
    end

    always @(posedge clk) begin
        if (!rstn || clear_reset_kernel) begin
            read_valid <= 0;
            valid_out <= 0;
            dout <= 0;
            center_x <= 0;
            center_y <= 0;
            column_q <= 0;
            row_q <= 0;
            current_pixel <= 0;
            top_left <= 0;
            top_middle <= 0;
            middle_left <= 0;
            middle_middle <= 0;
            bottom_left <= 0;
            bottom_middle <= 0;
            last_top <= 0;
            last_middle <= 0;
            last_bottom <= 0;
        end else if (enable) begin
            read_valid <= valid_in;
            if (valid_in) begin
                column_q <= pixel_x;
                row_q <= pixel_y;
                current_pixel <= din;
            end
            valid_out <= read_valid && column_q > 0 && row_q > 0;
            if (read_valid) begin
                center_x <= column_q - 1'b1;
                center_y <= row_q - 1'b1;
                if (column_q == LINE_WIDTH) begin
                    dout <= {
                        top_left, top_middle, last_top,
                        middle_left, middle_middle, last_middle,
                        bottom_left, bottom_middle, last_bottom
                    };
                end else begin
                    if (column_q == 0) begin
                        top_left <= column_top;
                        top_middle <= column_top;
                        middle_left <= column_middle;
                        middle_middle <= column_middle;
                        bottom_left <= column_bottom;
                        bottom_middle <= column_bottom;
                    end else begin
                        dout <= {
                            top_left, top_middle, column_top,
                            middle_left, middle_middle, column_middle,
                            bottom_left, bottom_middle, column_bottom
                        };
                        top_left <= top_middle;
                        top_middle <= column_top;
                        middle_left <= middle_middle;
                        middle_middle <= column_middle;
                        bottom_left <= bottom_middle;
                        bottom_middle <= column_bottom;
                    end
                    last_top <= column_top;
                    last_middle <= column_middle;
                    last_bottom <= column_bottom;
                end
            end
        end
    end
endmodule
