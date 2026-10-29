`timescale 1ns / 1ps

module tresholding (
    input wire valid_in,
    input wire [7:0] val,
    input wire [7:0] tresh_val,
    output wire valid_out,
    output wire [7:0] dout
);
    assign valid_out = valid_in;
    assign dout = val < tresh_val ? 8'd0 : val;
endmodule
