# Verifications: OV7670 Frame Capture from DDR3

## Function

The Tcl script reads the frames stored in `buff_0` and `buff_1` in DDR3 back
to the PC through the **JTAG to AXI Master**, and the notebook shows them as
images. The script only sends AXI READ transactions, so it does not disturb
the ping-pong scheme: the camera keeps writing, the frame manager keeps
swapping the buffers and the VGA output keeps running while the frames are
read.

| File name | Description |
| --- | --- |
| [capture_frame.tcl](capture_frame.tcl) | Vivado Tcl script that reads `buff_0` and `buff_1` from DDR3 and saves them as `.hex` files |
| [ov7670_capture.ipynb](ov7670_capture.ipynb) | Jupyter notebook that converts the `.hex` files to images, shows them and saves them as PNG |
| `buff_0_axi32.hex` | Raw dump of `buff_0` (buffer A), made by `capture_frame.tcl` |
| `buff_1_axi32.hex` | Raw dump of `buff_1` (buffer B), made by `capture_frame.tcl` |
| `buff_0_rgb444.png` | Image of `buff_0`, made by `ov7670_capture.ipynb` |
| `buff_1_rgb444.png` | Image of `buff_1`, made by `ov7670_capture.ipynb` |

## How to Run

### 1. Prepare the board

Program the bitstream from the Vivado Hardware Manager, then check the LEDs:

- **LD4** (`calib_done`) stays on: the DDR3 calibration is done.
- **LD5** (`dbg_use_buff_a`) and **LD6** (`dbg_use_buff_b`) blink
  alternately: the frame manager is swapping the ping-pong buffers, so both
  buffers hold frames.

### 2. Dump the frame buffers

In the **Tcl Console** of the Hardware Manager, source the script. No
arguments are needed:

```tcl
source path/verifications/capture_frame.tcl
```

The script reads `buff_0` and then `buff_1`, prints its progress and ends
with `DONE`:

```text
JTAG AXI: hw_axi_1
LIVE DUMP: the writer is not paused; an image may mix several frames.
buff_0: 0x00000000, 153600 words -> .../verifications/buff_0_axi32.hex
buff_0: 25600/153600 words (17%)
...
buff_1: 0x00096000, 153600 words -> .../verifications/buff_1_axi32.hex
...
DONE: open ov7670_capture.ipynb and Run All.
```

Each buffer takes about 15 s over JTAG.

### 3. Show the images

Open [ov7670_capture.ipynb](ov7670_capture.ipynb) and click **Run All**. The
notebook finds the `.hex` files by itself when it is opened from the
`video-streaming` root or from this folder. It shows both buffers side by
side and saves the PNG files. The kernel needs `numpy`, `matplotlib`,
`Pillow` and `IPython`.

## Output Files

All output files are written to this folder, next to `capture_frame.tcl`,
whatever the working directory of Vivado is. The file names are fixed, so
every new capture overwrites the previous one. While a buffer is being read,
its dump is written to `buff_<id>_axi32.hex.partial` and renamed only after
the last word, so a failed dump never replaces a complete file.

## Data Format

`buff_0` starts at `0x0000_0000` and `buff_1` at `0x0009_6000`, matching
`BASE_0` and `BASE_1` in [write_frame_exec.v](../rtl/write_frame_exec.v) and
[read_frame_exec.v](../rtl/read_frame_exec.v). Each buffer holds one
640 × 480 frame of 614,400 bytes.

Each `.hex` file has one 32-bit word per line, written as 8 hex digits in
ascending address order, so one buffer is 153,600 lines. Every word holds two
pixels: the **low halfword is the earlier pixel**, followed by the high
halfword.

```text
word = 0x0RGB_0RGB
word = px[n+1]_px[n]
```

### Pixel

Each pixel is RGB444 stored in a 16-bit halfword as `0x0RGB`: 4 bits each for
red, green and blue, and a top nibble of padding that is always `0`. The
notebook expands every 4-bit channel to 8 bits by multiplying it by 17
(`0 → 0`, `15 → 255`), so the PNG files are standard RGB888 images.

## How the Tcl Reads DDR3

1. Finds the JTAG to AXI core with `get_hw_axis` (for example `hw_axi_1`).
2. Splits each buffer into bursts of 128 words and sends each one as an AXI4
   INCR read with `create_hw_axi_txn -type READ` and `run_hw_axi`. No burst
   crosses a 4 KiB boundary, as AXI4 requires.
3. Checks every burst: `RRESP` must be `OKAY` and the returned `DATA` must
   have the expected length.
4. Reverses the words of each burst, because Vivado 2025.2 returns burst
   `DATA` with the highest address first. The file is therefore always in
   ascending address order.
5. Writes the words to the `.hex` file and repeats until the buffer is
   complete, first for `buff_0` and then for `buff_1`.

The script never writes to DDR3 and does not reset the JTAG to AXI core, the
MIG or the camera. Because the camera keeps writing during the dump, which is
much slower than one camera frame, one image can contain parts of several
frames, and the two buffers are not captured at the same moment.
