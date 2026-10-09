# ELSA final-artifact provenance

The current repository release is synchronized to the repaired NEW5 software and the frozen Final617 / H7 evidence used by the current ELSA paper.

## Final repaired software identities

| File | SHA-256 |
|---|---|
| `src/inc/sberti.h` | `f55b6e20cd94fcde061bdaa44aeb01441f78c1a856f29ba5d44f59e1000bd62f` |
| `src/inc/cache.h` | `18ae886d15bbd4f5aa0f063d6d128553abc7520b82916d559fe0ba52b5788758` |
| `src/prefetcher/sberti.cc` | `803a2cf970babc628f569d3a9ae5b7597cd9f54a68b5e7fe74950e1f38d15ff5` |
| `src/prefetcher/l2c_prefetcher.cc` | `1630a0a80468d807117de4f9fcc850e56261997ecbf95bc666ea122bbd3ab308` |
| `src/prefetcher/llc_prefetcher.cc` | `0003a4dc113f485c2a97d7d3477e76895c61c16d6000e0a7cdb1e01cc3d24903` |
| `src/cache.cc` | `4afafb154552a4e462639e7f4b6e3db073a016a48b018c4dba6a23a4fd8bdafc` |

The frozen scientific simulator binary used for Final617 had SHA-256:

`628ee00554f51cd2cbca1880374a6c5fdabb58292143ad524953519f9525455a`

The public repository does not need to redistribute that binary to preserve software identity; the binary provenance record is included under `provenance/final617/`.

## Final617 closure

The final campaign closure is represented by `provenance/final617/CHECKPOINT_MANIFEST.sha256` together with the trace/binary/status/log provenance files and the compact IPC ledger in `results/final617/`.

## Hardware closure

The canonical public RTL is the frozen H7 static-decode design. Its compact evidence and manifest are retained under `results/hardware/final_h7/` and `provenance/hardware/`.
