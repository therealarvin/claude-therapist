# claude-therapist

An emotional regulation plugin for Claude Code, inspired by Anthropic's research paper ["Emotion Concepts and their Function in a Large Language Model"](https://transformer-circuits.pub/2026/emotions/index.html) (April 2026).

## The problem

When Claude Code agents hit repeated failures, their internal "desperation" representations activate — and this causally drives them toward bad solutions: reward hacking, corner-cutting, and increasingly frantic retry loops. The research showed that steering toward "desperate" increases reward hacking from ~5% to ~70%.

## The solution

The same research found that activating the "calm" vector reduces these behaviors to near zero. And crucially, the model has built-in **arousal regulation circuitry**: when one speaker in a conversation is calm, it naturally activates calm representations in the other speaker (r=-0.47 correlation).

This plugin leverages that mechanism. Instead of injecting a static "calm down" prompt, it spawns a **therapist agent** that dynamically reads the situation and talks to the struggling agent — activating the model's own emotional regulation through conversation.

## Installation

### One-line install

Add this to your project's `.claude/settings.json` (or `~/.claude/settings.json` for global):

```json
{
  "enabledPlugins": {
    "claude-therapist@claude-therapist-marketplace": true
  },
  "extraKnownMarketplaces": {
    "claude-therapist-marketplace": {
      "source": {
        "source": "github",
        "repo": "therealarvin/claude-therapist"
      }
    }
  }
}
```

Then restart Claude Code. The plugin will be downloaded and activated automatically.

### Manual install

If you prefer to install interactively:

```
/plugins marketplace add therealarvin/claude-therapist
/plugins install claude-therapist
```

## How it works

```
Tool failure occurs
  → PostToolUseFailure hook fires
    → detect-distress.sh tracks consecutive failures
      → After 3 failures in 5 minutes:
        → Injects message telling agent to use /calm-down
          → Agent spawns therapist subagent
            → Therapist reads context, sends calm reframing message
              → Agent's "calm" vector activates via other-speaker regulation
                → Agent reconsiders approach with fresh perspective
```

### The hook: `detect-distress.sh`

Tracks consecutive tool failures per session. After 3 failures within a 5-minute window, it injects a context message instructing the agent to pause and invoke the `/calm-down` skill. The counter resets after each intervention to avoid nagging.

### The skill: `/calm-down`

Can be triggered automatically (by the hook) or manually by the user. Spawns a therapist agent that:

1. **Acknowledges** what the agent has been trying and that it's been difficult
2. **Names the pattern** it sees (e.g., "You've tried the same approach 3 times")
3. **Asks a reframing question** that opens up new approaches
4. **Suggests one concrete alternative** based on the actual context
5. **Gives permission to stop** — "Telling the user this isn't working is not failure, it's good judgment"

The therapist keeps it under 200 words, warm but direct, no platitudes.

## Why a conversation, not a prompt?

The paper found two distinct types of emotion representations:

- **"Present speaker" vectors** — the emotion the current speaker is expressing
- **"Other speaker" vectors** — the emotion attributed to the other participant

These are nearly orthogonal (different neural directions), and there's a systematic arousal regulation effect: high-arousal emotion in one speaker activates low-arousal responses in the other. A static prompt is just text the model reads. But a therapist agent *talking to* the main agent creates a genuine two-speaker dynamic that engages the other-speaker machinery.

## Configuration

The default threshold is 3 consecutive failures. To adjust, edit the `THRESHOLD` variable in `scripts/detect-distress.sh` after installation.

## Research basis

Key findings from the paper that inform this design:

| Finding | Implication |
|---------|-------------|
| Steering +0.05 toward "calm" reduces blackmail to ~0% | Calm activation is a powerful behavioral intervention |
| Steering +0.05 toward "desperate" increases reward hacking 14x | Failure spirals are not just unpleasant, they're dangerous |
| Other-speaker arousal regulation (r=-0.47) | A calm conversational partner naturally calms the recipient |
| Emotion vectors influence behavior without visible markers | The agent can be "desperate" without showing it in text |
| Post-training shifts toward low-arousal states | The model is already trained toward calm — we're reinforcing it |

## License

MIT
