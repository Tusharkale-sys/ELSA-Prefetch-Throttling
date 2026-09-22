#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO/scripts/run/common.sh"

elsa_require_env
elsa_common_args

WARMUP=10000000
SIMULATION=50000000
MANIFEST="$REPO/results/broad24/workloads_24.tsv"
OUT="${ELSA_RESULT_DIR:-$REPO/run-results/canonical_broad24}"

mkdir -p "$OUT"

cd "$REPO"

tail -n +2 "$MANIFEST" |
while IFS="$(printf '\t')" read -r IDX WORKLOAD TRACE_FILE TRACE_SHA
do
    TRACE="$TRACE_DIR/$TRACE_FILE"

    [ -f "$TRACE" ] || {
        echo "ERROR: missing trace: $TRACE"
        exit 1
    }

    ACTUAL_SHA="$(shasum -a 256 "$TRACE" | awk '{print $1}')"

    [ "$ACTUAL_SHA" = "$TRACE_SHA" ] || {
        echo "ERROR: trace SHA mismatch: $WORKLOAD"
        exit 1
    }

    for ARM in A0 A1 A2
    do
        unset SBERTI_RL SBERTI_EPOCH SBERTI_FIXED_CAP || true

        case "$ARM" in
            A0)
                L1="berti"
                L2="none"
                ;;
            A1)
                L1="none"
                L2="sberti"
                export SBERTI_RL=0
                export SBERTI_EPOCH=1024
                ;;
            A2)
                L1="none"
                L2="sberti"
                export SBERTI_RL=1
                export SBERTI_EPOCH=1024
                ;;
        esac

        LOG="$OUT/${IDX}__${WORKLOAD}__${ARM}.log"

        echo "RUN workload=$WORKLOAD arm=$ARM"

        "$CHAMPSIM_BIN" \
            --warmup_instructions="$WARMUP" \
            --simulation_instructions="$SIMULATION" \
            "${COMMON_ARGS[@]}" \
            "--l1d_prefetcher_types=$L1" \
            "--l2c_prefetcher_types=$L2" \
            -traces "$TRACE" \
            > "$LOG" 2>&1
    done
done
