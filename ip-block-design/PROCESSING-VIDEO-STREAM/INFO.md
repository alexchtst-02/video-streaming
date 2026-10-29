# PROCESSING VIDEO STREAM

## FUNCTIONS

This block design is the [VIDEO-STREAM](../VIDEO-STREAM/INFO.md) design with a
**frame processor** on the read side. Video from an **OV7670** camera is
streamed to a **Pmod VGA** display (640 × 480, RGB444), using the on-board
**DDR3 SDRAM** as frame storage with the same **double buffer (ping-pong)
scheme**. Frames are stored in DDR3 unprocessed; every frame read from DDR3
passes through the frame processor before it reaches the VGA output.

The frame processor works on a **280 × 280 region of interest (ROI)** in the
centre of the frame (x = 180–459, y = 100–379):

1. **Grayscale**: converts each RGB444 pixel to 8-bit gray. The source is
   selected with SW2–SW0 (`sw_mode[2:0]`).
2. **Median filter**: removes noise with a 3 × 3 median filter on the gray
   image.
3. **Thresholding**: pixels below the threshold become black, the others keep
   their gray value. The threshold starts at 128 and is changed with two
   buttons, one step per press, between 0 and 255.

SW3 (`sw_mode[3]`) selects what the VGA shows. Off: the original colour frame.
On: the processed ROI, with the original colour frame around it.

| `sw_mode[2:0]` | grayscale source |
| --- | --- |
| `001` | red channel |
| `010` | green channel |
| `100` | blue channel |
| `111` | inverted luma |
| others | luma, Y = (77·R + 150·G + 29·B) / 256 |

| control | board | function |
| --- | --- | --- |
| `sw_mode[0]` – `sw_mode[3]` | SW0 – SW3 | grayscale source and display mode |
| `higher_up_tresh` | BTN2 | threshold + 1 |
| `lower_down_tresh` | BTN3 | threshold − 1 |

The frames stored in DDR3 have been verified on hardware with the method in
[verifications](../../verifications/INFO.md). The frame processor runs after
DDR3 on the read side, so its result is only visible on the VGA output.

## MODULES

The block design contains three RTL module references. The first table lists
these top modules, and the second table lists the wrapper modules inside
them, down to three levels below the top. All files are in [rtl](../../rtl/).

**Top modules**
| top module | contents | function |
| --- | --- | --- |
| [write_data_path](../../rtl/write_data_path.v) | `guarded_ov7670`<br>`attributed_async_fifo`<br>`write_ov7670_frame` | Camera side: configures the OV7670, captures one 640 × 480 RGB444 frame and writes it to DDR3 through AXI |
| [read_data_path_processed](../../rtl/read_data_path_processed.v) | `read_ddr_frame`<br>`attributed_async_fifo`<br>`resetn_sync` (×2)<br>`tresh_value_control`<br>`frame_processor`<br>`vga_rgb444` | VGA side: reads one frame from DDR3 through AXI, processes it and drives the VGA output |
| [frame_manager](../../rtl/frame_manager.v) | `high_latcher` | Schedules frame writes and reads, selects buffer A or B for each side, swaps the ping-pong buffers and halts on faults |

**Wrapper modules**
| top module | contents | function |
| --- | --- | --- |
| [guarded_ov7670](../../rtl/guarded_ov7670.v) | `ov7670_stream`<br>`px_watcher` | Camera stream with a frame checker |
| [ov7670_stream](../../rtl/ov7670_stream.v) | `debouncer`<br>`camera_initialization`<br>`camera_capture` | OV7670 SCCB initialization and one-shot RGB444 frame capture |
| [px_watcher](../../rtl/px_watcher.v) | `resetn_sync`<br>`cdc_bit_sync` | Checks the captured frame (coordinates, size, overflow, interruption) and marks it valid or invalid |
| [attributed_async_fifo](../../rtl/attributed_async_fifo.v) | `fifo_unpacker`<br>`async_fifo`<br>`fifo_packer` | Clock domain crossing FIFO with width conversion: 16-bit pixels to 128-bit AXI beats on the write side, and the reverse on the read side |
| [fifo_unpacker](../../rtl/fifo_unpacker.v) | `resetn_sync` | Splits an input word into 16-bit FIFO words |
| [async_fifo](../../rtl/async_fifo.v) | `resetn_sync` (×2) | Gray-code pointer asynchronous FIFO with a reset synchronizer per clock domain |
| [fifo_packer](../../rtl/fifo_packer.v) | `resetn_sync` | Collects 16-bit FIFO words into an output word |
| [write_ov7670_frame](../../rtl/write_ov7670_frame.v) | `write_frame_exec`<br>`axi_write` | Writes one frame from the FIFO to DDR3 |
| [write_frame_exec](../../rtl/write_frame_exec.v) | `cdc_bit_sync` (×2) | Splits one frame into AXI write bursts at the address of buffer A or B |
| [read_ddr_frame](../../rtl/read_ddr_frame.v) | `read_frame_exec`<br>`axi_read` | Reads one frame from DDR3 into the FIFO |
| [frame_processor](../../rtl/frame_processor.v) | `resetn_sync`<br>`monitor_px_counter`<br>`rgb444_to_grayscale`<br>`noise_median_cancle`<br>`tresholding`<br>`nearest_neighborhood` | Grayscale, median filter and thresholding on the 280 × 280 ROI, selected by `sw_mode` |
| [noise_median_cancle](../../rtl/noise_median_cancle.v) | `resetn_sync`<br>`monitor_px_counter`<br>`med_noise_cancle_kernel_3x3_reconstructor`<br>`median9_pipeline` | 3 × 3 median filter on the gray ROI, keeping the original RGB pixel aligned with the result |
| [vga_rgb444](../../rtl/vga_rgb444.v) | `resetn_sync` | 640 × 480 VGA timing generator with RGB444 output |

## CONSTRAIN FILE
the target constrain file is **`base.xdc`** in the constraint set
`constrs_processed_stream`

## BLOCK DESIGNS

Block design `design_processed_stream`, used through the HDL wrapper
`design_processed_stream_wrapper`. The wrapper only exposes the ports below;
all logic is inside the block design.

### PORTS
| port name | `input` / `output` | additional config |
| --- | --- | --- |
| clk | `input` | 100 MHz board clock |
| rstn | `input` | active low |
| sw_mode[3:0] | `input` | SW3–SW0, display mode and grayscale source |
| higher_up_tresh | `input` | BTN2, threshold up |
| lower_down_tresh | `input` | BTN3, threshold down |
| cam_xclk | `output` | 25 MHz, OV7670 master clock |
| cam_pclk | `input` | 25 MHz, OV7670 pixel clock |
| cam_d[7:0] | `input` | OV7670 pixel data |
| cam_vsync | `input` | OV7670 frame sync |
| cam_href | `input` | OV7670 line valid |
| cam_rst | `output` | active low, OV7670 reset |
| cam_pwdn | `output` | OV7670 power down |
| cam_scl | `output` | SCCB clock (internal pull-up) |
| cam_sda | `inout` | SCCB data (internal pull-up) |
| vga_r[3:0] | `output` | VGA red |
| vga_g[3:0] | `output` | VGA green |
| vga_b[3:0] | `output` | VGA blue |
| vga_hs | `output` | VGA horizontal sync |
| vga_vs | `output` | VGA vertical sync |
| calib_done | `output` | LD4, DDR3 calibration done |
| dbg_use_buff_a | `output` | LD5, reading buffer A |
| dbg_use_buff_b | `output` | LD6, reading buffer B |
| ddr3_sdram | interface | DDR3 SDRAM pins, Arty A7-100 board preset |

#### CONNECTIONS

**`util_ds_buf`**
| input name | from |
| -- | --- |
| BUFG_I | port `clk` |

| output name | to |
| -- | --- |
| BUFG_O | `clk_wiz` clk_in1, `mig_7series` sys_clk_i |

**`clk_wiz`**
| input name | from |
| -- | --- |
| clk_in1 | `util_ds_buf` BUFG_O |
| resetn | port `rstn` |

| output name | to |
| -- | --- |
| clk_out1 (200 MHz) | `mig_7series` clk_ref_i |
| clk_out2 (25 MHz) | port `cam_xclk` |
| clk_out3 (25 MHz) | `read_data_path_processed` vga_clk |
| locked | not connected |

**`mig_7series`**
| input name | from |
| -- | --- |
| sys_clk_i | `util_ds_buf` BUFG_O |
| clk_ref_i | `clk_wiz` clk_out1 |
| sys_rst | port `rstn` |
| aresetn | `proc_sys_reset` peripheral_aresetn |
| S_AXI | `smartconnect` M00_AXI |

| output name | to |
| -- | --- |
| ui_clk (≈81.25 MHz) | `proc_sys_reset` slowest_sync_clk, `smartconnect` aclk, `jtag_axi` aclk, `write_data_path` aclk, `read_data_path_processed` aclk, `frame_manager` aclk |
| ui_clk_sync_rst | `proc_sys_reset` ext_reset_in |
| mmcm_locked | `proc_sys_reset` dcm_locked |
| init_calib_complete | port `calib_done`, `write_data_path`, `read_data_path_processed`, `frame_manager` init_calib_complete |
| DDR3 | port `ddr3_sdram` |

**`proc_sys_reset`**
| input name | from |
| -- | --- |
| slowest_sync_clk | `mig_7series` ui_clk |
| ext_reset_in | `mig_7series` ui_clk_sync_rst |
| dcm_locked | `mig_7series` mmcm_locked |
| aux_reset_in | constant `1` (default) |
| mb_debug_sys_rst | constant `0` (default) |

| output name | to |
| -- | --- |
| peripheral_aresetn | `mig_7series`, `smartconnect`, `jtag_axi`, `write_data_path`, `read_data_path_processed`, `frame_manager` aresetn |

**`smartconnect`** (3 slave interfaces, 1 master interface)
| input name | from |
| -- | --- |
| aclk | `mig_7series` ui_clk |
| aresetn | `proc_sys_reset` peripheral_aresetn |
| S00_AXI | `write_data_path` m_axi |
| S01_AXI | `read_data_path_processed` m_axi |
| S02_AXI | `jtag_axi` M_AXI |

| output name | to |
| -- | --- |
| M00_AXI | `mig_7series` S_AXI |

**`jtag_axi`**
| input name | from |
| -- | --- |
| aclk | `mig_7series` ui_clk |
| aresetn | `proc_sys_reset` peripheral_aresetn |

| output name | to |
| -- | --- |
| M_AXI | `smartconnect` S02_AXI |

**`write_data_path`** (RTL module)
| input name | from |
| -- | --- |
| clk | port `clk` (100 MHz, camera configuration clock) |
| sys_rstn | port `rstn` |
| aclk | `mig_7series` ui_clk |
| aresetn | `proc_sys_reset` peripheral_aresetn |
| init_calib_complete | `mig_7series` init_calib_complete |
| frame_executor_cmd[1:0] | `frame_manager` write_frame_executor_cmd |
| cam_pclk | port `cam_pclk` |
| cam_d[7:0] | port `cam_d` |
| cam_vsync | port `cam_vsync` |
| cam_href | port `cam_href` |

| output name | to |
| -- | --- |
| m_axi | `smartconnect` S00_AXI |
| done_one_frame | `frame_manager` write_ov7670_frame_done_one_frame |
| frame_is_valid | `frame_manager` write_ov7670_frame_frame_is_valid |
| cam_rst | port `cam_rst` |
| cam_pwdn | port `cam_pwdn` |
| cam_scl | port `cam_scl` |
| cam_sda (`inout`) | port `cam_sda` |

**`read_data_path_processed`** (RTL module)
| input name | from |
| -- | --- |
| aclk | `mig_7series` ui_clk |
| aresetn | `proc_sys_reset` peripheral_aresetn |
| vga_clk | `clk_wiz` clk_out3 |
| sys_rstn | port `rstn` |
| init_calib_complete | `mig_7series` init_calib_complete |
| frame_executor_cmd[1:0] | `frame_manager` read_frame_executor_cmd |
| sw_mode[3:0] | port `sw_mode` |
| higher_up_tresh | port `higher_up_tresh` |
| lower_down_tresh | port `lower_down_tresh` |

| output name | to |
| -- | --- |
| m_axi | `smartconnect` S01_AXI |
| done_one_frame | `frame_manager` read_ddr_frame_done_one_frame |
| frame_is_valid | `frame_manager` read_ddr_frame_frame_is_valid |
| busy | `frame_manager` read_ddr_frame_busy |
| fault | `frame_manager` read_ddr_frame_fault |
| fault_code[3:0] | `frame_manager` read_ddr_frame_fault_code |
| vga_r[3:0], vga_g[3:0], vga_b[3:0] | ports `vga_r`, `vga_g`, `vga_b` |
| vga_hs, vga_vs | ports `vga_hs`, `vga_vs` |
| cnn_dout[7:0], cnn_valid_out | not connected (28 × 28 downsampled ROI) |
| processing_error | not connected |
| underflow | not connected |

**`frame_manager`** (RTL module)
| input name | from |
| -- | --- |
| aclk | `mig_7series` ui_clk |
| aresetn | `proc_sys_reset` peripheral_aresetn |
| init_calib_complete | `mig_7series` init_calib_complete |
| write_ov7670_frame_done_one_frame | `write_data_path` done_one_frame |
| write_ov7670_frame_frame_is_valid | `write_data_path` frame_is_valid |
| read_ddr_frame_done_one_frame | `read_data_path_processed` done_one_frame |
| read_ddr_frame_frame_is_valid | `read_data_path_processed` frame_is_valid |
| read_ddr_frame_busy | `read_data_path_processed` busy |
| read_ddr_frame_fault | `read_data_path_processed` fault |
| read_ddr_frame_fault_code[3:0] | `read_data_path_processed` fault_code |

| output name | to |
| -- | --- |
| write_frame_executor_cmd[1:0] | `write_data_path` frame_executor_cmd |
| read_frame_executor_cmd[1:0] | `read_data_path_processed` frame_executor_cmd |
| dbg_use_buff_a | port `dbg_use_buff_a` |
| dbg_use_buff_b | port `dbg_use_buff_b` |

#### CLOCK DOMAINS
| clock | source | used by |
| --- | --- | --- |
| clk (100 MHz) | port `clk` | `util_ds_buf`, `write_data_path` clk (SCCB camera configuration) |
| clk_out1 (200 MHz) | `clk_wiz` | `mig_7series` reference clock (IDELAYCTRL) |
| clk_out2 (25 MHz) | `clk_wiz` | port `cam_xclk` |
| clk_out3 (25 MHz) | `clk_wiz` | `read_data_path_processed` VGA side, frame processor and threshold buttons |
| cam_pclk (25 MHz) | port `cam_pclk` | `write_data_path` camera capture side |
| ui_clk (≈81.25 MHz) | `mig_7series` | all AXI logic: `smartconnect`, `jtag_axi`, `frame_manager` and the AXI side of both data paths |
