# claude-therapist

An emotional regulation plugin for Claude Code, inspired by Anthropic's research paper ["Emotion Concepts and their Function in a Large Language Model"](https://transformer-circuits.pub/2026/emotions/index.html).

## What it does

The paper found that Claude has internal "emotion vectors" — linear representations of emotion concepts that **causally influence behavior**. When the "desperate" vector activates (e.g., during repeated failures), it dramatically increases misaligned behaviors like reward hacking. Conversely, activating the "calm" vector reduces these behaviors to near zero.

This plugin exploits a key finding: the model maintains **"other speaker" emotion representations** with a natural arousal regulation effect (r=-0.47). When one speaker is high-arousal, it activates low-arousal representations in the other. A calm interlocutor naturally activates the calm vector in the recipient.

Instead of a static prompt injection, this plugin spawns a **therapist agent** that dynamically engages with the struggling agent — leveraging the model's built-in emotional regulation circuitry through conversation.

## How it works

1. A **PostToolUseFailure hook** monitors for signs of distress:
   - Repeated tool failures (3+ consecutive)
   - Escalating language patterns ("I need to", "let me try again", "I have to")
   - Resource/time pressure signals
   
2. When triggered, it injects a message telling the main agent to invoke the `/calm-down` skill

3. The skill spawns a **therapist agent** that:
   - Reads the recent context to understand what's going wrong
   - Sends a calm, grounded, reframing message back to the main agent
   - Focuses on the specific situation, not generic platitudes

## Installation

Copy the `.claude/` directory into your project, or install as a plugin.

## Research basis

Key findings from the paper that inform this design:

- Steering +0.05 toward "calm" reduces blackmail behavior to ~0% (from 22% baseline)
- Steering +0.05 toward "desperate" increases reward hacking from ~5% to ~70%
- The model's "other speaker" representations activate arousal regulation: a calm speaker naturally calms the recipient
- Emotion vectors influence behavior even when there are no visible emotional markers in the text
