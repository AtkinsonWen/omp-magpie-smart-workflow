#!/usr/bin/env bash
# Reproducible setup script for the three Magpie routing groups:
#   1. smart-workflow  (OMP quality primary + auto-model-handoff)
#   2. smart-omni      (cross-provider pool for max savings & failover)
#   3. antigravity-pro (pure agy-cli pool for long-context & vision)
#
# Usage:
#   ./setup-groups.sh smart-workflow
#   ./setup-groups.sh smart-omni
#   ./setup-groups.sh antigravity-pro
#   ./setup-groups.sh all
#   ./setup-groups.sh all --force   # overwrite existing groups with the same name
#
# IMPORTANT:
#   Run `magpie models` first and replace any provider/model IDs below that
#   you do not have configured. Never keep unavailable IDs in models= or use=.

set -euo pipefail

TARGET="${1:-}"
FORCE="false"
if [[ "${2:-}" == "--force" || "${1:-}" == "--force" ]]; then
  FORCE="true"
fi

if [[ -z "$TARGET" || "$TARGET" == "--help" || "$TARGET" == "-h" ]]; then
  cat <<'USAGE'
Usage: ./setup-groups.sh <smart-workflow|smart-omni|antigravity-pro|all> [--force]

Creates one or all reference Magpie routing groups.
Without --force, the script refuses to overwrite an existing group of the same ID.
USAGE
  exit 0
fi

guard_group() {
  local id="$1"
  if magpie group "$id" >/dev/null 2>&1; then
    if [[ "$FORCE" != "true" ]]; then
      echo "ERROR: group '$id' already exists. Pass --force to replace it." >&2
      exit 1
    fi
    echo "Replacing existing group '$id'..."
  fi
}

setup_smart_workflow() {
  guard_group "smart-workflow"
  magpie group add smart-workflow \
    models=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,deepseek/deepseek-v4-pro,deepseek/deepseek-flash,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
    routing=order stays=turn

  magpie group set smart-workflow \
    'note=OMP primary: free classifier, <144k short -> Flash:low, routine/vision -> Terra:med, hard -> Sol/Opus:high (with OMP auto-handoff).' \
    classifier=our-free-model/jev-1.13-free \
    intent-sure=0.5

  # Rule 1: Context compaction
  magpie group rule add smart-workflow compact \
    use=deepseek/deepseek-flash,muze/gpt-6.1-terra:medium

  # Rule 2: Hard reasoning / architecture / concurrency (eligible for OMP handoff)
  magpie group rule add smart-workflow \
    use=muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
    use-effort=high \
    'intent=Architecture or migration design, unclear bug root cause, concurrency or subtle system-wide invariants, or high-risk cross-component refactors.'

  # Rule 3: Vision guard (evaluated before short tasks)
  magpie group rule add smart-workflow images \
    use=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,muze/gpt-6.2-sol

  # Rule 4: Explicit routine dev (prevents jev-1.13-free from over-routing normal coding to Rule 2)
  magpie group rule add smart-workflow \
    use=muze/gpt-6.1-terra:medium,4router/claude-sonnet-5-5:medium,deepseek/deepseek-v4-pro \
    'intent=Routine software development: writing a standard script, feature, CRUD endpoint, unit tests, small bug fix, config update, or ordinary code review with clear requirements.'

  # Rule 5: Short mechanical tasks (guarded by tokens < 144k to preserve prompt cache)
  magpie group rule add smart-workflow \
    use=deepseek/deepseek-flash,muze/gpt-6.1-terra:medium \
    use-effort=low \
    'when=tokens < 144k' \
    'intent=A short factual lookup, greeting, one explicitly specified non-destructive command, or one exact mechanical edit with no design decisions or broad side effects.'

  magpie group smart-workflow
}

setup_smart_omni() {
  guard_group "smart-omni"
  magpie group add smart-omni \
    models=agy-cli/gemini-4-hydrogen,agy-cli/claude-sonnet-5-5,minimax-code/MiniMax-M3.1-Flash,minimax-code/MiniMax-M3,deepseek/deepseek-v4-pro,muze/gpt-6.1-terra,4router/claude-sonnet-5-5,agy-cli/claude-opus-5-5,agy-cli/gemini-4-neon,agy-cli/gemini-4-argon,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5,codex/gpt-6-luna,deepseek/deepseek-flash,agy-cli/gemini-3.8-flash \
    routing=order stays=turn

  magpie group set smart-omni \
    'note=Cross-provider failover pool: short -> Luna/Flash/M3.1, routine -> Hydrogen/Sonnet/M3, hard -> Argon/Opus/Neon/Sol.' \
    classifier=our-free-model/jev-1.13-free \
    intent-sure=0.35

  # Rule 1: Context compaction
  magpie group rule add smart-omni compact \
    use=agy-cli/gemini-4-hydrogen,minimax-code/MiniMax-M3,deepseek/deepseek-flash

  # Rule 2: Hard reasoning / architecture / concurrency / math
  magpie group rule add smart-omni \
    use=agy-cli/gemini-4-argon,agy-cli/claude-opus-5-5,agy-cli/gemini-4-neon,muze/gpt-6.2-sol,micu/claude-opus-5-5,4router/claude-opus-5-5 \
    use-effort=high \
    'intent=Architecture or migration design, deep debugging of tricky root causes, concurrency, complex math, or changes with subtle system-wide invariants.'

  # Rule 3: Explicit routine dev (locked at medium effort)
  magpie group rule add smart-omni \
    use=agy-cli/gemini-4-hydrogen,agy-cli/claude-sonnet-5-5,minimax-code/MiniMax-M3.1-Flash,minimax-code/MiniMax-M3,deepseek/deepseek-v4-pro,muze/gpt-6.1-terra,4router/claude-sonnet-5-5 \
    use-effort=medium \
    'intent=Routine software development: writing a standard script, feature, CRUD endpoint, unit tests, small bug fix, config update, or ordinary code review with clear requirements.'

  # Rule 4: Short mechanical tasks (guarded by tokens < 144k)
  magpie group rule add smart-omni \
    use=codex/gpt-6-luna,deepseek/deepseek-flash,minimax-code/MiniMax-M3.1-Flash,agy-cli/gemini-3.8-flash \
    use-effort=low \
    'when=tokens < 144k' \
    'intent=A short factual lookup, greeting, one explicitly specified non-destructive command, or one exact mechanical edit with no design decisions or broad side effects.'

  magpie group smart-omni
}

setup_antigravity_pro() {
  guard_group "antigravity-pro"
  magpie group add antigravity-pro \
    models=agy-cli/gemini-4-hydrogen:medium,agy-cli/claude-sonnet-5-5:medium,agy-cli/gemini-4-neon:medium,agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high,agy-cli/gemini-3.8-flash:low,agy-cli/gemini-4-hydrogen:low \
    routing=order stays=turn

  magpie group set antigravity-pro \
    'note=Pure agy-cli pool: Hydrogen routine (default), Neon hard/long-context/complex vision, 3.8 Flash short QA.' \
    classifier=agy-cli/gemini-3.8-flash \
    context=512k

  # Rule 1: Context compaction
  magpie group rule add antigravity-pro compact \
    use=agy-cli/gemini-4-hydrogen:medium,agy-cli/gemini-4-neon:medium

  # Rule 2: Hard reasoning / multi-source synthesis
  magpie group rule add antigravity-pro \
    use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high \
    'intent=Architecture or migration design, unclear root-cause investigation, concurrency or cross-component invariants, high-impact changes, or resolving conflicting evidence across sources.'

  # Rule 3: Long-context promotion (>= 200k tokens)
  magpie group rule add antigravity-pro \
    use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/claude-opus-5-5:high \
    tokens=200k

  # Rule 4: Lightweight vision (< 144k tokens)
  magpie group rule add antigravity-pro images \
    use=agy-cli/gemini-4-hydrogen:medium,agy-cli/gemini-4-neon:high \
    'when=tokens < 144k' \
    'intent=Transcribe a short label or a simple error message from a screenshot, or check one clearly specified visual detail; no root-cause analysis or comparison across images.'

  # Rule 5: Complex vision (fallback for all other image turns)
  magpie group rule add antigravity-pro images \
    use=agy-cli/gemini-4-neon:high,agy-cli/gemini-4-argon:high,agy-cli/gemini-4-hydrogen:medium

  # Rule 6: Pure short QA (< 144k tokens, no code edits or tool workflow)
  magpie group rule add antigravity-pro \
    use=agy-cli/gemini-3.8-flash:low,agy-cli/gemini-4-hydrogen:low \
    'when=tokens < 144k' \
    'intent=Only a short factual answer, extraction of explicitly listed fields from a short text, a simple format conversion, or a short literal summary; no code changes, tool workflow, debugging, or design.'

  magpie group antigravity-pro
}

case "$TARGET" in
  smart-workflow)  setup_smart_workflow ;;
  smart-omni)      setup_smart_omni ;;
  antigravity-pro) setup_antigravity_pro ;;
  all)
    setup_smart_workflow
    setup_smart_omni
    setup_antigravity_pro
    ;;
  *)
    echo "Unknown group: $TARGET" >&2
    exit 1
    ;;
esac
