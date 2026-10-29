`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: cam_rom.v
// author : amsacks

module camera_conf_rom (
    input  wire        clk,
    input  wire        rstn,
    input  wire [7:0]  addr,
    output reg  [15:0] dout
);
    // Registers for OV7670 for configuration of RGB 444
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dout <= 16'd0;
        end else begin
            case (addr)
                8'd0:  dout <= 16'h12_80;  // COM7:        Reset SCCB registers
                8'd1:  dout <= 16'hFF_F0;  // Delay
                8'd2:  dout <= 16'h12_04;  // COM7,        Set RGB color output
                8'd3:  dout <= 16'h11_00;  // CLKRC        Internal PLL matches input clock (24 MHz).
                8'd4:  dout <= 16'h0C_00;  // COM3,        *Leave as default.
                8'd5:  dout <= 16'h3E_00;  // COM14,       *Leave as default. No scaling, normal pclock
                8'd6:  dout <= 16'h04_00;  // COM1,        *Leave as default. Disable CCIR656
                8'd7:  dout <= 16'h8C_02;  // RGB444       Enable RGB444 mode with xR GB.
                8'd8:  dout <= 16'h40_D0;  // COM15,       Output full range for RGB 444.
                8'd9:  dout <= 16'h3A_04;  // TSLB         set correct output data sequence (magic)
                8'd10: dout <= 16'h14_18;  // COM9         MAX AGC value x4
                8'd11: dout <= 16'h4F_B3;  // MTX1         all of these are magical matrix coefficients
                8'd12: dout <= 16'h50_B3;  // MTX2
                8'd13: dout <= 16'h51_00;  // MTX3
                8'd14: dout <= 16'h52_3D;  // MTX4
                8'd15: dout <= 16'h53_A7;  // MTX5
                8'd16: dout <= 16'h54_E4;  // MTX6
                8'd17: dout <= 16'h58_9E;  // MTXS
                8'd18: dout <= 16'h3D_C0;  // COM13        sets gamma enable, does not preserve reserved bits, may be wrong?
                8'd19: dout <= 16'h17_14;  // HSTART       start high 8 bits
                8'd20: dout <= 16'h18_02;  // HSTOP        stop high 8 bits //these kill the odd colored line
                8'd21: dout <= 16'h32_80;  // HREF         edge offset
                8'd22: dout <= 16'h19_03;  // VSTART       start high 8 bits
                8'd23: dout <= 16'h1A_7B;  // VSTOP        stop high 8 bits
                8'd24: dout <= 16'h03_0A;  // VREF         vsync edge offset
                8'd25: dout <= 16'h0F_41;  // COM6         reset timings
                8'd26: dout <= 16'h1E_00;  // MVFP         disable mirror / flip //might have magic value of 03
                8'd27: dout <= 16'h33_0B;  // CHLF         magic value from the internet
                8'd28: dout <= 16'h3C_78;  // COM12        no HREF when VSYNC low
                8'd29: dout <= 16'h69_00;  // GFIX         fix gain control
                8'd30: dout <= 16'h74_00;  // REG74        Digital gain control
                8'd31: dout <= 16'hB0_84;  // RSVD         magic value from the internet *required* for good color
                8'd32: dout <= 16'hB1_0C;  // ABLC1
                8'd33: dout <= 16'hB2_0E;  // RSVD         more magic internet values
                8'd34: dout <= 16'hB3_80;  // THL_ST
                //begin mystery scaling numbers
                8'd35: dout <= 16'h70_3A;  // SCALING_XSC          *Leave as default. No test pattern output.
                8'd36: dout <= 16'h71_35;  // SCALING_YSC          *Leave as default. No test pattern output.
                8'd37: dout <= 16'h72_11;  // SCALING DCWCTR       *Leave as default. Vertical down sample by 2. Horizontal down sample by 2.
                8'd38: dout <= 16'h73_F0;  // SCALING PCLK_DIV
                8'd39: dout <= 16'hA2_02;  // SCALING PCLK DELAY   *Leave as default.
                //gamma curve values
                8'd40: dout <= 16'h7A_20;  // SLOP
                8'd41: dout <= 16'h7B_10;  // GAM1
                8'd42: dout <= 16'h7C_1E;  // GAM2
                8'd43: dout <= 16'h7D_35;  // GAM3
                8'd44: dout <= 16'h7E_5A;  // GAM4
                8'd45: dout <= 16'h7F_69;  // GAM5
                8'd46: dout <= 16'h80_76;  // GAM6
                8'd47: dout <= 16'h81_80;  // GAM7
                8'd48: dout <= 16'h82_88;  // GAM8
                8'd49: dout <= 16'h83_8F;  // GAM9
                8'd50: dout <= 16'h84_96;  // GAM10
                8'd51: dout <= 16'h85_A3;  // GAM11
                8'd52: dout <= 16'h86_AF;  // GAM12
                8'd53: dout <= 16'h87_C4;  // GAM13
                8'd54: dout <= 16'h88_D7;  // GAM14
                8'd55: dout <= 16'h89_E8;  // GAM15
                //AGC and AEC
                8'd56: dout <= 16'h13_E0;  // COM8     disable AGC / AEC
                8'd57: dout <= 16'h00_00;  // set gain reg to 0 for AGC
                8'd58: dout <= 16'h10_00;  // set ARCJ reg to 0
                8'd59: dout <= 16'h0D_40;  // magic reserved bit for COM4
                8'd60: dout <= 16'h14_18;  // COM9, 4x gain + magic bit
                8'd61: dout <= 16'hA5_05;  // BD50MAX
                8'd62: dout <= 16'hAB_07;  // DB60MAX
                8'd63: dout <= 16'h24_95;  // AGC upper limit
                8'd64: dout <= 16'h25_33;  // AGC lower limit
                8'd65: dout <= 16'h26_E3;  // AGC/AEC fast mode op region
                8'd66: dout <= 16'h9F_78;  // HAECC1
                8'd67: dout <= 16'hA0_68;  // HAECC2
                8'd68: dout <= 16'hA1_03;  // magic
                8'd69: dout <= 16'hA6_D8;  // HAECC3
                8'd70: dout <= 16'hA7_D8;  // HAECC4
                8'd71: dout <= 16'hA8_F0;  // HAECC5
                8'd72: dout <= 16'hA9_90;  // HAECC6
                8'd73: dout <= 16'hAA_94;  // HAECC7
                8'd74: dout <= 16'h13_A7;  // COM8, enable AGC / AEC
                8'd75: dout <= 16'h69_06;
                default: dout <= 16'hFF_FF;  //mark end of ROM
            endcase
        end
    end
endmodule

`default_nettype wire
