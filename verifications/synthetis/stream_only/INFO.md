# Synthesis and Implementation: Stream Only

Implementation results of the [VIDEO-STREAM](../../../ip-block-design/VIDEO-STREAM/INFO.md) block design
(`design_stream`, top `design_stream_wrapper`) on the Arty A7-100 (`xc7a100tcsg324-1`), from
Vivado 2025.2 runs `synth_1` and `impl_1` with the constraint file
[base.xdc](../../../xdc/stream_only/base.xdc).

## Reports

| File | Description |
| --- | --- |
| [design_stream_wrapper_clock_utilization_routed.rpt](design_stream_wrapper_clock_utilization_routed.rpt) | Post-route clock resources (BUFG, MMCM, PLL) |
| [design_stream_wrapper_power_routed.rpt](design_stream_wrapper_power_routed.rpt) | Post-route on-chip power estimate |
| [design_stream_wrapper_timing_summary_routed.rpt](design_stream_wrapper_timing_summary_routed.rpt) | Post-route timing summary (STA) |
| [design_stream_wrapper_utilization_placed.rpt](design_stream_wrapper_utilization_placed.rpt) | Post-placement resource utilization |
| [design_stream_wrapper_utilization_synth.rpt](design_stream_wrapper_utilization_synth.rpt) | Post-synthesis resource utilization |

The timing summary is generated with `report_timing_summary
-no_detailed_paths` from the routed checkpoint of `impl_1`, so it gives the
same numbers as the full report of the run without listing every path.

## Results

### STA

| WNS | TNS | WHS | THS | WPWS | TPWS |
| --- | --- | --- | --- | --- | --- |
| 1.316 ns | 0.000 ns | 0.052 ns | 0.000 ns | 0.206 ns | 0.000 ns |

All user-specified timing constraints are met, with 0 failing endpoints.
This covers the 100 MHz system clock, the 200 MHz MIG reference clock, the
25 MHz camera and VGA clocks and the ≈81.25 MHz MIG `ui_clk`.

### Resource Utilization

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| LUT | 11232 | 63400 | 17.72% |
| FF | 13514 | 126800 | 10.66% |
| BRAM (tile) | 4.5 | 135 | 3.33% |
| DSP | 0 | 240 | 0.00% |
| IO | 83 | 210 | 39.52% |
| BUFG | 9 | 32 | 28.13% |

### On-Chip Power

| Category | Power | Percentage |
| --- | ---: | ---: |
| Dynamic power | 0.787 W | 88% |
| &emsp;Clocks | 0.047 W | 6% |
| &emsp;Signals | 0.022 W | 3% |
| &emsp;Logic | 0.020 W | 3% |
| &emsp;BRAM | 0.002 W | <1% |
| &emsp;DSP | 0.000 W | 0% |
| &emsp;MMCM | 0.193 W | 25% |
| &emsp;PLL | 0.115 W | 15% |
| &emsp;PHASER | 0.110 W | 14% |
| &emsp;XADC | 0.004 W | <1% |
| &emsp;I/O | 0.273 W | 35% |
| Device static power | 0.105 W | 12% |
| Total On-Chip Power | 0.893 W | 100% |

Dynamic power and device static power are percentages of the total on-chip
power. The indented items are percentages of the dynamic power. The junction
temperature is 29.1 °C. Vivado rates the confidence level of this estimate as
**Low** because no switching activity from simulation was provided.

### Demo

_TBD_
