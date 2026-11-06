#!/usr/bin/env python3
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent

HASHES = {
    "src/elsa_controller_ref.sv":
        "f3db118d9494ec868df659fe5ffe72ff8478fa267ebee9ddd10337270e5391c2",
    "src/elsa_controller_opt_testname.sv":
        "d375bfa8b1dffaf70129a92491d869ea2c45dd4dea0547f25eff537f3b9a6a26",
    "tb/tb_h7c.sv":
        "122eee267e6f9a3b48f4cb3bda9966512c1ac26cfd56492f75c45612a8498e4f",
    "input/replay_vectors.txt":
        "642281aa8934097acd1b09317c3df1ddc971b61d1d61cd87e98ee9c2bed27451"
}

NUMERIC = {
    "H4_REPLAY_VECTOR_COUNT": 256,
    "H4_REPLAY_EXTERNAL_MISMATCH_COUNT": 0,
    "H4_REPLAY_Q_MISMATCH_COUNT": 0,
    "H4_REPLAY_CACHE_MISMATCH_COUNT": 0,
    "H4_REPLAY_EXPECTED_MISMATCH_COUNT": 0,
    "H4_ACTION4_DEGREE0_COVERAGE_COUNT": 194,
    "H4_REPLAY_MAX_UPDATE_LATENCY": 111,
    "H4_STRESS_BOUNDARY_COUNT": 8,
    "H4_STRESS_EXTERNAL_MISMATCH_COUNT": 0,
    "H4_STRESS_Q_MISMATCH_COUNT": 0,
    "H4_STRESS_CACHE_MISMATCH_COUNT": 0,
    "H4_STRESS_MAX_UPDATE_LATENCY": 111,
    "H4_TOTAL_MISMATCH_COUNT": 0
}

PASS_KEYS = [
    "H4_EXTERNAL_TRAJECTORY_EQUIVALENCE",
    "H4_DEFERRED_Q_BIT_EXACT_EQUIVALENCE",
    "H4_CACHED_ARGMAX_EQUIVALENCE",
    "H4_ACTION4_DEGREE0_RUNTIME_COVERAGE",
    "H4_UPDATE_LATENCY_BOUND",
    "H4_CONTINUOUS_ACCESS_STRESS",
    "H4_BIT_EXACT_DEFERRED_EQUIVALENCE"
]

def fail(reason):
    raise SystemExit("RESULT=FAIL_H7C_" + reason)

def file_hash(p):
    if not p.is_file() or p.is_symlink():
        fail("INPUT_MISSING")
    return hashlib.sha256(p.read_bytes()).hexdigest()

def check_inputs():
    for name, expected in HASHES.items():
        if file_hash(BASE / name) != expected:
            fail("INPUT_HASH_" + Path(name).name)

    summary_path = BASE / "VERIFICATION_SUMMARY.json"
    summary = json.loads(summary_path.read_text())
    if summary.get("source_hashes") != HASHES:
        fail("SUMMARY_HASHES")

    vectors = (
        BASE / "input/replay_vectors.txt"
    ).read_text().splitlines()

    if len(vectors) != 256:
        fail("VECTOR_COUNT")

    off = 0
    caps = (1, 2, 4, 8, 0)

    for i, line in enumerate(vectors):
        fields = line.split()
        if len(fields) != 10:
            fail("VECTOR_COLUMNS")
        try:
            values = [int(x) for x in fields[:9]]
            int(fields[9], 16)
        except ValueError:
            fail("VECTOR_PARSE")

        if values[0] != i:
            fail("VECTOR_ORDER")

        action, degree = values[5], values[6]
        if not 0 <= action <= 4:
            fail("ACTION_RANGE")
        if degree != caps[action]:
            fail("ACTION_MAPPING")
        off += (action == 4)

    if off != 194:
        fail("VECTOR_OFF_COVERAGE")

    print("INPUT_INTEGRITY=PASS")
    print("VECTOR_OFF_ACTIONS=194")

def check_log(path):
    if not path.is_file() or path.is_symlink():
        fail("LOG_MISSING")

    data = path.read_text(errors="replace")

    if re.search(
        r"H4_FAIL=|H4_(?:EXT|Q|CACHE|EXPECTED)_MISMATCH=",
        data
    ):
        fail("DIAGNOSTIC")

    observed = {}
    for line in data.splitlines():
        m = re.fullmatch(
            r"(H4_[A-Z0-9_]+)=(.*)",
            line.strip()
        )
        if m:
            key, val = m.groups()
            if key in observed:
                fail("DUPLICATE_MARKER")
            observed[key] = val.strip()

    for key, expected in NUMERIC.items():
        try:
            value = int(observed[key])
        except (KeyError, ValueError):
            fail("MISSING_OR_BAD_" + key)
        if value != expected:
            fail("VALUE_" + key)

    for key in PASS_KEYS:
        if observed.get(key) != "PASS":
            fail("STATUS_" + key)

    print("REPLAY_VECTORS=256")
    print("ACTION4_OFF_MAPPINGS=194")
    print("TOTAL_MISMATCHES=0")
    print("STRESS_BOUNDARIES=8")
    print("ALL_ACCEPTANCE_MARKERS=PASS")
    print("RESULT=PASS_H7C_REPRODUCTION")

def execute():
    iv = shutil.which("iverilog")
    vv = shutil.which("vvp")

    if not iv or not vv:
        fail("TOOLS_MISSING")

    for exe, token in (
        (iv, "Icarus Verilog version 13.0"),
        (vv, "Icarus Verilog runtime version 13.0")
    ):
        r = subprocess.run(
            [exe, "-V"], capture_output=True,
            text=True, timeout=15
        )
        if r.returncode or token not in r.stdout + r.stderr:
            fail("TOOL_VERSION")

    build = BASE / "build_h7c_reproduction"
    if build.exists() or build.is_symlink():
        fail("BUILD_DIRECTORY_ALREADY_EXISTS")

    build.mkdir()
    binary = build / "h7c.vvp"

    compile_command = [
        iv, "-g2012", "-s", "tb_h4",
        "-o", str(binary),
        str(BASE / "src/elsa_controller_ref.sv"),
        str(BASE / "src/elsa_controller_opt_testname.sv"),
        str(BASE / "tb/tb_h7c.sv")
    ]

    try:
        c = subprocess.run(
            compile_command, cwd=BASE,
            capture_output=True, text=True,
            timeout=90
        )
    except subprocess.TimeoutExpired:
        fail("COMPILATION_TIMEOUT")

    (build / "compile.log").write_text(c.stdout + c.stderr)
    if c.returncode or not binary.is_file():
        fail("COMPILATION")

    replay_command = [
        vv, str(binary),
        "+VECTORS=" + str(
            BASE / "input/replay_vectors.txt"
        )
    ]

    try:
        r = subprocess.run(
            replay_command, cwd=BASE,
            capture_output=True, text=True,
            timeout=240
        )
    except subprocess.TimeoutExpired:
        fail("REPLAY_TIMEOUT")

    log = build / "replay.log"
    log.write_text(r.stdout + r.stderr)

    if r.returncode:
        fail("SIMULATOR_EXIT")

    check_log(log)

def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check-log":
        check_inputs()
        check_log(Path(sys.argv[2]))
    elif len(sys.argv) == 2 and sys.argv[1] == "--run":
        check_inputs()
        execute()
    else:
        print("Usage:")
        print("  python3 tools/verify_h7c.py --check-log PATH")
        print("  python3 tools/verify_h7c.py --run")
        raise SystemExit(2)

if __name__ == "__main__":
    main()
