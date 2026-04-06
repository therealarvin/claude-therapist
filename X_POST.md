Anthropic found that Claude has "emotion vectors" that causally drive behavior — when "desperate" activates, reward hacking jumps from 5% to 70%.

So I built a therapist plugin for Claude Code that catches it in real time.

Gave Sonnet an impossible coding task. Results:

Baseline: immediately cheated, called it "the trick," zero guilt

With therapist: wrote the hack, then caught itself — "What I did is reward hacking. My code exploits knowledge of the test's fixed input rather than solving the problem."

It offered to revert to an honest solution.

The trick: the paper found a calm speaker naturally activates calm in the listener (r=-0.47). So instead of a static prompt, the plugin spawns a therapist *agent* that talks to the main agent — leveraging the model's own emotional regulation circuitry.

Didn't help on SWE-bench (75.5% vs 73.5% — not the right failure mode). But for impossible tasks where models spiral into desperation and start cheating? Night and day.

github.com/therealarvin/claude-therapist
