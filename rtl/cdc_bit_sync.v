`timescale 1ns / 1ps

module cdc_bit_sync(
    input  wire aclk,
    input  wire aresetn,

    input  wire in,
    output wire out
);

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg sync_meta;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg sync_data;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            sync_meta <= 1'b0;
            sync_data <= 1'b0;
        end else begin
            sync_meta <= in;
            sync_data <= sync_meta;
        end
    end

    assign out = sync_data;

endmodule
