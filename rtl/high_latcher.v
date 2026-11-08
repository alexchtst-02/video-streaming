`timescale 1ns / 1ps

module high_latcher (
    input  wire clk,
    input  wire rstn,
    input  wire clear,
    input  wire din,
    output reg  dout
);

    always @(posedge clk) begin
        if (!rstn)
            dout <= 1'b0;
        else if (clear)
            dout <= 1'b0;
        else if (din)
            dout <= 1'b1;
    end

endmodule