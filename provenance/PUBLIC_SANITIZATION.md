# Public provenance sanitization

The canonical Final617 campaign remains the frozen local checkpoint used for the paper.

Some original provenance files contain machine-local absolute filesystem paths. Those paths are not scientifically meaningful and are not required to audit the reported results.

For the public repository, files containing such paths are published as `_PUBLIC` projections. Only machine-local absolute path strings are replaced with neutral `<LOCAL_PATH>/...` identifiers.

The public projections retain the scientific metadata carried by those records, including job identifiers, workload/arm labels, seeds, trace filenames where present, and cryptographic hashes.

No IPC value, experimental result, controller parameter, hardware result, seed, or hash value is modified by this sanitization.

The original frozen Final617 closure manifest was independently verified before preparation of this public artifact:

`a0820a05de5730c64b27a9fe558cd241e2cc2a3882fa4b455660f342ae7cd24c`

## Files projected for public release

- `results/final617/CLOSURE.txt` → `results/final617/CLOSURE_PUBLIC.txt`
- `results/final617/FINAL_617_JOB_MATRIX.tsv` → `results/final617/FINAL_617_JOB_MATRIX_PUBLIC.tsv`
- `provenance/final617/BINARY_PROVENANCE.tsv` → `provenance/final617/BINARY_PROVENANCE_PUBLIC.tsv`
- `provenance/final617/LOG_FILES_SHA256.txt` → `provenance/final617/LOG_FILES_SHA256_PUBLIC.txt`
- `provenance/final617/STATUS_FILES_SHA256.txt` → `provenance/final617/STATUS_FILES_SHA256_PUBLIC.txt`
- `provenance/final617/TRACE_PROVENANCE.tsv` → `provenance/final617/TRACE_PROVENANCE_PUBLIC.tsv`

The frozen local originals remain the canonical provenance authority; the `_PUBLIC` files are disclosure-safe views intended for repository inspection.
