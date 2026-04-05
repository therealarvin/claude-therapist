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
