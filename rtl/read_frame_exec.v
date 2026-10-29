`timescale 1ns / 1ps

module read_frame_exec #(
    parameter integer ADDR_WIDTH = 28,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter integer AXI_ID_WIDTH = 4,
    parameter integer BURST_BEAT = 16,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    
    parameter integer TIMEOUT_CYCLES = 400_000_000
)(
    input wire aclk,
    input wire aresetn,
    input wire init_calib_complete,
    input wire [1:0] frame_executor_cmd,
    input wire axi_busy,
    input wire axi_done,
    input wire axi_error,
    input wire [3:0] axi_error_code,
    output reg start_axi,
    output reg [ADDR_WIDTH-1:0] base_addr_axi,
    output reg done_one_frame,
    output reg frame_is_valid,
    output wire busy,
    output reg fault,
    output reg [3:0] fault_code
);
    localparam [ADDR_WIDTH-1:0] BASE_0 = 'h0000000;
    localparam [ADDR_WIDTH-1:0] BASE_1 = 'h0096000;
    localparam integer FRAME_BYTES = FRAME_WIDTH*FRAME_HEIGHT*2;
    localparam integer ADDR_INCR = (AXI_DATA_WIDTH/8)*BURST_BEAT;
    localparam integer TOTAL_BURST = FRAME_BYTES/ADDR_INCR;
    localparam integer BURST_COUNT_WIDTH = TOTAL_BURST > 1 ? $clog2(TOTAL_BURST) : 1;
    localparam integer TIMEOUT_WIDTH = TIMEOUT_CYCLES > 1 ? $clog2(TIMEOUT_CYCLES) : 1;
    localparam [1:0] IDLE = 0, ISSUE = 1, WAIT_BURST = 2, FAULT = 3;
    reg [1:0] state;
    reg [BURST_COUNT_WIDTH-1:0] burst_count;
    reg [TIMEOUT_WIDTH-1:0] timeout_count;
    assign busy = state != IDLE;

    initial begin
        if (TOTAL_BURST < 1 || FRAME_BYTES % ADDR_INCR != 0 || TIMEOUT_CYCLES < 1)
            $fatal(1, "Frame must contain an integer number of fixed AXI bursts");
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
            start_axi <= 0;
            base_addr_axi <= 0;
            done_one_frame <= 0;
            frame_is_valid <= 0;
            burst_count <= 0;
            timeout_count <= 0;
            fault <= 0;
            fault_code <= 0;
        end else begin
            start_axi <= 0;
            done_one_frame <= 0;
            if (state == IDLE || state == FAULT || start_axi || axi_done)
                timeout_count <= 0;
            else
                timeout_count <= timeout_count+1'b1;
            if (state != IDLE && state != FAULT && axi_error) begin
                fault <= 1;
                fault_code <= axi_error_code;
                frame_is_valid <= 0;
                done_one_frame <= 1;
                state <= FAULT;
            end else if (state != IDLE && state != FAULT && timeout_count == TIMEOUT_CYCLES-1) begin
                fault <= 1;
                fault_code <= 4'hf;
                frame_is_valid <= 0;
                done_one_frame <= 1;
                state <= FAULT;
            end else begin
                case (state)
                    IDLE: begin
                        if (frame_executor_cmd[1] && init_calib_complete && !axi_busy) begin
                            base_addr_axi <= frame_executor_cmd[0] ? BASE_1 : BASE_0;
                            burst_count <= 0;
                            frame_is_valid <= 0;
                            state <= ISSUE;
                        end
                    end
                    ISSUE: begin
                        if (!axi_busy) begin
                            start_axi <= 1;
                            state <= WAIT_BURST;
                        end
                    end
                    WAIT_BURST: begin
                        if (axi_done) begin
                            if (burst_count == TOTAL_BURST-1) begin
                                done_one_frame <= 1;
                                frame_is_valid <= 1;
                                state <= IDLE;
                            end else begin
                                burst_count <= burst_count+1'b1;
                                base_addr_axi <= base_addr_axi+ADDR_INCR;
                                state <= ISSUE;
                            end
                        end
                    end
                    FAULT: state <= FAULT;
                    default: state <= FAULT;
                endcase
            end
        end
    end
endmodule
