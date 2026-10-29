`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: debouncer.v
// author : amsacks

module debouncer #(
    parameter integer DELAY = 1_000_000
)(
    input  wire clk,
    input  wire btn,
    output wire signal_db
);
    localparam integer COUNTER_WIDTH = (DELAY < 1) ? 1 : $clog2(DELAY + 1);

    reg [COUNTER_WIDTH-1:0] counter;
    reg r_sample;

    initial begin
        counter  = {COUNTER_WIDTH{1'b0}};
        r_sample = 1'b0;
    end

    always @(posedge clk) begin
        if (btn !== r_sample && counter < DELAY) begin
            counter <= counter + 1'b1;
        end else if (counter == DELAY) begin
            counter  <= {COUNTER_WIDTH{1'b0}};
            r_sample <= btn;
        end else begin
            counter <= {COUNTER_WIDTH{1'b0}};
        end
    end

    assign signal_db = r_sample;
endmodule

`default_nettype wire
