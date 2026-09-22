#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO/scripts/run/common.sh"

: "${E32_CHAMPSIM_BIN:?Set E32_CHAMPSIM_BIN to the compatible E32/128 ChampSim binary}"
: "${TRACE_DIR:?Set TRACE_DIR to the directory containing the required traces}"

[ -x "$E32_CHAMPSIM_BIN" ] || {
    echo "ERROR: E32_CHAMPSIM_BIN is not executable"
    exit 1
}

[ -d "$TRACE_DIR" ] || {
    echo "ERROR: TRACE_DIR does not exist"
    exit 1
}

elsa_common_args

WARMUP=10000000
SIMULATION=50000000
MANIFEST="$REPO/results/broad24/workloads_24.tsv"
OUT="${ELSA_RESULT_DIR:-$REPO/run-results/e32_128}"

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

    for ARM in A0 A1 A2 F1
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
            F1)
                L1="none"
                L2="sberti"
                export SBERTI_RL=0
                export SBERTI_EPOCH=1024
                export SBERTI_FIXED_CAP=1
                ;;
        esac

        LOG="$OUT/${IDX}__${WORKLOAD}__${ARM}.log"

        echo "RUN workload=$WORKLOAD arm=$ARM"

        "$E32_CHAMPSIM_BIN" \
            --warmup_instructions="$WARMUP" \
            --simulation_instructions="$SIMULATION" \
            "${COMMON_ARGS[@]}" \
            "--l1d_prefetcher_types=$L1" \
            "--l2c_prefetcher_types=$L2" \
            -traces "$TRACE" \
            > "$LOG" 2>&1

        grep -q '^dram_io_freq 400$' "$LOG"
        grep -q '^l1d_size 32$' "$LOG"
        grep -q '^l1d_set 64$' "$LOG"
        grep -q '^l1d_way 8$' "$LOG"
        grep -q '^l1d_latency 5$' "$LOG"
        grep -q '^l2c_size 128$' "$LOG"
        grep -q '^l2c_set 128$' "$LOG"
        grep -q '^l2c_way 16$' "$LOG"
        grep -q '^l2c_latency 10$' "$LOG"
    done
done
