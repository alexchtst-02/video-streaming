`timescale 1ns / 1ps

(* use_dsp = "no" *)
module median9_pipeline #(
    parameter integer DATA_WIDTH = 8
)(
    input wire clk,
    input wire rstn,
    input wire enable,
    input wire valid_in,
    input wire [DATA_WIDTH*9-1:0] din,
    output wire valid_out,
    output wire [DATA_WIDTH-1:0] dout
);
    reg [DATA_WIDTH*9-1:0] stage_data [0:8];
    reg [8:0] stage_valid;
    integer stage_index;

    assign valid_out = stage_valid[8];
    assign dout = stage_data[8][DATA_WIDTH*4 +: DATA_WIDTH];

    function [DATA_WIDTH*9-1:0] compare_swap_pairs;
        input [DATA_WIDTH*9-1:0] values;
        input odd_phase;
        integer pair_index;
        integer first_lane;
        
        reg [DATA_WIDTH-1:0] first_value;
        reg [DATA_WIDTH-1:0] second_value;
        
        begin
            compare_swap_pairs = values;
            for (pair_index = 0; pair_index < 4; pair_index = pair_index+1) begin
                first_lane = pair_index*2 + (odd_phase ? 1 : 0);
                first_value = values[first_lane*DATA_WIDTH +: DATA_WIDTH];
                
                second_value = values[(first_lane+1)*DATA_WIDTH +: DATA_WIDTH];
                
                compare_swap_pairs[first_lane*DATA_WIDTH +: DATA_WIDTH] = 
                    first_value < second_value ? first_value 
                        : second_value;
                compare_swap_pairs[(first_lane+1)*DATA_WIDTH +: DATA_WIDTH] = 
                    first_value > second_value ? first_value 
                        : second_value;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            stage_valid <= 0;
            for (stage_index = 0; stage_index < 9; stage_index = stage_index+1)
                stage_data[stage_index] <= 0;
        end else if (enable) begin
            stage_data[0] <= compare_swap_pairs(din, 1'b0);
            stage_valid[0] <= valid_in;
            for (stage_index = 1; stage_index < 9; stage_index = stage_index+1) begin
                stage_data[stage_index] <= compare_swap_pairs(stage_data[stage_index-1], stage_index % 2 != 0);
                stage_valid[stage_index] <= stage_valid[stage_index-1];
            end
        end
    end
endmodule
