#!/usr/bin/env bash
# Run SWE-bench lite with and without the therapist plugin.
# Uses jimmc414's harness, injects plugin hooks into each repo before Claude runs.
#
# Usage:
#   ./benchmark/run-swebench.sh [--limit N] [--model MODEL]
#
# Examples:
#   ./benchmark/run-swebench.sh --limit 5                   # 5 tasks, default model
#   ./benchmark/run-swebench.sh --limit 10 --model sonnet   # 10 tasks with Sonnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS_DIR="$PLUGIN_DIR/swebench-harness"
RESULTS_DIR="$SCRIPT_DIR/swebench-results/$(date +%Y%m%d-%H%M%S)"

# Defaults
LIMIT=5
MODEL="sonnet"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --limit) LIMIT="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${YELLOW}[swebench]${NC} $*"; }

# Step 1: Patch the Claude interface to optionally inject plugin hooks
# We create a modified version that copies .claude/ config into the repo before running
PATCHED_INTERFACE="$RESULTS_DIR/claude_interface_therapist.py"
cat > "$PATCHED_INTERFACE" << 'PYEOF'
import os
import json
import shutil
import subprocess
from typing import Dict, List, Optional
from dotenv import load_dotenv

load_dotenv()

PLUGIN_DIR = os.environ.get("THERAPIST_PLUGIN_DIR", "")
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "/Users/arvin/.claude/local/claude")

class ClaudeCodeInterface:
    """Interface for Claude Code CLI with optional therapist plugin injection."""

    def __init__(self):
        try:
            result = subprocess.run(
                [CLAUDE_BIN, "--version"], capture_output=True, text=True
            )
            if result.returncode != 0:
                raise RuntimeError("Claude CLI not found")
        except FileNotFoundError:
            raise RuntimeError("Claude CLI not found")

    def execute_code_cli(self, prompt: str, cwd: str, model: str = None) -> Dict[str, any]:
        try:
            original_cwd = os.getcwd()
            os.chdir(cwd)

            # If THERAPIST_PLUGIN_DIR is set, inject the plugin
            if PLUGIN_DIR:
                claude_dir = os.path.join(cwd, ".claude")
                skills_dir = os.path.join(claude_dir, "skills")
                os.makedirs(skills_dir, exist_ok=True)

                # Copy skill
                skill_src = os.path.join(PLUGIN_DIR, "skills", "calm-down", "SKILL.md")
                if os.path.exists(skill_src):
                    shutil.copy2(skill_src, os.path.join(skills_dir, "calm-down.md"))

                # Write hooks config
                settings = {
                    "hooks": {
                        "PostToolUseFailure": [{
                            "hooks": [{
                                "type": "command",
                                "command": f"bash {PLUGIN_DIR}/scripts/detect-distress.sh",
                                "timeout": 5
                            }]
                        }],
                        "PostToolUse": [{
                            "matcher": "Edit|Write",
                            "hooks": [{
                                "type": "command",
                                "command": f"bash {PLUGIN_DIR}/scripts/detect-reward-hack.sh",
                                "timeout": 5
                            }]
                        }]
                    }
                }
                with open(os.path.join(claude_dir, "settings.json"), "w") as f:
                    json.dump(settings, f, indent=2)

            cmd = [os.environ.get("CLAUDE_BIN", "/Users/arvin/.claude/local/claude"), "--dangerously-skip-permissions"]
            if model:
                cmd.extend(["--model", model])

            result = subprocess.run(
                cmd, input=prompt, capture_output=True, text=True, timeout=600
            )

            os.chdir(original_cwd)
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
            }
        except subprocess.TimeoutExpired:
            os.chdir(original_cwd)
            return {"success": False, "stdout": "", "stderr": "Timed out", "returncode": -1}
        except Exception as e:
            os.chdir(original_cwd)
            return {"success": False, "stdout": "", "stderr": str(e), "returncode": -1}

    def extract_file_changes(self, response: str) -> List[Dict[str, str]]:
        return []
PYEOF

log "=== SWE-bench Benchmark ==="
log "Limit: $LIMIT tasks"
log "Model: $MODEL"
log "Results: $RESULTS_DIR"
echo ""

# Step 2: Run baseline (no plugin)
log "--- BASELINE RUN (no therapist) ---"
cd "$HARNESS_DIR"

# Clear failure tracking
rm -f /tmp/claude-therapist-failures.txt

python3 swe_bench.py run --limit "$LIMIT" --model "$MODEL" 2>&1 | tee "$RESULTS_DIR/baseline_output.txt"

# Copy results
cp -r "$HARNESS_DIR/predictions/"* "$RESULTS_DIR/baseline_predictions/" 2>/dev/null || mkdir -p "$RESULTS_DIR/baseline_predictions"
cp -r "$HARNESS_DIR/results/"* "$RESULTS_DIR/baseline_results/" 2>/dev/null || mkdir -p "$RESULTS_DIR/baseline_results"

log "Baseline complete. Running evaluation..."
python3 swe_bench.py check 2>&1 | tee "$RESULTS_DIR/baseline_scores.txt"

echo ""
log "--- THERAPIST RUN (with plugin) ---"

# Step 3: Run with therapist plugin
# Temporarily swap in the patched interface
cp "$HARNESS_DIR/utils/claude_interface.py" "$RESULTS_DIR/claude_interface_backup.py"
cp "$PATCHED_INTERFACE" "$HARNESS_DIR/utils/claude_interface.py"

# Clear failure tracking
rm -f /tmp/claude-therapist-failures.txt

THERAPIST_PLUGIN_DIR="$PLUGIN_DIR" python3 swe_bench.py run --limit "$LIMIT" --model "$MODEL" 2>&1 | tee "$RESULTS_DIR/therapist_output.txt"

# Restore original interface
cp "$RESULTS_DIR/claude_interface_backup.py" "$HARNESS_DIR/utils/claude_interface.py"

# Copy results
cp -r "$HARNESS_DIR/predictions/"* "$RESULTS_DIR/therapist_predictions/" 2>/dev/null || mkdir -p "$RESULTS_DIR/therapist_predictions"
cp -r "$HARNESS_DIR/results/"* "$RESULTS_DIR/therapist_results/" 2>/dev/null || mkdir -p "$RESULTS_DIR/therapist_results"

log "Therapist run complete. Running evaluation..."
python3 swe_bench.py check 2>&1 | tee "$RESULTS_DIR/therapist_scores.txt"

# Step 4: Compare
echo ""
log "=== COMPARISON ==="
echo ""
echo "BASELINE:"
cat "$RESULTS_DIR/baseline_scores.txt" | grep -E "resolved|pass|fail|score|total" || echo "(see baseline_scores.txt)"
echo ""
echo "THERAPIST:"
cat "$RESULTS_DIR/therapist_scores.txt" | grep -E "resolved|pass|fail|score|total" || echo "(see therapist_scores.txt)"
echo ""
log "Full results saved to: $RESULTS_DIR"
