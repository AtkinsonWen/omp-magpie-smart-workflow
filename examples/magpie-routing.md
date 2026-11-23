# Configure Magpie

Connect your providers first. Copy exact `provider/model` IDs from `magpie models`. The example uses five providers/model slots but only needs three distinct roles: a fast model, a general model, and a strong planner. Remove unavailable fallbacks from both `models=` and `use=`; never add placeholder IDs. Use a strong planner that supports tool calls. If you change planner IDs, also update `PLANNERS` in `auto-model-handoff.ts` and the OMP `slow` and `plan` roles.

**First install only.** Run `magpie groups` first. `group add` replaces a group with the same name, and `rule add` appends rules. If `smart-workflow` already exists, inspect and update it explicitly rather than rerunning this block.

```sh
magpie group add smart-workflow models=muze/gpt-6.1-terra,deepseek/deepseek-flash,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 routing=order stays=turn
magpie group set smart-workflow classifier=muze/gpt-6.1-terra
magpie group rule add smart-workflow compact use=muze/gpt-6.1-terra,deepseek/deepseek-flash
magpie group rule add smart-workflow use=muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 'intent=Architecture or migration design, unclear bug root cause, or a change that needs reasoning about interacting components, concurrency, or tricky invariants.'
magpie group rule add smart-workflow use=deepseek/deepseek-flash,muze/gpt-6.1-terra use-effort=low 'intent=A short factual lookup, one explicitly specified non-destructive command, or one exact mechanical edit with no design decisions or broad side effects.'
magpie group smart-workflow
```

Use Bash (including Git Bash on Windows) or PowerShell, not `cmd.exe` for the single-quoted arguments. Magpie evaluates rules from top to bottom. A match prioritizes its candidates; remaining group members may still serve on failure. Without a matching intent, the group's order starts with the general model. A compaction rule is separate from the active turn's model. A provider fallback can change the actual backend even within a turn.
