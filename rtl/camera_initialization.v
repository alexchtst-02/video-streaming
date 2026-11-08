`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: cam_init.v
// author : amsacks

module camera_initialization #(
    parameter CLK_F = 100_000_000,
    parameter SCCB_F = 400_000
)(   
    input wire      clk,
    input wire      rstn,      
    input wire      cam_init_start,
    output wire     siod,
    output wire     sioc,
    output wire     cam_init_done,        
    
    // Signal used only for testbench
    output wire         data_sent_done,
    output wire [7:0]   SCCB_dout
);
    wire [7:0]  rom_addr;
    wire [15:0] rom_data;
    wire        i2c_ready;
    wire        i2c_start;
    wire [7:0]  i2c_addr;
    wire [7:0]  i2c_data;

    camera_conf_rom OV7670_Registers (
        .clk  (clk),
        .rstn (rstn),
        .addr (rom_addr),
        .dout (rom_data)
    );

    camera_configuration #(
        .CLK_F(CLK_F)
    ) OV7670_config (
        .clk          (clk),
        .rstn         (rstn),
        .i2c_ready    (i2c_ready),
        .config_start (cam_init_start),
        .rom_data     (rom_data),
        .rom_addr     (rom_addr),
        .i2c_start    (i2c_start),
        .i2c_addr     (i2c_addr),
        .i2c_data     (i2c_data),
        .config_done  (cam_init_done)
    );

    sccb_master #(
        .CLK_F (CLK_F),
        .SCCB_F(SCCB_F)
    ) SCCB_HERE (
        .clk     (clk),
        .rstn    (rstn),
        .read    (1'b0),
        .write   (1'b1),
        .start   (i2c_start),
        .restart (1'b0),
        .stop    (1'b0),
        .din     (i2c_data),
        .addr    (i2c_addr),
        .dout    (SCCB_dout),
        .ready   (i2c_ready),
        .done    (data_sent_done),
        .ack     (),
        .sda     (siod),
        .scl     (sioc)
    );
endmodule

`default_nettype wire
