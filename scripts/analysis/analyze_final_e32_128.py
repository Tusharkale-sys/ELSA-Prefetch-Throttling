import csv
import math
import re
import statistics
import sys
from collections import Counter
from pathlib import Path

result = Path(sys.argv[1])
out = Path(sys.argv[2])

ARMS = [
    "A0_BERTI_NATIVE_L1D",
    "A1_SBERTI_STATIC_NO_SARSA_L2C",
    "A2_SBERTI_SARSA_ADAPTIVE_L2C",
    "F1_SBERTI_FIXED_CAP1_L2C",
]

SHORT = {
    "A0_BERTI_NATIVE_L1D": "A0",
    "A1_SBERTI_STATIC_NO_SARSA_L2C": "A1",
    "A2_SBERTI_SARSA_ADAPTIVE_L2C": "A2",
    "F1_SBERTI_FIXED_CAP1_L2C": "F1",
}

COMPARISONS = [
    (
        "PRIMARY_A2_VS_A1",
        "A2_SBERTI_SARSA_ADAPTIVE_L2C",
        "A1_SBERTI_STATIC_NO_SARSA_L2C",
    ),
    (
        "SECONDARY_A2_VS_F1",
        "A2_SBERTI_SARSA_ADAPTIVE_L2C",
        "F1_SBERTI_FIXED_CAP1_L2C",
    ),
    (
        "SECONDARY_A2_VS_A0",
        "A2_SBERTI_SARSA_ADAPTIVE_L2C",
        "A0_BERTI_NATIVE_L1D",
    ),
]

FINISHED_RE = re.compile(
    r"^Finished CPU 0 instructions:\s+"
    r"([0-9]+)\s+cycles:\s+"
    r"([0-9]+)\s+cumulative IPC:\s+"
    r"([0-9]+(?:\.[0-9]+)?)"
)

DRAM_KEYS = [
    "Channel_0_RQ_row_buffer_hit",
    "Channel_0_RQ_row_buffer_miss",
    "Channel_0_WQ_row_buffer_hit",
    "Channel_0_WQ_row_buffer_miss",
]

def die(message):
    raise RuntimeError(message)

def choose(n, k):
    if k < 0 or k > n:
        return 0

    return (
        math.factorial(n)
        // (
            math.factorial(k)
            * math.factorial(n - k)
        )
    )

def exact_sign_p(wins, losses):
    n = wins + losses

    if n == 0:
        return 1.0

    k = min(wins, losses)

    numerator = 0

    for i in range(k + 1):
        numerator += choose(n, i)

    p = (
        2.0
        * float(numerator)
        / float(2 ** n)
    )

    return min(1.0, p)

def holm_adjust(items):
    ordered = sorted(
        items,
        key=lambda x: x[1],
    )

    m = len(ordered)
    previous = 0.0
    adjusted = {}

    for rank, item in enumerate(ordered):
        name, p = item

        value = (
            float(m - rank)
            * p
        )

        value = max(
            previous,
            value,
        )

        value = min(
            1.0,
            value,
        )

        adjusted[name] = value
        previous = value

    return adjusted

def gm(values):
    if not values:
        die("empty geometric mean")

    if any(x <= 0 for x in values):
        die(
            "geometric mean received nonpositive value"
        )

    return math.exp(
        sum(
            math.log(x)
            for x in values
        )
        / float(len(values))
    )

def gm_ratio_percent(test, base):
    if len(test) != len(base):
        die("GM pair length mismatch")

    ratios = []

    for t, b in zip(test, base):
        if t <= 0 or b <= 0:
            die(
                "GM ratio received nonpositive input"
            )

        ratios.append(
            float(t) / float(b)
        )

    return (
        gm(ratios) - 1.0
    ) * 100.0

def percent(test, base):
    if base == 0:
        return None

    return (
        float(test)
        / float(base)
        - 1.0
    ) * 100.0

def direction_counts(
    test,
    base,
    higher_is_better,
):
    wins = 0
    ties = 0
    losses = 0

    for t, b in zip(test, base):
        if t == b:
            ties += 1
            continue

        if higher_is_better:
            if t > b:
                wins += 1
            else:
                losses += 1
        else:
            if t < b:
                wins += 1
            else:
                losses += 1

    return wins, ties, losses

def parse_status(path):
    values = {}

    for raw in path.read_text(
        errors="ignore"
    ).splitlines():

        if "=" not in raw:
            continue

        key, value = raw.split(
            "=",
            1,
        )

        values[key] = value

    required = [
        "STATUS",
        "INDEX",
        "WORKLOAD",
        "ARM",
        "RC",
        "RUN_SECONDS",
        "LOG",
    ]

    missing = [
        key
        for key in required
        if key not in values
    ]

    if missing:
        die(
            "{} missing {}".format(
                path.name,
                missing,
            )
        )

    if values["STATUS"] != "PASS":
        die(
            "{} status not PASS".format(
                path.name
            )
        )

    if values["RC"] != "0":
        die(
            "{} RC != 0".format(
                path.name
            )
        )

    return values

def parse_numeric(path):
    values = {}

    with path.open(
        errors="ignore"
    ) as f:
        for raw in f:
            parts = raw.strip().split()

            if len(parts) != 2:
                continue

            key = parts[0].rstrip(":")

            try:
                value = float(parts[1])
            except Exception:
                continue

            values[key] = value

    return values

def require_int(values, key, log):
    if key not in values:
        die(
            "{} missing {}".format(
                log.name,
                key,
            )
        )

    return int(values[key])

def parse_log(path, arm):
    numeric = parse_numeric(path)

    finished = []

    with path.open(
        errors="ignore"
    ) as f:
        for raw in f:
            m = FINISHED_RE.match(
                raw.strip()
            )

            if m:
                finished.append(m)

    if len(finished) != 1:
        die(
            "{} completion-line count {}".format(
                path.name,
                len(finished),
            )
        )

    m = finished[0]

    instructions = int(m.group(1))
    cycles = int(m.group(2))
    ipc = float(m.group(3))

    if ipc <= 0:
        die(
            "{} nonpositive IPC".format(
                path.name
            )
        )

    rq_hit = require_int(
        numeric,
        "Channel_0_RQ_row_buffer_hit",
        path,
    )

    rq_miss = require_int(
        numeric,
        "Channel_0_RQ_row_buffer_miss",
        path,
    )

    wq_hit = require_int(
        numeric,
        "Channel_0_WQ_row_buffer_hit",
        path,
    )

    wq_miss = require_int(
        numeric,
        "Channel_0_WQ_row_buffer_miss",
        path,
    )

    rq = rq_hit + rq_miss
    wq = wq_hit + wq_miss
    dram = rq + wq

    if rq <= 0:
        die(
            "{} nonpositive RQ".format(
                path.name
            )
        )

    if dram <= 0:
        die(
            "{} nonpositive total DRAM".format(
                path.name
            )
        )

    row_hit_rate = (
        float(rq_hit + wq_hit)
        / float(dram)
    )

    row = {
        "instructions": instructions,
        "cycles": cycles,
        "ipc": ipc,
        "rq_hit": rq_hit,
        "rq_miss": rq_miss,
        "wq_hit": wq_hit,
        "wq_miss": wq_miss,
        "rq_transactions": rq,
        "wq_transactions": wq,
        "dram_transactions": dram,
        "row_hit_rate": row_hit_rate,
        "counter_family": "",
        "prefetch_issued_raw": None,
        "prefetch_useful_raw": None,
        "sberti_accuracy": None,
        "rl_epochs": None,
        "rl_final_degree": None,
        "rl_degree1_epochs": None,
        "rl_degree2_epochs": None,
        "rl_degree3_epochs": None,
        "rl_degree4_epochs": None,
    }

    if arm == "A0_BERTI_NATIVE_L1D":
        issued = require_int(
            numeric,
            "berti_prefetches_issued",
            path,
        )

        useful = require_int(
            numeric,
            "berti_prefetches_useful",
            path,
        )

        row["counter_family"] = "BERTI_NATIVE_RAW"
        row["prefetch_issued_raw"] = issued
        row["prefetch_useful_raw"] = useful

    else:
        issued = require_int(
            numeric,
            "sberti_total_prefetch_issued",
            path,
        )

        useful = require_int(
            numeric,
            "sberti_total_prefetch_useful",
            path,
        )

        row["counter_family"] = "SBERTI_TOTAL"
        row["prefetch_issued_raw"] = issued
        row["prefetch_useful_raw"] = useful

        if issued == 0:
            accuracy = 0.0
        else:
            accuracy = (
                float(useful)
                / float(issued)
            )

        row["sberti_accuracy"] = accuracy

        row["rl_epochs"] = require_int(
            numeric,
            "sberti_rl_epochs",
            path,
        )

        row["rl_final_degree"] = require_int(
            numeric,
            "sberti_rl_final_degree",
            path,
        )

        row["rl_degree1_epochs"] = require_int(
            numeric,
            "sberti_rl_degree1_epochs",
            path,
        )

        row["rl_degree2_epochs"] = require_int(
            numeric,
            "sberti_rl_degree2_epochs",
            path,
        )

        row["rl_degree3_epochs"] = require_int(
            numeric,
            "sberti_rl_degree3_epochs",
            path,
        )

        row["rl_degree4_epochs"] = require_int(
            numeric,
            "sberti_rl_degree4_epochs",
            path,
        )

    return row

statuses = sorted(
    (result / "status").glob(
        "*.status"
    )
)

if len(statuses) != 96:
    die(
        "expected 96 status files"
    )

records = []

for status_path in statuses:
    status = parse_status(
        status_path
    )

    arm = status["ARM"]

    if arm not in ARMS:
        die(
            "unexpected arm {}".format(
                arm
            )
        )

    log = Path(
        status["LOG"]
    )

    if not log.is_file():
        die(
            "missing log {}".format(log)
        )

    metrics = parse_log(
        log,
        arm,
    )

    row = {
        "index": int(
            status["INDEX"]
        ),
        "workload": status["WORKLOAD"],
        "arm": arm,
        "arm_short": SHORT[arm],
        "run_seconds": int(
            status["RUN_SECONDS"]
        ),
        "log": str(log),
    }

    row.update(metrics)

    records.append(row)

records.sort(
    key=lambda r: (
        r["index"],
        ARMS.index(r["arm"]),
    )
)

if len(records) != 96:
    die("record count != 96")

counts = Counter(
    r["arm"]
    for r in records
)

for arm in ARMS:
    if counts[arm] != 24:
        die(
            "{} count {}".format(
                arm,
                counts[arm],
            )
        )

index_workloads = {}

for row in records:
    index = row["index"]
    workload = row["workload"]

    if (
        index in index_workloads
        and index_workloads[index] != workload
    ):
        die(
            "index/workload mismatch"
        )

    index_workloads[index] = workload

if len(index_workloads) != 24:
    die(
        "workload count != 24"
    )

ordered_workloads = [
    index_workloads[index]
    for index in sorted(index_workloads)
]

by_key = {
    (
        r["workload"],
        r["arm"],
    ): r
    for r in records
}

if len(by_key) != 96:
    die(
        "duplicate workload-arm entry"
    )

for workload in ordered_workloads:
    for arm in ARMS:
        if (
            workload,
            arm,
        ) not in by_key:
            die(
                "missing {} {}".format(
                    workload,
                    arm,
                )
            )

record_fields = [
    "index",
    "workload",
    "arm",
    "arm_short",
    "instructions",
    "cycles",
    "ipc",
    "rq_hit",
    "rq_miss",
    "wq_hit",
    "wq_miss",
    "rq_transactions",
    "wq_transactions",
    "dram_transactions",
    "row_hit_rate",
    "counter_family",
    "prefetch_issued_raw",
    "prefetch_useful_raw",
    "sberti_accuracy",
    "rl_epochs",
    "rl_final_degree",
    "rl_degree1_epochs",
    "rl_degree2_epochs",
    "rl_degree3_epochs",
    "rl_degree4_epochs",
    "run_seconds",
    "log",
]

with (
    out / "E32_128_RECORDS.tsv"
).open(
    "w",
    newline="",
) as f:
    writer = csv.DictWriter(
        f,
        fieldnames=record_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for row in records:
        clean = {}

        for key in record_fields:
            value = row.get(key)

            if value is None:
                clean[key] = ""
            else:
                clean[key] = value

        writer.writerow(clean)

arm_summary = []

for arm in ARMS:
    rows = [
        r
        for r in records
        if r["arm"] == arm
    ]

    ipc = [
        r["ipc"]
        for r in rows
    ]

    rq = [
        r["rq_transactions"]
        for r in rows
    ]

    wq = [
        r["wq_transactions"]
        for r in rows
    ]

    dram = [
        r["dram_transactions"]
        for r in rows
    ]

    dram_sum = sum(dram)

    row_hits = sum(
        r["rq_hit"] + r["wq_hit"]
        for r in rows
    )

    issued_sum = sum(
        r["prefetch_issued_raw"]
        for r in rows
    )

    useful_sum = sum(
        r["prefetch_useful_raw"]
        for r in rows
    )

    if arm == "A0_BERTI_NATIVE_L1D":
        weighted_accuracy = None
        prefetch_scope = (
            "RAW_NATIVE_BERTI_"
            "NOT_CROSS_ARM_ACCURACY_COMPARABLE"
        )
    else:
        if issued_sum == 0:
            weighted_accuracy = 0.0
        else:
            weighted_accuracy = (
                float(useful_sum)
                / float(issued_sum)
            )

        prefetch_scope = (
            "SBERTI_TOTAL_COMPARABLE_"
            "WITH_A1_A2_F1"
        )

    arm_summary.append(
        {
            "arm": SHORT[arm],
            "gm_ipc": gm(ipc),
            "mean_ipc": statistics.mean(ipc),
            "gm_rq_transactions": gm(rq),
            "sum_wq_transactions": sum(wq),
            "zero_wq_workloads": sum(
                1
                for x in wq
                if x == 0
            ),
            "gm_dram_transactions": gm(dram),
            "sum_rq_transactions": sum(rq),
            "sum_dram_transactions": dram_sum,
            "weighted_row_hit_rate": (
                float(row_hits)
                / float(dram_sum)
            ),
            "prefetch_issued_sum_raw": issued_sum,
            "prefetch_useful_sum_raw": useful_sum,
            "weighted_sberti_accuracy": weighted_accuracy,
            "prefetch_metric_scope": prefetch_scope,
        }
    )

arm_fields = [
    "arm",
    "gm_ipc",
    "mean_ipc",
    "gm_rq_transactions",
    "sum_wq_transactions",
    "zero_wq_workloads",
    "gm_dram_transactions",
    "sum_rq_transactions",
    "sum_dram_transactions",
    "weighted_row_hit_rate",
    "prefetch_issued_sum_raw",
    "prefetch_useful_sum_raw",
    "weighted_sberti_accuracy",
    "prefetch_metric_scope",
]

with (
    out / "E32_128_ARM_SUMMARY.tsv"
).open(
    "w",
    newline="",
) as f:
    writer = csv.DictWriter(
        f,
        fieldnames=arm_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for row in arm_summary:
        clean = dict(row)

        if (
            clean[
                "weighted_sberti_accuracy"
            ]
            is None
        ):
            clean[
                "weighted_sberti_accuracy"
            ] = ""

        writer.writerow(clean)

pairwise = []

ipc_pvalues = {}
dram_pvalues = {}

for name, test_arm, base_arm in COMPARISONS:
    test_rows = [
        by_key[
            (
                workload,
                test_arm,
            )
        ]
        for workload in ordered_workloads
    ]

    base_rows = [
        by_key[
            (
                workload,
                base_arm,
            )
        ]
        for workload in ordered_workloads
    ]

    test_ipc = [
        r["ipc"]
        for r in test_rows
    ]

    base_ipc = [
        r["ipc"]
        for r in base_rows
    ]

    test_rq = [
        r["rq_transactions"]
        for r in test_rows
    ]

    base_rq = [
        r["rq_transactions"]
        for r in base_rows
    ]

    test_wq = [
        r["wq_transactions"]
        for r in test_rows
    ]

    base_wq = [
        r["wq_transactions"]
        for r in base_rows
    ]

    test_dram = [
        r["dram_transactions"]
        for r in test_rows
    ]

    base_dram = [
        r["dram_transactions"]
        for r in base_rows
    ]

    ipc_changes = [
        percent(t, b)
        for t, b in zip(
            test_ipc,
            base_ipc,
        )
    ]

    dram_changes = [
        percent(t, b)
        for t, b in zip(
            test_dram,
            base_dram,
        )
    ]

    ipc_w, ipc_t, ipc_l = direction_counts(
        test_ipc,
        base_ipc,
        True,
    )

    dram_w, dram_t, dram_l = direction_counts(
        test_dram,
        base_dram,
        False,
    )

    wq_w, wq_t, wq_l = direction_counts(
        test_wq,
        base_wq,
        False,
    )

    ipc_p = exact_sign_p(
        ipc_w,
        ipc_l,
    )

    dram_p = exact_sign_p(
        dram_w,
        dram_l,
    )

    ipc_pvalues[name] = ipc_p
    dram_pvalues[name] = dram_p

    test_row_hits = sum(
        r["rq_hit"] + r["wq_hit"]
        for r in test_rows
    )

    base_row_hits = sum(
        r["rq_hit"] + r["wq_hit"]
        for r in base_rows
    )

    test_row_total = sum(
        r["dram_transactions"]
        for r in test_rows
    )

    base_row_total = sum(
        r["dram_transactions"]
        for r in base_rows
    )

    prefetch_comparable = (
        base_arm
        != "A0_BERTI_NATIVE_L1D"
    )

    if prefetch_comparable:
        test_issued = sum(
            r["prefetch_issued_raw"]
            for r in test_rows
        )

        base_issued = sum(
            r["prefetch_issued_raw"]
            for r in base_rows
        )

        test_useful = sum(
            r["prefetch_useful_raw"]
            for r in test_rows
        )

        base_useful = sum(
            r["prefetch_useful_raw"]
            for r in base_rows
        )

        test_accuracy = (
            float(test_useful)
            / float(test_issued)
            if test_issued
            else 0.0
        )

        base_accuracy = (
            float(base_useful)
            / float(base_issued)
            if base_issued
            else 0.0
        )

        issued_percent = percent(
            test_issued,
            base_issued,
        )

        useful_percent = percent(
            test_useful,
            base_useful,
        )

        accuracy_delta = (
            test_accuracy
            - base_accuracy
        ) * 100.0

        prefetch_scope = (
            "SBERTI_TO_SBERTI"
        )

    else:
        test_issued = None
        base_issued = None
        test_useful = None
        base_useful = None
        test_accuracy = None
        base_accuracy = None
        issued_percent = None
        useful_percent = None
        accuracy_delta = None
        prefetch_scope = (
            "NA_A0_DIFFERENT_COUNTER_FAMILY"
        )

    wq_test_sum = sum(test_wq)
    wq_base_sum = sum(base_wq)

    pairwise.append(
        {
            "comparison": name,
            "test_arm": SHORT[test_arm],
            "base_arm": SHORT[base_arm],
            "gm_ipc_percent": gm_ratio_percent(
                test_ipc,
                base_ipc,
            ),
            "mean_ipc_percent": statistics.mean(
                ipc_changes
            ),
            "median_ipc_percent": statistics.median(
                ipc_changes
            ),
            "ipc_wins": ipc_w,
            "ipc_ties": ipc_t,
            "ipc_losses": ipc_l,
            "ipc_exact_sign_p": ipc_p,
            "gm_dram_transactions_percent": gm_ratio_percent(
                test_dram,
                base_dram,
            ),
            "mean_dram_transactions_percent": statistics.mean(
                dram_changes
            ),
            "median_dram_transactions_percent": statistics.median(
                dram_changes
            ),
            "dram_lower_wins": dram_w,
            "dram_ties": dram_t,
            "dram_higher_losses": dram_l,
            "dram_exact_sign_p": dram_p,
            "gm_rq_transactions_percent": gm_ratio_percent(
                test_rq,
                base_rq,
            ),
            "wq_sum_test": wq_test_sum,
            "wq_sum_base": wq_base_sum,
            "wq_sum_percent": percent(
                wq_test_sum,
                wq_base_sum,
            ),
            "wq_lower_wins": wq_w,
            "wq_ties": wq_t,
            "wq_higher_losses": wq_l,
            "wq_both_zero_count": sum(
                1
                for t, b in zip(
                    test_wq,
                    base_wq,
                )
                if t == 0 and b == 0
            ),
            "wq_gm_status": (
                "NOT_DEFINED_ZERO_INPUTS"
            ),
            "test_prefetch_issued_sum": test_issued,
            "base_prefetch_issued_sum": base_issued,
            "prefetch_issued_sum_percent": issued_percent,
            "test_prefetch_useful_sum": test_useful,
            "base_prefetch_useful_sum": base_useful,
            "prefetch_useful_sum_percent": useful_percent,
            "test_weighted_sberti_accuracy": test_accuracy,
            "base_weighted_sberti_accuracy": base_accuracy,
            "sberti_accuracy_delta_pp": accuracy_delta,
            "prefetch_metric_scope": prefetch_scope,
            "test_weighted_row_hit_rate": (
                float(test_row_hits)
                / float(test_row_total)
            ),
            "base_weighted_row_hit_rate": (
                float(base_row_hits)
                / float(base_row_total)
            ),
            "row_hit_rate_delta_pp": (
                (
                    float(test_row_hits)
                    / float(test_row_total)
                )
                -
                (
                    float(base_row_hits)
                    / float(base_row_total)
                )
            ) * 100.0,
        }
    )

ipc_holm = holm_adjust(
    list(ipc_pvalues.items())
)

dram_holm = holm_adjust(
    list(dram_pvalues.items())
)

for row in pairwise:
    name = row["comparison"]

    row[
        "ipc_exact_sign_holm3_p"
    ] = ipc_holm[name]

    row[
        "dram_exact_sign_holm3_p"
    ] = dram_holm[name]

pair_fields = [
    "comparison",
    "test_arm",
    "base_arm",
    "gm_ipc_percent",
    "mean_ipc_percent",
    "median_ipc_percent",
    "ipc_wins",
    "ipc_ties",
    "ipc_losses",
    "ipc_exact_sign_p",
    "ipc_exact_sign_holm3_p",
    "gm_dram_transactions_percent",
    "mean_dram_transactions_percent",
    "median_dram_transactions_percent",
    "dram_lower_wins",
    "dram_ties",
    "dram_higher_losses",
    "dram_exact_sign_p",
    "dram_exact_sign_holm3_p",
    "gm_rq_transactions_percent",
    "wq_sum_test",
    "wq_sum_base",
    "wq_sum_percent",
    "wq_lower_wins",
    "wq_ties",
    "wq_higher_losses",
    "wq_both_zero_count",
    "wq_gm_status",
    "test_prefetch_issued_sum",
    "base_prefetch_issued_sum",
    "prefetch_issued_sum_percent",
    "test_prefetch_useful_sum",
    "base_prefetch_useful_sum",
    "prefetch_useful_sum_percent",
    "test_weighted_sberti_accuracy",
    "base_weighted_sberti_accuracy",
    "sberti_accuracy_delta_pp",
    "prefetch_metric_scope",
    "test_weighted_row_hit_rate",
    "base_weighted_row_hit_rate",
    "row_hit_rate_delta_pp",
]

with (
    out / "E32_128_PAIRWISE.tsv"
).open(
    "w",
    newline="",
) as f:
    writer = csv.DictWriter(
        f,
        fieldnames=pair_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for row in pairwise:
        clean = {}

        for key in pair_fields:
            value = row.get(key)

            if value is None:
                clean[key] = ""
            else:
                clean[key] = value

        writer.writerow(clean)

per_workload_fields = [
    "index",
    "workload",
    "comparison",
    "test_arm",
    "base_arm",
    "test_ipc",
    "base_ipc",
    "ipc_percent",
    "test_dram_transactions",
    "base_dram_transactions",
    "dram_transactions_percent",
    "test_rq_transactions",
    "base_rq_transactions",
    "rq_transactions_percent",
    "test_wq_transactions",
    "base_wq_transactions",
    "wq_transactions_percent",
    "wq_pair_status",
]

with (
    out / "E32_128_PER_WORKLOAD_PAIRWISE.tsv"
).open(
    "w",
    newline="",
) as f:
    writer = csv.DictWriter(
        f,
        fieldnames=per_workload_fields,
        delimiter="\t",
        lineterminator="\n",
    )

    writer.writeheader()

    for name, test_arm, base_arm in COMPARISONS:
        for workload in ordered_workloads:
            test = by_key[
                (
                    workload,
                    test_arm,
                )
            ]

            base = by_key[
                (
                    workload,
                    base_arm,
                )
            ]

            if (
                test["wq_transactions"] == 0
                and base["wq_transactions"] == 0
            ):
                wq_percent = ""
                wq_status = "BOTH_ZERO"
            elif base["wq_transactions"] == 0:
                wq_percent = ""
                wq_status = "BASE_ZERO"
            else:
                wq_percent = percent(
                    test["wq_transactions"],
                    base["wq_transactions"],
                )

                wq_status = "DEFINED"

            writer.writerow(
                {
                    "index": test["index"],
                    "workload": workload,
                    "comparison": name,
                    "test_arm": SHORT[test_arm],
                    "base_arm": SHORT[base_arm],
                    "test_ipc": test["ipc"],
                    "base_ipc": base["ipc"],
                    "ipc_percent": percent(
                        test["ipc"],
                        base["ipc"],
                    ),
                    "test_dram_transactions": test["dram_transactions"],
                    "base_dram_transactions": base["dram_transactions"],
                    "dram_transactions_percent": percent(
                        test["dram_transactions"],
                        base["dram_transactions"],
                    ),
                    "test_rq_transactions": test["rq_transactions"],
                    "base_rq_transactions": base["rq_transactions"],
                    "rq_transactions_percent": percent(
                        test["rq_transactions"],
                        base["rq_transactions"],
                    ),
                    "test_wq_transactions": test["wq_transactions"],
                    "base_wq_transactions": base["wq_transactions"],
                    "wq_transactions_percent": wq_percent,
                    "wq_pair_status": wq_status,
                }
            )

a2 = [
    r
    for r in records
    if r["arm"]
    == "A2_SBERTI_SARSA_ADAPTIVE_L2C"
]

if len(a2) != 24:
    die(
        "A2 count != 24"
    )

a2_epochs = [
    r["rl_epochs"]
    for r in a2
]

a2_final = Counter(
    r["rl_final_degree"]
    for r in a2
)

valid_degrees = {
    1,
    2,
    4,
    8,
}

if not set(a2_final).issubset(
    valid_degrees
):
    die(
        "unexpected A2 final degree {}".format(
            sorted(a2_final)
        )
    )

epoch_degree_totals = {
    1: sum(
        r["rl_degree1_epochs"]
        for r in a2
    ),
    2: sum(
        r["rl_degree2_epochs"]
        for r in a2
    ),
    4: sum(
        r["rl_degree3_epochs"]
        for r in a2
    ),
    8: sum(
        r["rl_degree4_epochs"]
        for r in a2
    ),
}

total_action_epochs = sum(
    epoch_degree_totals.values()
)

with (
    out / "E32_128_A2_SARSA_BEHAVIOR.txt"
).open("w") as f:
    f.write(
        "A2_RUN_COUNT=24\n"
    )

    f.write(
        "A2_RL_EPOCHS_MIN={}\n".format(
            min(a2_epochs)
        )
    )

    f.write(
        "A2_RL_EPOCHS_MAX={}\n".format(
            max(a2_epochs)
        )
    )

    f.write(
        "A2_RL_EPOCHS_MEAN={:.12f}\n".format(
            statistics.mean(
                a2_epochs
            )
        )
    )

    f.write(
        "A2_RL_EPOCHS_MEDIAN={:.12f}\n".format(
            statistics.median(
                a2_epochs
            )
        )
    )

    f.write(
        "A2_RL_EPOCHS_SUM={}\n".format(
            sum(a2_epochs)
        )
    )

    for degree in [1, 2, 4, 8]:
        f.write(
            "A2_FINAL_DEGREE_{}_COUNT={}\n".format(
                degree,
                a2_final.get(
                    degree,
                    0,
                ),
            )
        )

    f.write(
        "A2_ACTION_EPOCH_TOTAL={}\n".format(
            total_action_epochs
        )
    )

    for degree in [1, 2, 4, 8]:
        count = epoch_degree_totals[
            degree
        ]

        fraction = (
            float(count)
            / float(total_action_epochs)
            if total_action_epochs
            else 0.0
        )

        f.write(
            "A2_ACTION_DEGREE_{}_EPOCHS={}\n".format(
                degree,
                count,
            )
        )

        f.write(
            "A2_ACTION_DEGREE_{}_FRACTION={:.12f}\n".format(
                degree,
                fraction,
            )
        )

by_comparison = {
    row["comparison"]: row
    for row in pairwise
}

lines = []

lines.append(
    "E32_128_FINAL_PREREGISTERED_ANALYSIS=COMPLETE"
)

lines.append(
    "WORKLOAD_COUNT=24"
)

lines.append(
    "ARM_COUNT=4"
)

lines.append(
    "RUN_COUNT=96"
)

lines.append(
    "WQ_GEOMETRIC_MEAN=NOT_DEFINED_DUE_TO_ZERO_INPUTS"
)

lines.append(
    "WQ_ZERO_WORKLOAD_COUNT_PER_ARM=6"
)

lines.append("")

for name, _, _ in COMPARISONS:
    row = by_comparison[name]

    lines.append(
        "{}_GM_IPC_PERCENT={:.12f}".format(
            name,
            row["gm_ipc_percent"],
        )
    )

    lines.append(
        "{}_IPC_W_T_L={}/{}/{}".format(
            name,
            row["ipc_wins"],
            row["ipc_ties"],
            row["ipc_losses"],
        )
    )

    lines.append(
        "{}_IPC_SIGN_P={:.12f}".format(
            name,
            row["ipc_exact_sign_p"],
        )
    )

    lines.append(
        "{}_IPC_HOLM3_P={:.12f}".format(
            name,
            row["ipc_exact_sign_holm3_p"],
        )
    )

    lines.append(
        "{}_GM_COMPLETED_DRAM_TRANSACTIONS_PERCENT={:.12f}".format(
            name,
            row[
                "gm_dram_transactions_percent"
            ],
        )
    )

    lines.append(
        "{}_DRAM_LOWER_TIE_HIGHER={}/{}/{}".format(
            name,
            row["dram_lower_wins"],
            row["dram_ties"],
            row["dram_higher_losses"],
        )
    )

    lines.append(
        "{}_DRAM_SIGN_P={:.12f}".format(
            name,
            row["dram_exact_sign_p"],
        )
    )

    lines.append(
        "{}_DRAM_HOLM3_P={:.12f}".format(
            name,
            row["dram_exact_sign_holm3_p"],
        )
    )

    lines.append(
        "{}_GM_RQ_TRANSACTIONS_PERCENT={:.12f}".format(
            name,
            row[
                "gm_rq_transactions_percent"
            ],
        )
    )

    lines.append(
        "{}_WQ_SUM_PERCENT={:.12f}".format(
            name,
            row["wq_sum_percent"],
        )
    )

    lines.append(
        "{}_WQ_LOWER_TIE_HIGHER={}/{}/{}".format(
            name,
            row["wq_lower_wins"],
            row["wq_ties"],
            row["wq_higher_losses"],
        )
    )

    lines.append(
        "{}_ROW_HIT_RATE_DELTA_PP={:.12f}".format(
            name,
            row[
                "row_hit_rate_delta_pp"
            ],
        )
    )

    if (
        row["prefetch_metric_scope"]
        == "SBERTI_TO_SBERTI"
    ):
        lines.append(
            "{}_PREFETCH_ISSUED_SUM_PERCENT={:.12f}".format(
                name,
                row[
                    "prefetch_issued_sum_percent"
                ],
            )
        )

        if (
            row[
                "prefetch_useful_sum_percent"
            ]
            is None
        ):
            lines.append(
                "{}_PREFETCH_USEFUL_SUM_PERCENT=NA_BASE_ZERO".format(
                    name
                )
            )
        else:
            lines.append(
                "{}_PREFETCH_USEFUL_SUM_PERCENT={:.12f}".format(
                    name,
                    row[
                        "prefetch_useful_sum_percent"
                    ],
                )
            )

        lines.append(
            "{}_SBERTI_ACCURACY_DELTA_PP={:.12f}".format(
                name,
                row[
                    "sberti_accuracy_delta_pp"
                ],
            )
        )

    else:
        lines.append(
            "{}_PREFETCH_METRICS=NA_DIFFERENT_COUNTER_FAMILIES".format(
                name
            )
        )

    lines.append("")

lines.append(
    "COMPLETED_DRAM_TRANSACTION_DEFINITION=RQ_HIT_PLUS_RQ_MISS_PLUS_WQ_HIT_PLUS_WQ_MISS"
)

lines.append(
    "WQ_REPORTING=ALL24_AGGREGATE_SUM_AND_WTL_NO_PSEUDOCOUNT_NO_WORKLOAD_DROP"
)

lines.append(
    "A0_PREFETCH_ACCURACY_CROSS_ARM_COMPARISON=NOT_USED"
)

lines.append(
    "ENERGY_JOULES=NOT_EVALUATED"
)

lines.append(
    "HARDWARE_SYNTHESIS=NOT_EVALUATED"
)

lines.append(
    "DEMAND_VS_PREFETCH_DRAM_BREAKDOWN=NOT_AVAILABLE_FROM_EXISTING_PRINT_PATH"
)

(
    out / "RESULT.txt"
).write_text(
    "\n".join(lines)
    + "\n"
)

print(
    "E32_128_FINAL_PREREGISTERED_ANALYSIS=PASS"
)

print(
    "RECORD_COUNT=96"
)

print(
    "WORKLOAD_COUNT=24"
)

print()

for row in arm_summary:
    if (
        row[
            "weighted_sberti_accuracy"
        ]
        is None
    ):
        acc = "NA"
    else:
        acc = "{:.12f}".format(
            row[
                "weighted_sberti_accuracy"
            ]
        )

    print(
        "ARM={} GM_IPC={:.12f} "
        "GM_DRAM={:.12f} "
        "GM_RQ={:.12f} "
        "SUM_WQ={} ZERO_WQ={} "
        "ISSUED_RAW={} USEFUL_RAW={} "
        "ACC={}".format(
            row["arm"],
            row["gm_ipc"],
            row[
                "gm_dram_transactions"
            ],
            row[
                "gm_rq_transactions"
            ],
            row[
                "sum_wq_transactions"
            ],
            row[
                "zero_wq_workloads"
            ],
            row[
                "prefetch_issued_sum_raw"
            ],
            row[
                "prefetch_useful_sum_raw"
            ],
            acc,
        )
    )

print()

for row in pairwise:
    print(
        "COMPARISON={} "
        "GM_IPC_PERCENT={:.12f} "
        "IPC_W_T_L={}/{}/{} "
        "IPC_P={:.12f} "
        "GM_DRAM_PERCENT={:.12f} "
        "DRAM_LOWER_TIE_HIGHER={}/{}/{} "
        "DRAM_P={:.12f} "
        "GM_RQ_PERCENT={:.12f} "
        "WQ_SUM_PERCENT={:.12f} "
        "WQ_LOWER_TIE_HIGHER={}/{}/{}".format(
            row["comparison"],
            row["gm_ipc_percent"],
            row["ipc_wins"],
            row["ipc_ties"],
            row["ipc_losses"],
            row["ipc_exact_sign_p"],
            row[
                "gm_dram_transactions_percent"
            ],
            row["dram_lower_wins"],
            row["dram_ties"],
            row["dram_higher_losses"],
            row["dram_exact_sign_p"],
            row[
                "gm_rq_transactions_percent"
            ],
            row["wq_sum_percent"],
            row["wq_lower_wins"],
            row["wq_ties"],
            row["wq_higher_losses"],
        )
    )

    if (
        row["prefetch_metric_scope"]
        == "SBERTI_TO_SBERTI"
    ):
        print(
            "  SBERTI_ISSUED_PERCENT={:.12f} "
            "SBERTI_ACCURACY_DELTA_PP={:.12f}".format(
                row[
                    "prefetch_issued_sum_percent"
                ],
                row[
                    "sberti_accuracy_delta_pp"
                ],
            )
        )

    else:
        print(
            "  PREFETCH_METRICS="
            "NA_DIFFERENT_COUNTER_FAMILIES"
        )

print()

print(
    "WQ_GEOMETRIC_MEAN="
    "NOT_DEFINED_DUE_TO_ZERO_INPUTS"
)

print(
    "A0_PREFETCH_ACCURACY_CROSS_ARM="
    "NOT_USED"
)

print(
    "FINAL_ANALYZER_COMPLETED=PASS"
)
