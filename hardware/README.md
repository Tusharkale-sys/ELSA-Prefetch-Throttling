# ELSA hardware realization

The canonical RTL for the current paper is:

`hardware/rtl/elsa_controller.sv`

It corresponds to the frozen **H7 static-decode** realization of NEW5.

## Frozen result

| Metric | Final H7 |
|---|---:|
| Routed Fmax | 33.88 MHz |
| Speedup vs original NEW5 RTL | 11.723× |
| Combinational cells | 20,712 |
| Flip-flops | 8,623 |
| Multipliers | 11 |
| BRAM | 0 |
| Replay mismatches | 0 / 256 |
| Action-4 → degree-0 coverage | 194 |
| Maximum update latency | 111 cycles |
| 100 MHz target | **Not met** |

The 100 MHz miss is a retained negative result. The resource and timing values are specific to the frozen FPGA flow and must not be interpreted as ASIC area, ASIC timing, or measured energy.

See `results/hardware/final_h7/` for the compact frozen evidence and `provenance/hardware/` for its manifest.
