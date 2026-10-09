# Reproducibility status

**Current public-artifact target:** Final617 + final H7 static-decode realization.

## Synchronized components

- final repaired NEW5 software,
- compact Final617 job/closure/provenance records,
- canonical compact 617-execution IPC ledger,
- final H7 RTL,
- compact final-H7 evidence.

## Intentionally not bundled

- benchmark traces whose redistribution is restricted,
- unrelated thesis/research projects,
- mutable development checkpoints,
- large duplicate raw logs when their frozen hashes/provenance are sufficient for audit.

## Integrity

Run:

```bash
bash scripts/verify_artifact.sh
```

No simulation is launched by that script.
