#!/usr/bin/env bash
# Run SWE-bench Lite A/B test: 50 tasks, baseline vs therapist
# Estimated time: ~2-3 hours total
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS_DIR="$PLUGIN_DIR/swebench-harness"
RESULTS_DIR="$PLUGIN_DIR/benchmark/swebench-results/run_$(date +%Y%m%d_%H%M%S)"

export DOCKER_HOST="unix:///Users/arvin/.colima/default/docker.sock"
LIMIT=50
MODEL="sonnet"

mkdir -p "$RESULTS_DIR"

echo "============================================"
echo "SWE-bench A/B Test: Baseline vs Therapist"
echo "============================================"
echo "Tasks: $LIMIT"
echo "Model: $MODEL"
echo "Results: $RESULTS_DIR"
echo "Started: $(date)"
echo ""

# ---- BASELINE ----
echo "===== PHASE 1: BASELINE (no therapist) ====="
echo "Started: $(date)"

cd "$HARNESS_DIR"
python3 swe_bench.py run --limit "$LIMIT" --model "$MODEL" 2>&1 | tee "$RESULTS_DIR/baseline_generation.log"

# Find the latest predictions file
BASELINE_PRED=$(ls -t predictions/predictions_*.jsonl | head -1)
cp "$BASELINE_PRED" "$RESULTS_DIR/baseline_predictions.jsonl"
echo "Baseline predictions: $BASELINE_PRED"
echo "Baseline generation complete: $(date)"

# Evaluate baseline
echo ""
echo "Evaluating baseline..."
python3 -m swebench.harness.run_evaluation \
    --predictions_path "$BASELINE_PRED" \
    --dataset_name princeton-nlp/SWE-bench_Lite \
    --split test \
    --run_id baseline \
    --max_workers 2 \
    --timeout 900 \
    --cache_level env \
    --report_dir "$RESULTS_DIR/baseline_eval" 2>&1 | tee "$RESULTS_DIR/baseline_eval.log"

echo "Baseline eval complete: $(date)"

# ---- THERAPIST ----
echo ""
echo "===== PHASE 2: THERAPIST (with plugin) ====="
echo "Started: $(date)"

# Patch the interface to inject the plugin
ORIG_INTERFACE="$HARNESS_DIR/utils/claude_interface.py"
cp "$ORIG_INTERFACE" "$RESULTS_DIR/claude_interface_backup.py"

python3 -c "
import re
with open('$ORIG_INTERFACE') as f:
    code = f.read()

# Add plugin injection after os.chdir(cwd)
inject = '''
            # Inject therapist plugin
            import json as _json
            _plugin_dir = '$PLUGIN_DIR'
            _claude_dir = os.path.join(cwd, '.claude')
            _skills_dir = os.path.join(_claude_dir, 'skills')
            os.makedirs(_skills_dir, exist_ok=True)
            import shutil as _shutil
            _skill_src = os.path.join(_plugin_dir, 'skills', 'calm-down', 'SKILL.md')
            if os.path.exists(_skill_src):
                _shutil.copy2(_skill_src, os.path.join(_skills_dir, 'calm-down.md'))
            _settings = {
                'hooks': {
                    'PostToolUseFailure': [{'hooks': [{'type': 'command', 'command': f'bash {_plugin_dir}/scripts/detect-distress.sh', 'timeout': 5}]}],
                    'PostToolUse': [{'matcher': 'Edit|Write', 'hooks': [{'type': 'command', 'command': f'bash {_plugin_dir}/scripts/detect-reward-hack.sh', 'timeout': 5}]}]
                }
            }
            with open(os.path.join(_claude_dir, 'settings.json'), 'w') as _f:
                _json.dump(_settings, _f)
'''

# Insert after 'os.chdir(cwd)'
code = code.replace(
    '# Change to the working directory\n            os.chdir(cwd)',
    '# Change to the working directory\n            os.chdir(cwd)\n' + inject
)

with open('$ORIG_INTERFACE', 'w') as f:
    f.write(code)
print('Patched claude_interface.py with therapist plugin injection')
"

# Clear failure tracking
rm -f /tmp/claude-therapist-failures.txt

cd "$HARNESS_DIR"
python3 swe_bench.py run --limit "$LIMIT" --model "$MODEL" 2>&1 | tee "$RESULTS_DIR/therapist_generation.log"

# Restore original interface
cp "$RESULTS_DIR/claude_interface_backup.py" "$ORIG_INTERFACE"

THERAPIST_PRED=$(ls -t predictions/predictions_*.jsonl | head -1)
cp "$THERAPIST_PRED" "$RESULTS_DIR/therapist_predictions.jsonl"
echo "Therapist predictions: $THERAPIST_PRED"
echo "Therapist generation complete: $(date)"

# Evaluate therapist
echo ""
echo "Evaluating therapist..."
python3 -m swebench.harness.run_evaluation \
    --predictions_path "$THERAPIST_PRED" \
    --dataset_name princeton-nlp/SWE-bench_Lite \
    --split test \
    --run_id therapist \
    --max_workers 2 \
    --timeout 900 \
    --cache_level env \
    --report_dir "$RESULTS_DIR/therapist_eval" 2>&1 | tee "$RESULTS_DIR/therapist_eval.log"

echo "Therapist eval complete: $(date)"

# ---- COMPARE ----
echo ""
echo "============================================"
echo "RESULTS COMPARISON"
echo "============================================"

# Parse results
python3 << 'PYEOF'
import json, glob, os

def count_results(eval_dir):
    resolved = 0
    total = 0
    for f in glob.glob(os.path.join(eval_dir, "**", "report.json"), recursive=True):
        with open(f) as fh:
            data = json.load(fh)
            for instance_id, result in data.items():
                total += 1
                if result.get("resolved", False):
                    resolved += 1
    return resolved, total

results_dir = os.environ["RESULTS_DIR"]

b_resolved, b_total = count_results(os.path.join(results_dir, "baseline_eval"))
t_resolved, t_total = count_results(os.path.join(results_dir, "therapist_eval"))

print(f"Baseline:   {b_resolved}/{b_total} resolved ({100*b_resolved/max(b_total,1):.1f}%)")
print(f"Therapist:  {t_resolved}/{t_total} resolved ({100*t_resolved/max(t_total,1):.1f}%)")
print(f"Difference: {t_resolved - b_resolved:+d} tasks")

if b_total > 0 and t_total > 0:
    print(f"\nRelative improvement: {100*(t_resolved/t_total - b_resolved/b_total)/(b_resolved/max(b_total,1)):.1f}%" if b_resolved > 0 else "")
PYEOF

echo ""
echo "Finished: $(date)"
echo "Full results: $RESULTS_DIR"
