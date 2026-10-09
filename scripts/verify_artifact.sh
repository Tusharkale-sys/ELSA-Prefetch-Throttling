#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

check_sha() {
  expected="$1"
  file="$2"
  [ -f "$file" ] || fail "missing $file"
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || fail "$file SHA-256 mismatch: $actual"
  pass "$file SHA-256"
}

check_sha f55b6e20cd94fcde061bdaa44aeb01441f78c1a856f29ba5d44f59e1000bd62f src/inc/sberti.h
check_sha 18ae886d15bbd4f5aa0f063d6d128553abc7520b82916d559fe0ba52b5788758 src/inc/cache.h
check_sha 803a2cf970babc628f569d3a9ae5b7597cd9f54a68b5e7fe74950e1f38d15ff5 src/prefetcher/sberti.cc
check_sha 1630a0a80468d807117de4f9fcc850e56261997ecbf95bc666ea122bbd3ab308 src/prefetcher/l2c_prefetcher.cc
check_sha 0003a4dc113f485c2a97d7d3477e76895c61c16d6000e0a7cdb1e01cc3d24903 src/prefetcher/llc_prefetcher.cc
check_sha 4afafb154552a4e462639e7f4b6e3db073a016a48b018c4dba6a23a4fd8bdafc src/cache.cc
check_sha d8471aec615ad6e76e40c78a43a616a88e2952d1a6244dda2500ec6686962605 results/final617/ELSA_FINAL617_raw_ipc.csv

grep -Eq 'SB_RL_NUM_ACTIONS[[:space:]]+5' src/inc/sberti.h || fail "NEW5 action-count contract"
grep -Eq 'deg_map\[5\][[:space:]]*=[[:space:]]*\{1,[[:space:]]*2,[[:space:]]*4,[[:space:]]*8,[[:space:]]*0\}' src/prefetcher/sberti.cc || fail "NEW5 physical action map"
pass "NEW5 five-action software contract"

grep -Eq 'NUM_ACTIONS[[:space:]]*=[[:space:]]*5' hardware/rtl/elsa_controller.sv || fail "H7 five-action RTL contract"
grep -Eq 'degree_from_action[[:space:]]*=[[:space:]]*4.d0' hardware/rtl/elsa_controller.sv || fail "H7 OFF decode"
pass "H7 five-action RTL contract"

rows="$(awk 'END{print NR-1}' results/final617/ELSA_FINAL617_raw_ipc.csv)"
[ "$rows" = "617" ] || fail "Final617 ledger rows=$rows"
pass "Final617 compact ledger has 617 executions"

awk -F, 'NR==2{first=$1} NR>1{last=$1} END{exit !(first==1 && last==617)}' results/final617/ELSA_FINAL617_raw_ipc.csv || fail "Final617 sequence not 1..617"
pass "Final617 sequence endpoints"

grep -F $'FINAL_H7_FMAX_MHZ\t33.88' results/hardware/final_h7/FINAL_HARDWARE_SUMMARY.tsv >/dev/null || fail "H7 Fmax marker"
grep -F $'TARGET_100MHZ_PASS\tNO' results/hardware/final_h7/FINAL_HARDWARE_SUMMARY.tsv >/dev/null || fail "H7 100MHz boundary marker"
pass "H7 final result markers"

echo
echo "ELSA_ARTIFACT_VERIFY=PASS"
echo "SIMULATION_RUN=NO"
