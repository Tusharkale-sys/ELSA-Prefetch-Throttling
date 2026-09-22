# Portable Runner Contract

The historical frozen runners are not published verbatim because they contain machine-specific absolute paths.

Public reproduction scripts must instead accept the simulator and trace locations from the user environment.

## Common scientific settings

- warm-up instructions: 10000000
- measured instructions: 50000000
- DRAM I/O frequency: 400
- ELSA epoch: SBERTI_EPOCH=1024
- traces are not bundled in this repository

## Canonical Broad24 arms

- A0: native L1D Berti
- A1: L2 sBerti, SBERTI_RL=0
- A2: L2 sBerti, SBERTI_RL=1, SBERTI_EPOCH=1024

## Fixed-cap arms

- F1: SBERTI_FIXED_CAP=1
- F2: SBERTI_FIXED_CAP=2
- F4: SBERTI_FIXED_CAP=4
- F8: SBERTI_FIXED_CAP=8
- SARSA disabled for fixed-cap experiments

## E32/128 configuration

- L1D: 32 KiB, 64 sets, 8 ways, latency 5
- L2: 128 KiB, 128 sets, 16 ways, latency 10

Final public runners must use relative repository paths and externally supplied CHAMPSIM_BIN and TRACE_DIR values.
