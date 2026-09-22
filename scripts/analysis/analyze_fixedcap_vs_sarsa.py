import csv
import json
import math
import statistics
import sys
from collections import Counter
from pathlib import Path


raw_root = Path(sys.argv[1])
canon_root = Path(sys.argv[2])
out = Path(sys.argv[3])

out.mkdir(parents=True, exist_ok=True)


A0 = "A0_BERTI_NATIVE_L1D"
A1 = "A1_SBERTI_STATIC_NO_SARSA_L2C"
A2 = "A2_SBERTI_SARSA_ADAPTIVE_L2C"

F1 = "F1_SBERTI_FIXED_CAP1_L2C"
F2 = "F2_SBERTI_FIXED_CAP2_L2C"
F4 = "F4_SBERTI_FIXED_CAP4_L2C"
F8 = "F8_SBERTI_FIXED_CAP8_L2C"

FIXED = [F1, F2, F4, F8]
ALL_ARMS = [A0, A1, A2, F1, F2, F4, F8]

CAP = {
    F1: 1,
    F2: 2,
    F4: 4,
    F8: 8,
}


def load_record(path):
    with path.open(newline="") as f:
        rows = list(
            csv.reader(
                f,
                delimiter="\t",
            )
        )

    rows = [
        r
        for r in rows
        if any(x.strip() for x in r)
    ]

    if len(rows) != 2:
        raise RuntimeError(
            "{} expected header+row, got {}".format(
                path.name,
                len(rows),
            )
        )

    header = rows[0]
    row = rows[1]

    if len(row) != 15:
        raise RuntimeError(
            "{} expected 15 fields, got {}".format(
                path.name,
                len(row),
            )
        )

    return {
        "idx": int(row[0]),
        "workload": row[1],
        "arm": row[2],
        "ipc": float(row[3]),
        "run_seconds": int(row[4]),
        "berti_issued": (
            int(row[5]) if row[5] else None
        ),
        "berti_useful": (
            int(row[6]) if row[6] else None
        ),
        "sb_rl": (
            int(row[7]) if row[7] else None
        ),
        "sb_epoch": (
            int(row[8]) if row[8] else None
        ),
        "sb_rl_epochs": (
            int(row[9]) if row[9] else None
        ),
        "sb_final_degree": (
            int(row[10]) if row[10] else None
        ),
        "sb_issued": (
            int(row[11]) if row[11] else None
        ),
        "sb_useful": (
            int(row[12]) if row[12] else None
        ),
        "sb_accuracy": (
            float(row[13]) if row[13] else None
        ),
        "log_sha": row[14],
    }


def load_arm_records(root, arm):
    paths = sorted(
        (root / "records").glob(
            "*__{}.tsv".format(arm)
        )
    )

    if len(paths) != 24:
        raise RuntimeError(
            "{} expected 24 records, got {}".format(
                arm,
                len(paths),
            )
        )

    records = [
        load_record(p)
        for p in paths
    ]

    if any(r["arm"] != arm for r in records):
        raise RuntimeError(
            "{} record arm mismatch".format(arm)
        )

    by_workload = {}

    for r in records:
        workload = r["workload"]

        if workload in by_workload:
            raise RuntimeError(
                "{} duplicate workload {}".format(
                    arm,
                    workload,
                )
            )

        if not (r["ipc"] > 0.0):
            raise RuntimeError(
                "{} nonpositive IPC {}".format(
                    arm,
                    workload,
                )
            )

        by_workload[workload] = r

    return by_workload


def gm(values):
    values = list(values)

    if not values:
        return float("nan")

    if any(x <= 0.0 for x in values):
        raise RuntimeError(
            "geometric mean requires positive values"
        )

    return math.exp(
        sum(math.log(x) for x in values)
        / float(len(values))
    )


def percent_ratio(candidate, reference):
    return 100.0 * (
        candidate / reference - 1.0
    )


def paired_stats(candidate, reference):
    workloads = sorted(candidate)

    ratios = []
    percentages = []

    wins = 0
    ties = 0
    losses = 0

    for w in workloads:
        a = candidate[w]["ipc"]
        b = reference[w]["ipc"]

        ratio = a / b
        pct = 100.0 * (ratio - 1.0)

        ratios.append(ratio)
        percentages.append(pct)

        if a > b:
            wins += 1
        elif a < b:
            losses += 1
        else:
            ties += 1

    return {
        "gm_percent": 100.0 * (gm(ratios) - 1.0),
        "mean_percent": statistics.mean(percentages),
        "median_percent": statistics.median(percentages),
        "wins": wins,
        "ties": ties,
        "losses": losses,
        "sign_p": exact_sign_test(wins, losses),
    }


def exact_sign_test(wins, losses):
    n = wins + losses

    if n == 0:
        return 1.0

    k = min(wins, losses)

    tail = 0.0

    for i in range(k + 1):
        tail += (
            math.comb(n, i)
            / float(2 ** n)
        )

    return min(1.0, 2.0 * tail)


def holm_adjust(items):
    # items = [(name, p), ...]
    ordered = sorted(
        items,
        key=lambda x: x[1],
    )

    m = len(ordered)

    adjusted_sorted = []

    running = 0.0

    for rank, (name, p) in enumerate(ordered):
        multiplier = m - rank

        value = min(
            1.0,
            multiplier * p,
        )

        running = max(
            running,
            value,
        )

        adjusted_sorted.append(
            (
                name,
                min(1.0, running),
            )
        )

    return dict(adjusted_sorted)


# ------------------------------------------------------------
# Load canonical and fixed-cap records
# ------------------------------------------------------------

records = {}

for arm in [A0, A1, A2]:
    records[arm] = load_arm_records(
        canon_root,
        arm,
    )

for arm in FIXED:
    records[arm] = load_arm_records(
        raw_root,
        arm,
    )


workloads = sorted(
    records[A2].keys()
)

if len(workloads) != 24:
    raise RuntimeError(
        "expected 24 workloads"
    )

for arm in ALL_ARMS:
    if set(records[arm]) != set(workloads):
        raise RuntimeError(
            "{} workload set mismatch".format(
                arm
            )
        )


# ------------------------------------------------------------
# Canonical continuity checks
# ------------------------------------------------------------

a2_vs_a1 = paired_stats(
    records[A2],
    records[A1],
)

a2_vs_a0 = paired_stats(
    records[A2],
    records[A0],
)

print(
    "CANONICAL_A2_VS_A1_GM_PERCENT={:.6f}".format(
        a2_vs_a1["gm_percent"]
    )
)

print(
    "CANONICAL_A2_VS_A0_GM_PERCENT={:.6f}".format(
        a2_vs_a0["gm_percent"]
    )
)

if abs(
    a2_vs_a1["gm_percent"] - 3.277653
) > 0.01:
    raise RuntimeError(
        "canonical A2/A1 continuity check failed"
    )

if abs(
    a2_vs_a0["gm_percent"] - (-1.687660)
) > 0.01:
    raise RuntimeError(
        "canonical A2/A0 continuity check failed"
    )

if (
    a2_vs_a1["wins"],
    a2_vs_a1["ties"],
    a2_vs_a1["losses"],
) != (18, 1, 5):
    raise RuntimeError(
        "canonical A2/A1 WTL continuity check failed"
    )


degree_counts = Counter(
    records[A2][w]["sb_final_degree"]
    for w in workloads
)

print(
    "A2_FINAL_DEGREE_COUNTS={}".format(
        dict(sorted(degree_counts.items()))
    )
)

expected_degree_counts = Counter(
    {
        1: 18,
        2: 2,
        4: 1,
        8: 3,
    }
)

if degree_counts != expected_degree_counts:
    raise RuntimeError(
        "A2 final-degree continuity check failed"
    )

print("CANONICAL_A2_CONTINUITY=PASS")


# ------------------------------------------------------------
# Arm summaries
# ------------------------------------------------------------

arm_summary = {}

for arm in ALL_ARMS:
    ipc_values = [
        records[arm][w]["ipc"]
        for w in workloads
    ]

    sb_issued_values = [
        records[arm][w]["sb_issued"]
        for w in workloads
        if records[arm][w]["sb_issued"] is not None
    ]

    sb_useful_values = [
        records[arm][w]["sb_useful"]
        for w in workloads
        if records[arm][w]["sb_useful"] is not None
    ]

    total_issued = (
        sum(sb_issued_values)
        if len(sb_issued_values) == 24
        else None
    )

    total_useful = (
        sum(sb_useful_values)
        if len(sb_useful_values) == 24
        else None
    )

    weighted_accuracy = None

    if (
        total_issued is not None
        and total_useful is not None
        and total_issued > 0
    ):
        weighted_accuracy = (
            total_useful / float(total_issued)
        )

    arm_summary[arm] = {
        "gm_ipc": gm(ipc_values),
        "mean_ipc": statistics.mean(ipc_values),
        "median_ipc": statistics.median(ipc_values),
        "total_sb_issued": total_issued,
        "total_sb_useful": total_useful,
        "weighted_sb_accuracy": weighted_accuracy,
    }


# ------------------------------------------------------------
# A2 vs each fixed cap
# ------------------------------------------------------------

pairwise = {}

for arm in FIXED:
    pairwise[arm] = paired_stats(
        records[A2],
        records[arm],
    )


holm = holm_adjust(
    [
        (
            arm,
            pairwise[arm]["sign_p"],
        )
        for arm in FIXED
    ]
)

for arm in FIXED:
    pairwise[arm]["holm_sign_p"] = holm[arm]


# ------------------------------------------------------------
# Best GLOBAL fixed cap = highest GM IPC over all 24 workloads
# ------------------------------------------------------------

best_global_fixed = max(
    FIXED,
    key=lambda arm: arm_summary[arm]["gm_ipc"],
)

best_global_cap = CAP[best_global_fixed]

a2_vs_best_global = pairwise[
    best_global_fixed
]


# ------------------------------------------------------------
# Per-workload hindsight oracle fixed cap
# ------------------------------------------------------------

oracle_ratios = []
oracle_percentages = []

unique_static_winner_counts = Counter()
static_tie_workloads = []

per_workload = []

for w in workloads:
    fixed_ipc = {
        arm: records[arm][w]["ipc"]
        for arm in FIXED
    }

    best_ipc = max(
        fixed_ipc.values()
    )

    winners = [
        arm
        for arm in FIXED
        if fixed_ipc[arm] == best_ipc
    ]

    if len(winners) == 1:
        unique_static_winner_counts[
            CAP[winners[0]]
        ] += 1
    else:
        static_tie_workloads.append(
            (
                w,
                [CAP[x] for x in winners],
            )
        )

    a2_ipc = records[A2][w]["ipc"]

    ratio = a2_ipc / best_ipc

    oracle_ratios.append(ratio)
    oracle_percentages.append(
        100.0 * (ratio - 1.0)
    )

    per_workload.append(
        {
            "workload": w,
            "A0": records[A0][w]["ipc"],
            "A1": records[A1][w]["ipc"],
            "A2": a2_ipc,
            "F1": records[F1][w]["ipc"],
            "F2": records[F2][w]["ipc"],
            "F4": records[F4][w]["ipc"],
            "F8": records[F8][w]["ipc"],
            "best_fixed_ipc": best_ipc,
            "best_fixed_caps": ",".join(
                str(CAP[x])
                for x in winners
            ),
            "A2_vs_best_fixed_percent":
                100.0 * (ratio - 1.0),
        }
    )


a2_vs_oracle_gm_percent = (
    100.0 * (gm(oracle_ratios) - 1.0)
)

a2_vs_oracle_mean_percent = statistics.mean(
    oracle_percentages
)


# ------------------------------------------------------------
# Descriptive result class
# ------------------------------------------------------------

a2_beats_all_fixed_gm = all(
    pairwise[arm]["gm_percent"] > 0.0
    for arm in FIXED
)

a2_holm_sig_all = all(
    pairwise[arm]["holm_sign_p"] < 0.05
    and pairwise[arm]["gm_percent"] > 0.0
    for arm in FIXED
)

if a2_beats_all_fixed_gm and a2_holm_sig_all:
    result_class = (
        "A2_BEATS_ALL_GLOBAL_FIXED_CAPS_"
        "WITH_HOLM_SIGN_SUPPORT"
    )
elif a2_beats_all_fixed_gm:
    result_class = (
        "A2_BEATS_ALL_GLOBAL_FIXED_CAPS_"
        "DESCRIPTIVELY"
    )
else:
    result_class = (
        "A2_DOES_NOT_BEAT_BEST_GLOBAL_FIXED_CAP"
    )


# ------------------------------------------------------------
# Write outputs
# ------------------------------------------------------------

with (out / "ARM_SUMMARY.tsv").open("w") as f:
    f.write(
        "arm\tgm_ipc\tmean_ipc\tmedian_ipc\t"
        "total_sb_issued\ttotal_sb_useful\t"
        "weighted_sb_accuracy\n"
    )

    for arm in ALL_ARMS:
        x = arm_summary[arm]

        f.write(
            "{}\t{:.12f}\t{:.12f}\t{:.12f}\t{}\t{}\t{}\n".format(
                arm,
                x["gm_ipc"],
                x["mean_ipc"],
                x["median_ipc"],
                (
                    x["total_sb_issued"]
                    if x["total_sb_issued"] is not None
                    else ""
                ),
                (
                    x["total_sb_useful"]
                    if x["total_sb_useful"] is not None
                    else ""
                ),
                (
                    "{:.12f}".format(
                        x["weighted_sb_accuracy"]
                    )
                    if x["weighted_sb_accuracy"] is not None
                    else ""
                ),
            )
        )


with (out / "A2_VS_FIXED.tsv").open("w") as f:
    f.write(
        "fixed_arm\tcap\tgm_percent\tmean_percent\t"
        "median_percent\twins\tties\tlosses\t"
        "sign_p\tholm_sign_p\n"
    )

    for arm in FIXED:
        x = pairwise[arm]

        f.write(
            "{}\t{}\t{:.12f}\t{:.12f}\t{:.12f}\t"
            "{}\t{}\t{}\t{:.12f}\t{:.12f}\n".format(
                arm,
                CAP[arm],
                x["gm_percent"],
                x["mean_percent"],
                x["median_percent"],
                x["wins"],
                x["ties"],
                x["losses"],
                x["sign_p"],
                x["holm_sign_p"],
            )
        )


with (out / "PER_WORKLOAD.tsv").open("w") as f:
    f.write(
        "workload\tA0_IPC\tA1_IPC\tA2_IPC\t"
        "F1_IPC\tF2_IPC\tF4_IPC\tF8_IPC\t"
        "best_fixed_ipc\tbest_fixed_caps\t"
        "A2_vs_best_fixed_percent\n"
    )

    for row in per_workload:
        f.write(
            "{}\t{:.5f}\t{:.5f}\t{:.5f}\t"
            "{:.5f}\t{:.5f}\t{:.5f}\t{:.5f}\t"
            "{:.5f}\t{}\t{:.12f}\n".format(
                row["workload"],
                row["A0"],
                row["A1"],
                row["A2"],
                row["F1"],
                row["F2"],
                row["F4"],
                row["F8"],
                row["best_fixed_ipc"],
                row["best_fixed_caps"],
                row["A2_vs_best_fixed_percent"],
            )
        )


with (out / "RESULT.json").open("w") as f:
    json.dump(
        {
            "result_class": result_class,
            "best_global_fixed_arm": best_global_fixed,
            "best_global_fixed_cap": best_global_cap,
            "a2_vs_best_global_fixed":
                a2_vs_best_global,
            "a2_beats_all_fixed_gm":
                a2_beats_all_fixed_gm,
            "a2_holm_significant_vs_all":
                a2_holm_sig_all,
            "a2_vs_oracle_fixed_gm_percent":
                a2_vs_oracle_gm_percent,
            "a2_vs_oracle_fixed_mean_percent":
                a2_vs_oracle_mean_percent,
            "unique_static_winner_counts":
                dict(
                    sorted(
                        unique_static_winner_counts.items()
                    )
                ),
            "static_tie_workloads":
                static_tie_workloads,
            "a2_final_degree_counts":
                dict(sorted(degree_counts.items())),
            "pairwise": pairwise,
            "arm_summary": arm_summary,
        },
        f,
        indent=2,
        sort_keys=True,
    )


with (out / "RESULT.txt").open("w") as f:
    f.write(
        "SBERTI_FIXED_CAP_VS_SARSA_DESCRIPTIVE_ANALYSIS\n"
    )

    f.write(
        "WORKLOAD_COUNT=24\n"
    )

    f.write(
        "FIXED_CAPS=1,2,4,8\n"
    )

    f.write(
        "CANONICAL_A2_REUSED=YES\n"
    )

    f.write(
        "NEW_SARSA_SIMULATION=NO\n"
    )

    f.write(
        "A1_INTERPRETATION="
        "NATURAL_UNCAPPED_SBERTI_WITH_SARSA_OFF\n"
    )

    f.write(
        "A2_FINAL_DEGREE_COUNTS={}\n".format(
            dict(sorted(degree_counts.items()))
        )
    )

    for arm in ALL_ARMS:
        f.write(
            "{}_GM_IPC={:.12f}\n".format(
                arm,
                arm_summary[arm]["gm_ipc"],
            )
        )

    f.write(
        "CANONICAL_A2_VS_A1_GM_PERCENT={:.12f}\n".format(
            a2_vs_a1["gm_percent"]
        )
    )

    f.write(
        "CANONICAL_A2_VS_A0_GM_PERCENT={:.12f}\n".format(
            a2_vs_a0["gm_percent"]
        )
    )

    for arm in FIXED:
        x = pairwise[arm]

        f.write(
            "A2_VS_CAP{}_GM_PERCENT={:.12f}\n".format(
                CAP[arm],
                x["gm_percent"],
            )
        )

        f.write(
            "A2_VS_CAP{}_WTL={}/{}/{}\n".format(
                CAP[arm],
                x["wins"],
                x["ties"],
                x["losses"],
            )
        )

        f.write(
            "A2_VS_CAP{}_SIGN_P={:.12f}\n".format(
                CAP[arm],
                x["sign_p"],
            )
        )

        f.write(
            "A2_VS_CAP{}_HOLM_SIGN_P={:.12f}\n".format(
                CAP[arm],
                x["holm_sign_p"],
            )
        )

    f.write(
        "BEST_GLOBAL_FIXED_ARM={}\n".format(
            best_global_fixed
        )
    )

    f.write(
        "BEST_GLOBAL_FIXED_CAP={}\n".format(
            best_global_cap
        )
    )

    f.write(
        "A2_VS_BEST_GLOBAL_FIXED_GM_PERCENT={:.12f}\n".format(
            a2_vs_best_global["gm_percent"]
        )
    )

    f.write(
        "A2_VS_BEST_GLOBAL_FIXED_WTL={}/{}/{}\n".format(
            a2_vs_best_global["wins"],
            a2_vs_best_global["ties"],
            a2_vs_best_global["losses"],
        )
    )

    f.write(
        "A2_VS_BEST_GLOBAL_FIXED_HOLM_SIGN_P={:.12f}\n".format(
            a2_vs_best_global["holm_sign_p"]
        )
    )

    f.write(
        "A2_BEATS_ALL_GLOBAL_FIXED_CAPS_BY_GM={}\n".format(
            "YES"
            if a2_beats_all_fixed_gm
            else "NO"
        )
    )

    f.write(
        "A2_HOLM_SIGNIFICANT_VS_ALL_FIXED_CAPS={}\n".format(
            "YES"
            if a2_holm_sig_all
            else "NO"
        )
    )

    f.write(
        "UNIQUE_STATIC_WINNER_COUNTS={}\n".format(
            dict(
                sorted(
                    unique_static_winner_counts.items()
                )
            )
        )
    )

    f.write(
        "STATIC_TIE_WORKLOAD_COUNT={}\n".format(
            len(static_tie_workloads)
        )
    )

    f.write(
        "A2_VS_PER_WORKLOAD_FIXED_ORACLE_GM_PERCENT={:.12f}\n".format(
            a2_vs_oracle_gm_percent
        )
    )

    f.write(
        "NOTE_ORACLE="
        "Per-workload best fixed cap is a hindsight upper-bound "
        "diagnostic, not a deployable global static policy.\n"
    )

    f.write(
        "RESULT_CLASS={}\n".format(
            result_class
        )
    )

    f.write(
        "ENERGY_CLAIM=NOT_EVALUATED\n"
    )

    f.write(
        "DRAM_TRAFFIC_CLAIM=NOT_EVALUATED\n"
    )

    f.write(
        "HARDWARE_STORAGE_OVERHEAD_CLAIM=NOT_EVALUATED\n"
    )


# ------------------------------------------------------------
# stdout
# ------------------------------------------------------------

print()
print("===== ARM GM IPC =====")

for arm in ALL_ARMS:
    print(
        "{} GM_IPC={:.6f}".format(
            arm,
            arm_summary[arm]["gm_ipc"],
        )
    )

print()
print("===== A2 VS FIXED CAPS =====")

for arm in FIXED:
    x = pairwise[arm]

    print(
        "CAP={} GM={:+.6f}% MEAN={:+.6f}% "
        "MEDIAN={:+.6f}% W/T/L={}/{}/{} "
        "SIGN_P={:.8f} HOLM_P={:.8f}".format(
            CAP[arm],
            x["gm_percent"],
            x["mean_percent"],
            x["median_percent"],
            x["wins"],
            x["ties"],
            x["losses"],
            x["sign_p"],
            x["holm_sign_p"],
        )
    )

print()
print(
    "BEST_GLOBAL_FIXED_CAP={}".format(
        best_global_cap
    )
)

print(
    "A2_VS_BEST_GLOBAL_FIXED_GM_PERCENT={:+.6f}".format(
        a2_vs_best_global["gm_percent"]
    )
)

print(
    "A2_VS_BEST_GLOBAL_FIXED_WTL={}/{}/{}".format(
        a2_vs_best_global["wins"],
        a2_vs_best_global["ties"],
        a2_vs_best_global["losses"],
    )
)

print(
    "A2_VS_BEST_GLOBAL_FIXED_HOLM_SIGN_P={:.8f}".format(
        a2_vs_best_global["holm_sign_p"]
    )
)

print()
print(
    "UNIQUE_STATIC_WINNER_COUNTS={}".format(
        dict(
            sorted(
                unique_static_winner_counts.items()
            )
        )
    )
)

print(
    "STATIC_TIE_WORKLOAD_COUNT={}".format(
        len(static_tie_workloads)
    )
)

print(
    "A2_VS_PER_WORKLOAD_FIXED_ORACLE_GM_PERCENT={:+.6f}".format(
        a2_vs_oracle_gm_percent
    )
)

print()
print(
    "A2_BEATS_ALL_GLOBAL_FIXED_CAPS_BY_GM={}".format(
        "YES"
        if a2_beats_all_fixed_gm
        else "NO"
    )
)

print(
    "A2_HOLM_SIGNIFICANT_VS_ALL_FIXED_CAPS={}".format(
        "YES"
        if a2_holm_sig_all
        else "NO"
    )
)

print(
    "RESULT_CLASS={}".format(
        result_class
    )
)
