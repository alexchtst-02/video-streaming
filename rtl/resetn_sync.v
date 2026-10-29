`timescale 1ns / 1ps

module resetn_sync (
    input  wire clk,
    input  wire arstn,
    output wire srstn
);

    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_ff;

    always @(posedge clk or negedge arstn) begin
        if (!arstn)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0], 1'b1};
    end

    assign srstn = sync_ff[1];

endmodule
