`timescale 1ns / 1ps
`default_nettype none

// Active-high buttons, one step per debounced press, saturating at 0 and 255.
// Use the same clock as frame_processor/clk; the processed wrapper uses vga_clk.
module tresh_value_control #(
    parameter integer INITIAL_VALUE = 128,
    parameter integer DEBOUNCE_CYCLES = 1_000_000
)(
    input wire clk,
    input wire rstn,
    input wire higher_up_tresh,
    input wire lower_down_tresh,
    output reg [7:0] tresh_value
);
    localparam integer COUNT_WIDTH = DEBOUNCE_CYCLES > 1 ?
        $clog2(DEBOUNCE_CYCLES) : 1;

    (* ASYNC_REG = "TRUE" *) reg [1:0] button_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0] button_sync;
    reg [1:0] button_stable;
    reg [1:0] button_stable_d;
    reg [COUNT_WIDTH-1:0] debounce_count [0:1];
    integer button_index;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            button_meta <= 2'b00;
            button_sync <= 2'b00;
        end else begin
            button_meta <= {lower_down_tresh, higher_up_tresh};
            button_sync <= button_meta;
        end
    end

    // Debounce press and release independently for each button. A held
    // button creates no additional edge; release must settle before reuse.
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            button_stable <= 2'b00;
            button_stable_d <= 2'b00;
            for (button_index=0; button_index<2; button_index=button_index+1)
                debounce_count[button_index] <= 0;
        end else begin
            button_stable_d <= button_stable;
            for (button_index=0; button_index<2; button_index=button_index+1) begin
                if (button_sync[button_index] == button_stable[button_index]) begin
                    debounce_count[button_index] <= 0;
                end else if (debounce_count[button_index] == DEBOUNCE_CYCLES-1) begin
                    button_stable[button_index] <= button_sync[button_index];
                    debounce_count[button_index] <= 0;
                end else begin
                    debounce_count[button_index] <= debounce_count[button_index]+1'b1;
                end
            end
        end
    end

    wire higher_press = button_stable[0] && !button_stable_d[0];
    wire lower_press = button_stable[1] && !button_stable_d[1];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tresh_value <= INITIAL_VALUE[7:0];
        end else begin
            case ({higher_press, lower_press})
                2'b10: if (tresh_value != 8'd255)
                    tresh_value <= tresh_value+1'b1;
                2'b01: if (tresh_value != 8'd0)
                    tresh_value <= tresh_value-1'b1;
                // Events on the same clock cancel each other.
                default: tresh_value <= tresh_value;
            endcase
        end
    end

    initial begin
        if (INITIAL_VALUE < 0 || INITIAL_VALUE > 255)
            $fatal(1, "INITIAL_VALUE must be in range 0..255");
        if (DEBOUNCE_CYCLES < 1)
            $fatal(1, "DEBOUNCE_CYCLES must be at least 1");
    end
endmodule

`default_nettype wire
