#!/bin/zsh
# Run an autonomous Agent Deck perf collection pass.
#
# Launches a SEPARATE Debug instance of Agent Deck with AGENTDECK_AUTOPERF=1:
# it runs accessory + offscreen by default (or visible with --visible), self-drives the
# built-in ScrollBench + STREAMSIM + SidebarExpandBench journeys against the
# real transcript, and quits — leaving a rollup at /tmp/agentdeck-autoperf-rollup.md plus hang/hitch
# backtraces under /tmp/agentdeck-hang-*.txt.
#
# Runs against the REAL data roots. Do NOT run it while the live Agent Deck is
# open (they share the session store). Journeys are non-destructive.
#
# Usage:
#   scripts/run-autoperf.sh [--sidebar-only] [--visible] [path/to/Agent Deck.app]
set -euo pipefail
setopt NULL_GLOB   # rm globs below are no-ops when nothing matches

SIDEBAR_ONLY=0
VISIBLE=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --sidebar-only) SIDEBAR_ONLY=1 ;;
    --visible) VISIBLE=1 ;;
    *) echo "error: unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

APP="${1:-}"
if [[ -z "$APP" ]]; then
  APP="$(find ~/Library/Developer/Xcode/DerivedData/agent-deck-*/Build/Products/Debug -maxdepth 1 -name 'Agent Deck.app' 2>/dev/null | head -1)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: Agent Deck.app (Debug) not found. Build first, or pass its path." >&2
  exit 1
fi

# Clear prior run artifacts so the rollup reflects only this pass.
rm -f /tmp/agentdeck-perf.txt /tmp/agentdeck-autoperf-rollup.md /tmp/agentdeck-hang-*.txt /tmp/agentdeck-hitch-*.txt 2>/dev/null || true

ENV_ARGS=(AGENTDECK_AUTOPERF=1)
MODE="AutoPerf"
VISIBILITY="background, offscreen"
if [[ "$SIDEBAR_ONLY" == "1" ]]; then
  ENV_ARGS+=(AGENTDECK_AUTOPERF_SIDEBAR_ONLY=1)
  MODE="AutoPerf SidebarExpandBench-only"
fi
if [[ "$VISIBLE" == "1" ]]; then
  ENV_ARGS+=(AGENTDECK_AUTOPERF_VISIBLE=1)
  VISIBILITY="visible-window"
fi

echo "Launching $APP in $MODE mode ($VISIBILITY)…"
env "${ENV_ARGS[@]}" "$APP/Contents/MacOS/Agent Deck" &
APPPID=$!

# Wait for the app to terminate itself (it quits after writing the rollup), with
# a hard cap beyond AutoPerfCoordinator's internal timeout.
DEADLINE=$(( $(date +%s) + 360 ))
while kill -0 "$APPPID" 2>/dev/null; do
  if [[ $(date +%s) -ge $DEADLINE ]]; then
    echo "error: AutoPerf run exceeded 6 min; killing." >&2
    kill "$APPPID" 2>/dev/null || true
    exit 2
  fi
  sleep 1
done

ROLLUP="/tmp/agentdeck-autoperf-rollup.md"
if [[ -f "$ROLLUP" ]]; then
  echo "AutoPerf complete. Rollup: $ROLLUP"
  sed -n '1,40p' "$ROLLUP"
else
  echo "error: rollup not written. Check /tmp/agentdeck-perf.txt." >&2
  exit 3
fi
