# Processor System Reset (proc_sys_reset v5.0)

## Important Setup

No custom setup. This IP uses the **default settings**.

## Function

- Generates clean, synchronized reset signals for one clock domain.
- Synchronizes an asynchronous external reset (`ext_reset_in`) to
  `slowest_sync_clk`, so reset assertion and de-assertion are glitch-free and
  aligned to that clock.
- Holds the reset active until the clock source is stable, using the
  `dcm_locked` input (e.g. a `locked` signal from an MMCM/PLL).
- Provides several reset outputs with the correct polarity for each consumer,
  for example:
  - `interconnect_aresetn`: active-low reset for AXI interconnect
    (SmartConnect),
  - `peripheral_aresetn`: active-low reset for AXI peripherals and masters,
  - `peripheral_reset`: active-high reset.

## Connection

### Input Ports

_TBD_

### Output Ports

_TBD_
