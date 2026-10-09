# Reproducibility guide

## Fast integrity check

From the repository root:

```bash
bash scripts/verify_artifact.sh
```

This is intentionally a non-simulation check. It verifies the final source identities, NEW5 action contract, compact Final617 ledger, and final H7 markers.

## Full campaign structure

Final617 contains five frozen blocks:

1. MASTER14 — 336 executions.
2. E32/128 — 72 executions.
3. Prospective72 — 72 executions.
4. T5_112 — 112 executions.
5. HELDOUT25 — 25 executions.

Total: 617 arm-unit executions.

The blocks have different scientific purposes and must remain separate in inference and interpretation.

## Traces

Benchmark traces are not included when redistribution terms do not permit public redistribution. See `provenance/final617/TRACE_PROVENANCE_PUBLIC.tsv` for the trace identities used by the frozen campaign.

## Frozen-evidence rule

Final617 is closed. The public artifact should not silently replace, selectively rerun, or tune individual frozen results. Any future extension should be clearly labeled as a new experiment rather than folded into Final617.
