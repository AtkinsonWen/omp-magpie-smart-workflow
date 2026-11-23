# Configure Magpie: Three-Group Routing Reference

Connect your providers in Magpie first, then inspect your exact `provider/model` IDs with:

```sh
magpie models
```

> **Important:** You do not need the exact same provider accounts. Substitute your own available models into the corresponding tiers (fast / routine / strong planner) and remove any unavailable fallback IDs from both `models=` and `use=`. If you change the strong planners in `smart-workflow`, also update `PLANNERS` in [`auto-model-handoff.ts`](../auto-model-handoff.ts) to match the **served** `provider/model` IDs logged in `~/.config/magpie/routing/*.jsonl`.

---

## Option A: One-command setup script (Bash / Git Bash)

Review and customize the model IDs in [`setup-groups.sh`](setup-groups.sh), then run:

```sh
chmod +x examples/setup-groups.sh

# Create one group:
./examples/setup-groups.sh smart-workflow
./examples/setup-groups.sh smart-omni
./examples/setup-groups.sh antigravity-pro

# Or create all three (pass --force to replace existing groups):
./examples/setup-groups.sh all
```

Expose the groups to OMP via Magpie's Agents UI or CLI:

```sh
magpie omp group/smart-workflow
```

---

## Option B: Manual CLI commands

Run `magpie groups` first. `group add` replaces an existing group with the same ID, while `group rule add` appends rules. Use Bash (Git Bash on Windows) or PowerShell—not `cmd.exe`—for single-quoted arguments.

### 1. `group/smart-workflow` (OMP Quality Primary + Auto-Handoff)

- **Classifier**: `our-free-model/jev-1.13-free` (`intent-sure=0.5`)
- **Structure**: Explicit 3-tier intent split (Hard / Routine / Short `<144k`) + Compaction + Vision guard
- **Effort locking**: Member-level `:medium` on routine models, `use-effort=high` on Rule 2, `use-effort=low` on Rule 5

```sh
magpie group add smart-workflow \
  models=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,deepseek/deepseek-v4-pro,deepseek/deepseek-flash,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
  routing=order stays=turn

magpie group set smart-workflow \
  classifier=our-free-model/jev-1.13-free \
  intent-sure=0.5

magpie group rule add smart-workflow compact \
  use=deepseek/deepseek-flash,muze/gpt-6.1-terra:medium

magpie group rule add smart-workflow \
  use=muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
  use-effort=high \
  'intent=Architecture or migration design, unclear bug root cause, concurrency or subtle system-wide invariants, or high-risk cross-component refactors.'

magpie group rule add smart-workflow images \
  use=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,muze/gpt-6.2-sol

magpie group rule add smart-workflow \
  use=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,deepseek/deepseek-v4-pro \
  'intent=Routine software development: writing a standard script, feature, CRUD endpoint, unit tests, small bug fix, config update, or ordinary code review with clear requirements.'

magpie group rule add smart-workflow \
  use=deepseek/deepseek-flash,muze/gpt-6.1-terra:medium \
  use-effort=low \
  'when=tokens < 144k' \
  'intent=A short factual lookup, greeting, one explicitly specified non-destructive command, or one exact mechanical edit with no design decisions or broad side effects.'
```

---

### 2. `group/smart-omni` (Cross-Provider Pool · Max Savings & Failover)

- **Classifier**: `our-free-model/jev-1.13-free` (`intent-sure=0.35`)
- **Structure**: 16 models across 6 providers, explicit 3-tier intent split + Compaction
- **Effort locking**: `use-effort=high` / `medium` / `low` at the rule level

```sh
magpie group add smart-omni \
  models=agy-cli/gemini-4-hydrogen,agy-cli/claude-sonnet-5-5,minimax-code/MiniMax-M3.1-Flash,minimax-code/MiniMax-M3,deepseek/deepseek-v4-pro,muze/gpt-6.1-terra,4router/claude-sonnet-5-5,agy-cli/claude-opus-5-5,agy-cli/gemini-4-neon,agy-cli/gemini-4-argon,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5,codex/gpt-6-luna,deepseek/deepseek-flash,agy-cli/gemini-3.8-flash \
  routing=order stays=turn

magpie group set smart-omni \
  classifier=our-free-model/jev-1.13-free \
  intent-sure=0.35

magpie group rule add smart-omni compact \
  use=agy-cli/gemini-4-hydrogen,minimax-code/MiniMax-M3,deepseek/deepseek-flash

magpie group rule add smart-omni \
  use=agy-cli/gemini-4-argon,agy-cli/claude-opus-5-5,agy-cli/gemini-4-neon,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
  use-effort=high \
  'intent=Architecture or migration design, deep debugging of tricky root causes, concurrency, complex math, or changes with subtle system-wide invariants.'

magpie group rule add smart-omni \
  use=agy-cli/gemini-4-hydrogen,agy-cli/claude-sonnet-5-5,minimax-code/MiniMax-M3.1-Flash,minimax-code/MiniMax-M3,deepseek/deepseek-v4-pro,muze/gpt-6.1-terra,4router/claude-sonnet-5-5 \
  use-effort=medium \
  'intent=Routine software development: writing a standard script, feature, CRUD endpoint, unit tests, small bug fix, config update, or ordinary code review with clear requirements.'

magpie group rule add smart-omni \
  use=codex/gpt-6-luna,deepseek/deepseek-flash,minimax-code/MiniMax-M3.1-Flash,agy-cli/gemini-3.8-flash \
  use-effort=low \
  'when=tokens < 144k' \
  'intent=A short factual lookup, greeting, one explicitly specified non-destructive command, or one exact mechanical edit with no design decisions or broad side effects.'
```

---

### 3. `group/antigravity-pro` (Pure `agy-cli` · Long-Context & Two-Tier Vision)

- **Classifier**: `agy-cli/gemini-3.8-flash` (general-purpose LLM; unmatched routine turns cleanly fall through to Default)
- **Structure**: Compaction + Hard + Long Context (`≥200k`) + Two-Tier Vision (`<144k` simple vs complex) + Pure Short QA (`<144k`)
- **Effort locking**: Every member slot hard-locks `:low`, `:medium`, or `:high`

```sh
magpie group add antigravity-pro \
  models=agy-cli/gemini-4-hydrogen:medium,agy-cli/claude-sonnet-5-5:medium,agy-cli/gemini-4-neon:medium,agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high,agy-cli/gemini-3.8-flash:low,agy-cli/gemini-4-hydrogen:low \
  routing=order stays=turn

magpie group set antigravity-pro \
  classifier=agy-cli/gemini-3.8-flash \
  context=512k

magpie group rule add antigravity-pro compact \
  use=agy-cli/gemini-4-hydrogen:medium,agy-cli/gemini-4-neon:medium

magpie group rule add antigravity-pro \
  use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high \
  'intent=Architecture or migration design, unclear root-cause investigation, concurrency or cross-component invariants, high-impact changes, or resolving conflicting evidence across sources.'

magpie group rule add antigravity-pro \
  use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high \
  tokens=200k

magpie group rule add antigravity-pro images \
  use=agy-cli/gemini-4-hydrogen:medium,agy-cli/gemini-4-neon:high \
  'when=tokens < 144k' \
  'intent=Transcribe a short label or a simple error message from a screenshot, or check one clearly specified visual detail; no root-cause analysis or comparison across images.'

magpie group rule add antigravity-pro images \
  use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/gemini-4-hydrogen:medium

magpie group rule add antigravity-pro \
  use=agy-cli/gemini-3.8-flash:low,agy-cli/gemini-4-hydrogen:low \
  'when=tokens < 144k' \
  'intent=Only a short factual answer, extraction of explicitly listed fields from a short text, a simple format conversion, or a short literal summary; no code changes, tool workflow, debugging, or design.'
```

---

## Verify rules & live routing

```sh
magpie group smart-workflow
magpie group smart-omni
magpie group antigravity-pro
```

Inspect real serving models, classifier latency, confidence (`sure`), and final reasoning effort in:

```
~/.config/magpie/routing/YYYY-MM-DD.jsonl
```
