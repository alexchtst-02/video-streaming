# Synthesis and Implementation: Processed Frame

Implementation results of the [PROCESSING-VIDEO-STREAM](../../../ip-block-design/PROCESSING-VIDEO-STREAM/INFO.md) block design
(`design_processed_stream`, top `design_processed_stream_wrapper`) on the Arty A7-100 (`xc7a100tcsg324-1`), from
Vivado 2025.2 runs `synth_2` and `impl_2` with the constraint file
[base.xdc](../../../xdc/processed_frame/base.xdc).

## Reports

| File | Description |
| --- | --- |
| [design_processed_stream_wrapper_clock_utilization_routed.rpt](design_processed_stream_wrapper_clock_utilization_routed.rpt) | Post-route clock resources (BUFG, MMCM, PLL) |
| [design_processed_stream_wrapper_power_routed.rpt](design_processed_stream_wrapper_power_routed.rpt) | Post-route on-chip power estimate |
| [design_processed_stream_wrapper_timing_summary_routed.rpt](design_processed_stream_wrapper_timing_summary_routed.rpt) | Post-route timing summary (STA) |
| [design_processed_stream_wrapper_utilization_placed.rpt](design_processed_stream_wrapper_utilization_placed.rpt) | Post-placement resource utilization |
| [design_processed_stream_wrapper_utilization_synth.rpt](design_processed_stream_wrapper_utilization_synth.rpt) | Post-synthesis resource utilization |

The timing summary is generated with `report_timing_summary
-no_detailed_paths` from the routed checkpoint of `impl_2`, so it gives the
same numbers as the full report of the run without listing every path.

## Results

### STA

| WNS | TNS | WHS | THS | WPWS | TPWS |
| --- | --- | --- | --- | --- | --- |
| 1.316 ns | 0.000 ns | 0.008 ns | 0.000 ns | 0.206 ns | 0.000 ns |

All user-specified timing constraints are met, with 0 failing endpoints.
This covers the 100 MHz system clock, the 200 MHz MIG reference clock, the
25 MHz camera and VGA clocks and the ≈81.25 MHz MIG `ui_clk`.

### Resource Utilization

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| LUT | 12020 | 63400 | 18.96% |
| FF | 14348 | 126800 | 11.32% |
| BRAM (tile) | 5.5 | 135 | 4.07% |
| DSP | 0 | 240 | 0.00% |
| IO | 89 | 210 | 42.38% |
| BUFG | 9 | 32 | 28.13% |

### On-Chip Power

| Category | Power | Percentage |
| --- | ---: | ---: |
| Dynamic power | 0.789 W | 88% |
| &emsp;Clocks | 0.048 W | 6% |
| &emsp;Signals | 0.023 W | 3% |
| &emsp;Logic | 0.021 W | 3% |
| &emsp;BRAM | 0.002 W | <1% |
| &emsp;DSP | 0.000 W | 0% |
| &emsp;MMCM | 0.193 W | 24% |
| &emsp;PLL | 0.115 W | 15% |
| &emsp;PHASER | 0.110 W | 14% |
| &emsp;XADC | 0.004 W | <1% |
| &emsp;I/O | 0.273 W | 35% |
| Device static power | 0.105 W | 12% |
| Total On-Chip Power | 0.895 W | 100% |

Dynamic power and device static power are percentages of the total on-chip
power. The indented items are percentages of the dynamic power. The junction
temperature is 29.1 °C. Vivado rates the confidence level of this estimate as
**Low** because no switching activity from simulation was provided.

### Demo

_TBD_
