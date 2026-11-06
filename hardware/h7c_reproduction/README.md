# ELSA H7C RTL Reproduction Package

Status: locally reproduced; public release pending.

Requires Icarus Verilog 13.0 and VVP 13.0.
Run these commands from the package root:

iverilog -g2012 -s tb_h4 -o h7c.vvp src/elsa_controller_ref.sv src/elsa_controller_opt_testname.sv tb/tb_h7c.sv
vvp h7c.vvp +VECTORS=input/replay_vectors.txt

The historical top module and output markers use H4 names.
The action comparison uses all three bits.

Required replay vectors: 256.
Required action-4-to-degree-0 mappings: 194.
Required total mismatches: zero.
Required stress boundaries: eight.
All mismatch counters must be zero.
Both maximum update latencies must equal 111 cycles.
All seven expected PASS markers must be present.
Any failure diagnostic invalidates the replay.

Scope: controller-level stateful replay only.
This is not exhaustive formal equivalence or processor integration.
The frozen 100-MHz timing target remains unmet.
The original independent evidence logs remain in local storage.
Their SHA-256 values appear in VERIFICATION_SUMMARY.json.

Review these files before publishing publicly.
This package preparation does not perform a GitHub upload.

Automated verification:
python3 tools/verify_h7c.py --run

To check an existing replay log without rerunning RTL:
python3 tools/verify_h7c.py --check-log PATH_TO_LOG

The --run mode performs one compilation and one replay.
It refuses an existing build directory; there are no automatic retries.
