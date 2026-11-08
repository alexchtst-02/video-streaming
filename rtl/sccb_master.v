`timescale 1ns / 1ps
`default_nettype none

// CITE
// repo: https://github.com/amsacks/OV7670-camera
// module: sccb_master.v
// author : amsacks

/*
 *  Creates SCCB serial protocol in order to write data
 *  to OV7670 registers for configuring pixel output
 *
 */

module sccb_master
#(parameter CLK_F = 100_000_000,
    parameter SCCB_F = 400_000)
    (   input wire          clk,
        input wire          rstn,

        input wire          read,
        input wire          write,
        input wire          start,
        input wire          restart,
        input wire          stop,

        input wire   [7:0]  din,
        input wire   [7:0]  addr,

        output wire  [7:0]  dout,
        output wire         ready,
        output wire         done,
        output wire         ack,

        inout  wire         sda,
        output wire         scl
     );

    // Camera Address for writing
    localparam CAM_ADDR = 7'h21;

    // FSM States
    localparam [3:0] IDLE      = 0,
                     START_1   = 1,
                     START_2   = 2,
                     WAIT      = 3,
                     DATA_1    = 4,
                     DATA_2    = 5,
                     DATA_3    = 6,
                     DATA_4    = 7,
                     DATA_DONE = 8,
                     RESTART   = 9,
                     END_1     = 10,
                     END_2     = 11;

    // CLK_F/SCCB_F is number of clocks in ONE period of the SCCB clock (SCL)
    localparam TIMER_WIDTH = $clog2(CLK_F/SCCB_F);
    localparam HALF        = CLK_F/(2*SCCB_F);
    localparam QUARTER     = HALF/2;

    reg [TIMER_WIDTH - 1: 0] timer;
    reg [3:0]                state;
    reg [8:0]                data_bit_index;
    reg [8:0]                tx_data;
    reg [8:0]                rx_data;
    reg [7:0]                latched_data, latched_addr;
    reg [1:0]                byte_index;
    reg                      data_state;
    wire                     sda_sample;

    reg done_reg;
    reg ready_reg;

    // Buffer SCL and SDA lines
    reg scl_reg, scl_reg_d;
    reg sda_reg, sda_enable_reg_d;

    // Register read/write inputs
    reg read_reg;
    reg write_reg;

   initial begin
        state       = IDLE;
        ready_reg   = 1'b1;
        scl_reg     = 1'b1;
        sda_reg     = 1'b1;
        scl_reg_d   = 1'b1;
        sda_enable_reg_d = 1'b1;
        done_reg    = 1'b0;
   end

    always @(posedge clk or negedge rstn)
        begin
            if(!rstn) begin
                scl_reg_d       <= 1'b1;
                sda_enable_reg_d <= 1'b1;
            end
            else begin
                scl_reg_d       <= scl_reg;
                sda_enable_reg_d <= sda_reg;
            end
        end

    always @(posedge clk)
        begin
            read_reg  <= read;
            write_reg <= write;
        end

    // 2-Wire SCCB bus lines
    assign sda_sample = (data_state && read_reg) ||
                        (data_state && write_reg && data_bit_index == 8);
    OBUFT scl_buffer (
        .I(1'b0),
        .T(scl_reg_d),
        .O(scl)
    );

    OBUFT sda_buffer (
        .I(1'b0),
        .T(sda_sample || sda_enable_reg_d),
        .O(sda)
    );


    // State Machine
    always @(posedge clk)
        begin
            timer <= timer + 1'b1;              // Free Running Counter
            case(state)
                IDLE: begin                     // SDA and SCL line high; Wait for start command
                    timer          <= 0;
                    ready_reg      <= 1'b1;
                    done_reg       <= 1'b0;
                    data_state     <= 1'b0;
                    data_bit_index <= 9'b0;
                    byte_index     <= 2'b0;
                    scl_reg        <= 1'b1;
                    sda_reg        <= 1'b1;
                    latched_data   <= 8'hZZ;
                    latched_addr   <= 8'hZZ;
                    if(start) begin
                            state        <= START_1;
                            timer        <= 0;
                            latched_data <= din;
                            latched_addr <= addr;
                            ready_reg    <= 1'b0;
                        end
                    end
                START_1: begin    // Bring SDA line low; Wait for 1/2 period of SCL
                    sda_reg       <= 1'b0;
                    if(timer == (HALF-1)) begin
                        timer <= 0;
                        state <= START_2;
                    end
                end
                START_2: begin    // Bring SCL line low; Wait for 1/2 period of SCL
                    scl_reg   <= 1'b0;
                    if(timer == (HALF-1)) begin
                        timer        <= 0;
                        state        <= WAIT;
                    end
                end
                WAIT:   begin     // Both SCL/SDA low; Wait for Control Signal (Read or Write)
                    scl_reg        <= 1'b0;
                    sda_reg        <= 1'b0;
                    timer          <= 0;
                    data_bit_index <= 0;
                    byte_index     <= byte_index + 1'b1;
                    state          <= (byte_index == 3) ? END_1 : DATA_1;
                    case(byte_index)                                  // 3-Phase Write Cycle (no ack in SCCB)
                       2'b00: tx_data <= {CAM_ADDR, ~write, 1'b1};       //   byte1 = {SLAVE ADDRESS, WR BIT, Don't Care Bit}
                       2'b01: tx_data <= {latched_addr, 1'b1};           //   byte2 = {Register Addr,         Don't Care Bit}
                       2'b10: tx_data <= {latched_data, 1'b1};           //   byte3 = {Data to Register,      Don't Care Bit}
                       default: tx_data <= {latched_data, 1'b1};
                    endcase

                    if((!write) && (!read)) begin
                        if(stop)                      state <= END_1;
                        else if(restart || start)     state <= RESTART;
                        else                          state <= IDLE;
                    end
                end
                DATA_1: begin   // Load Data Bit to SDA before sampled by SCL
                    sda_reg       <= tx_data[8];
                    scl_reg       <= 1'b0;
                    data_state    <= 1'b1;
                    if(timer == (QUARTER-1)) begin
                        timer <= 0;
                        state <= DATA_2;
                    end
                end
                DATA_2: begin   // SCL Samples the Data Bit (Shift in for read/Shift out for write)
                    sda_reg <= tx_data[8];
                    scl_reg <= 1'b1;
                    // Sample read bits in the middle of SCL being HIGH for sample reads
                    if(timer == (QUARTER-1)) begin
                        timer <= 0;
                        state <= DATA_3;
                        rx_data <= {rx_data[7:0], sda};
                    end
                end
                DATA_3: begin   // Wait another quarter SCL cycle of it being HIGH
                    sda_reg <= tx_data[8];
                    scl_reg <= 1'b1;
                    if(timer == (QUARTER-1)) begin
                        timer <= 0;
                        state <= DATA_4;  // Shift Data In
                    end
                end
                DATA_4: begin   // Bring SCL Low again; Wait another quarter of a cycle
                    sda_reg       <= tx_data[8];
                    scl_reg       <= 1'b0;
                    if(timer == (QUARTER-1)) begin
                        timer <= 0;
                        if(data_bit_index == 8) begin
                            state      <= DATA_DONE;
                            done_reg   <= 1'b1;     // Set done signal HIGH
                            data_state <= 1'b0;
                        end
                        else begin
                            tx_data        <= {tx_data[7:0], 1'b0};
                            data_bit_index <= data_bit_index + 1'b1;
                            state          <= DATA_1;
                        end
                    end
                end
                DATA_DONE: begin
                    done_reg <= 1'b0;     // Set done signal LOW since it's a tick
                    sda_reg  <= 1'b0;
                    scl_reg  <= 1'b0;
                    if(timer == (QUARTER-1)) begin
                        timer <= 0;
                        state <= WAIT;
                    end
                end
                RESTART: begin
                    if(timer == (HALF-1)) begin
                        timer <= 0;
                        state <= START_1;
                    end
                end
                END_1: begin
                    // SCL low, SDA low,        SCL high, SDA high
                    // [ Done in WAIT state]
                    scl_reg <= 1'b1;
                    sda_reg <= 1'b0;
                    if(timer == (HALF-1)) begin
                        timer <= 0;
                        state <= END_2;
                    end
                end
                END_2: begin
                    scl_reg <= 1'b1;
                    sda_reg <= 1'b1;
                    if(timer == (HALF-1)) begin
                        timer <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end

    // Assign Output from SCCBA Reads ( don't read ACK bit )
    assign dout = rx_data[8:1];
    // ACK (from slave in writes should be '0')
    assign ack = rx_data[0];

    // Assign I2C Master Status Signals
    assign ready = ready_reg;
    assign done  = done_reg;

endmodule

`default_nettype wire
