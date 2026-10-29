`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: cam_config.v
// author : amsacks

module camera_configuration #(
    parameter integer CLK_F = 100_000_000
)
(   input wire          clk,
    input wire          rstn,
    input wire          i2c_ready,
    input wire          config_start,
    input wire [15:0]   rom_data, 
    output reg [7:0]    rom_addr,
    output reg          i2c_start, 
    output reg [7:0]    i2c_addr,
    output reg [7:0]    i2c_data,
    output reg          config_done
);

    localparam integer TEN_MS_DELAY = (CLK_F * 10) / 1000;
    localparam integer TIMER_WIDTH  = (TEN_MS_DELAY > 1) ? $clog2(TEN_MS_DELAY + 1) : 1;

    localparam [1:0] SM_IDLE  = 2'd0;
    localparam [1:0] SM_SEND  = 2'd1;
    localparam [1:0] SM_DONE  = 2'd2;
    localparam [1:0] SM_TIMER = 2'd3;

    reg [1:0] state;
    reg [1:0] return_state;
    reg [TIMER_WIDTH-1:0] timer;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state        <= SM_IDLE;
            return_state <= SM_IDLE;
            timer        <= {TIMER_WIDTH{1'b0}};
            rom_addr     <= 8'd0;
            i2c_start    <= 1'b0;
            i2c_addr     <= 8'd0;
            i2c_data     <= 8'd0;
            config_done  <= 1'b0;
        end else begin
            i2c_start <= 1'b0;

            case (state)
                SM_IDLE: begin
                    if (config_start) begin
                        state <= SM_SEND;
                    end
                end

                SM_SEND: begin
                    if (i2c_ready) begin
                        case (rom_data)
                            16'hFF_FF: begin
                                state <= SM_DONE;
                            end

                            16'hFF_F0: begin
                                state        <= SM_TIMER;
                                return_state <= SM_SEND;
                                timer        <= TEN_MS_DELAY;
                                rom_addr     <= rom_addr + 1'b1;
                            end

                            default: begin
                                state        <= SM_TIMER;
                                return_state <= SM_SEND;
                                timer        <= {{(TIMER_WIDTH-1){1'b0}}, 1'b1};
                                i2c_start    <= 1'b1;
                                i2c_addr     <= rom_data[15:8];
                                i2c_data     <= rom_data[7:0];
                                rom_addr     <= rom_addr + 1'b1;
                            end
                        endcase
                    end
                end

                SM_DONE: begin
                    state       <= SM_IDLE;
                    config_done <= 1'b1;
                end

                SM_TIMER: begin
                    if (timer == {{(TIMER_WIDTH-1){1'b0}}, 1'b1}) begin
                        timer <= {TIMER_WIDTH{1'b0}};
                        state <= return_state;
                    end else begin
                        timer <= timer - 1'b1;
                    end
                end

                default: begin
                    state <= SM_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
