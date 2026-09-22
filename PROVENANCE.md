# Provenance

This repository is a cleaned public artifact for:

**ELSA: Lightweight SARSA Prefetch Throttling for Resource-Constrained Embedded Systems**

## Contribution boundary

ELSA does not replace sBerti candidate-address generation.

It controls the maximum degree on the ELSA-controlled SmartStride path
using actions `{1, 2, 4, 8}`.

The primary comparison is:

- A1: sBerti with SARSA disabled
- A2: the same sBerti implementation with ELSA enabled

Native Berti is retained as an architectural reference rather than a
single-variable ELSA baseline.

## Upstream

Exact upstream Berti provenance is recorded in:

`provenance/UPSTREAM.md`

## Frozen-source integrity

The published controller source hashes are recorded in:

`provenance/SOURCE_SHA256.txt`

Public-release path sanitization is documented in:

`provenance/PUBLIC_SANITIZATION.md`

The original frozen research artifacts were not modified during
construction of this public release.
