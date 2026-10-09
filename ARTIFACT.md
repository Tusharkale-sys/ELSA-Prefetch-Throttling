# ELSA artifact map

This file maps the final paper claims to the compact public artifact. The purpose is auditability, not to re-run the entire 617-execution campaign by default.

## Canonical software

The final repaired NEW5 software is represented by:

- `src/inc/sberti.h`
- `src/inc/cache.h`
- `src/prefetcher/sberti.cc`
- `src/prefetcher/l2c_prefetcher.cc`
- `src/prefetcher/llc_prefetcher.cc`
- `src/cache.cc`

The scientific controller exposes five physical actions through the map `[1,2,4,8,0]`, where the last action is local controlled OFF.

## Canonical Final617 evidence

`results/final617/ELSA_FINAL617_raw_ipc.csv` is the compact IPC ledger for all 617 frozen arm-unit executions. The campaign is partitioned into distinct blocks rather than treated as one inferential sample:

| Block | Executions |
|---|---:|
| MASTER14 | 336 |
| E32/128 | 72 |
| Prospective72 | 72 |
| T5_112 | 112 |
| HELDOUT25 | 25 |
| **Total** | **617** |

Campaign identity and trace/binary provenance are in `provenance/final617/`.

## Primary paper results

The compact ledger and frozen analysis support the following headline values:

- NEW5/A1: +4.0955% GM IPC, median +0.3285%, 20/1/3.
- NEW5/OLD4: +0.3054% GM IPC, median -0.0026%, 7/4/13, exact sign p=0.263.
- NEW5/F1: +0.2502%.
- NEW5/A0: -2.1203%, 8/0/16.
- Prospective MCF: +7.2278%, 5/0/0.
- Prospective LBM: +0.0108%.

The per-workload hindsight fixed-action oracle remains 0.6718% ahead of NEW5 on MASTER14. This negative boundary is intentional and preserved.

## Hardware

The canonical RTL is `hardware/rtl/elsa_controller.sv`, copied from the frozen H7 static-decode closure.

Compact hardware evidence is in `results/hardware/final_h7/` and provenance is in `provenance/hardware/`.

The final design reports 33.88 MHz routed Fmax. The preregistered 100 MHz target is not met.

## What is not redistributed

Benchmark traces are not redistributed when licensing or redistribution terms do not permit it. The repository instead includes trace identities/provenance needed to reconstruct the evaluation environment lawfully.

Large raw simulator logs are not duplicated in the compact public artifact because the frozen closure already records their identities and hashes. The compact IPC ledger is provided for direct numerical audit.
