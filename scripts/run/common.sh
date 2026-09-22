#!/usr/bin/env bash

elsa_require_env() {
    : "${CHAMPSIM_BIN:?Set CHAMPSIM_BIN to the compatible ChampSim binary}"
    : "${TRACE_DIR:?Set TRACE_DIR to the directory containing the required traces}"

    [ -x "$CHAMPSIM_BIN" ] || {
        echo "ERROR: CHAMPSIM_BIN is not executable: $CHAMPSIM_BIN"
        exit 1
    }

    [ -d "$TRACE_DIR" ] || {
        echo "ERROR: TRACE_DIR does not exist: $TRACE_DIR"
        exit 1
    }
}

elsa_common_args() {
    COMMON_ARGS=(
        "--llc_replacement_type=ship"
        "--config=config/nopref.ini"
        "--config=config/pythia.ini"
        "--l2c_prefetcher_force_prefetch_at_llc=true"
        "--rob_partition_size=64,128,320"
        "--rob_frontal_partition_ids=0"
        "--rob_dorsal_partition_ids=2"
        "--dram_io_freq=400"
        "--config=config/hermes_base.ini"
        "--config=config/ocp_hermes.ini"
        "--config=config/oogway_dev.ini"
        "--og_enable=false"
        "--og_multi_prefetcher_enable=false"
        "--og_prefetcher_level=2"
    )
}
