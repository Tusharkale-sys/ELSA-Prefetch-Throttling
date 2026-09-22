# ELSA

**ELSA: Lightweight SARSA Prefetch Throttling for Resource-Constrained Embedded Systems**

This repository contains the reproducibility artifact for the ELSA research work.

## Overview

ELSA adds a lightweight SARSA-based runtime controller to sBerti for adaptive prefetch aggressiveness control.

The controller chooses among four prefetch-depth caps:

- 1
- 2
- 4
- 8

The evaluated controller uses:

- 8 states
- 4 actions
- alpha = 0.5
- gamma = 0.6
- epsilon = 0
- experiment epoch = 1024 L2 accesses

Paper experiments explicitly use `SBERTI_EPOCH=1024`.

## Contribution Boundary

Berti is prior work.

sBerti provides the underlying prefetch-generation mechanism used in this research environment.

The ELSA contribution is the lightweight SARSA-based runtime aggressiveness controller, its evaluation, and its hardware realization.

## Repository Layout

```text
src/
  inc/sberti.h
  prefetcher/sberti.cc
hardware/
  rtl/elsa_controller.sv
config/
scripts/
results/
docs/
provenance/
```

## Reproducibility

The final artifact will provide experiment commands, configurations, analysis scripts, compact frozen results, and hardware validation instructions.

Workload traces that cannot legally be redistributed will not be included; instructions for obtaining them will be documented instead.

## Isolation

This repository contains only material required for the ELSA artifact.

Unrelated research projects, private thesis material, third-party toolchains, and unrelated experimental files are intentionally excluded.

## License

See `LICENSE`.

The upstream Berti artifact used by this work is licensed under GNU GPL v3.
