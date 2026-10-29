`timescale 1ns / 1ps

module rgb444_to_grayscale (
    input wire valid_in,
    input wire [15:0] rgb444,
    input wire [2:0] mode,
    output wire valid_out,
    output reg  [7:0] gray8
);

    wire [3:0] r4 = rgb444[11:8];
    wire [3:0] g4 = rgb444[7:4];
    wire [3:0] b4 = rgb444[3:0];

    wire [7:0] r8 = {r4, r4};
    wire [7:0] g8 = {g4, g4};
    wire [7:0] b8 = {b4, b4};

    // Y = (77*R + 150*G + 29*B) / 256
    (* use_dsp = "no" *)
    wire [15:0] weighted_sum;

    assign weighted_sum =
        (r8 * 16'd77) +
        (g8 * 16'd150) +
        (b8 * 16'd29);

    wire [7:0] gray_normal = weighted_sum[15:8];

    assign valid_out = valid_in;

    always @(*) begin
        case (mode)
            3'b000:  gray8 = ~gray_normal; // INVERT
            3'b001:  gray8 = r8;           // RED
            3'b010:  gray8 = g8;           // GREEN
            3'b011:  gray8 = b8;           // BLUE
            3'b100:  gray8 = gray_normal;
            default: gray8 = 8'd0;
        endcase
    end

endmodule
