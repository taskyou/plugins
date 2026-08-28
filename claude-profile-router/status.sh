#!/bin/bash
# `ty plugins run claude-profile-router status` — show what the router sees.
# Same numbers route.sh decides on, so a surprising routing choice can be
# checked against reality without reading the daemon log.
set -uo pipefail

PLUGIN_DIR="${TASK_PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

_pre_profiles="${TY_CLAUDE_PROFILES:-}"
_pre_max="${TY_CLAUDE_MAX_PERCENT:-}"
if [[ -f "$PLUGIN_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$PLUGIN_DIR/config.env"
fi
[[ -n "$_pre_profiles" ]] && TY_CLAUDE_PROFILES="$_pre_profiles"
[[ -n "$_pre_max" ]] && TY_CLAUDE_MAX_PERCENT="$_pre_max"

MAX_PERCENT="${TY_CLAUDE_MAX_PERCENT:-90}"

if [[ -z "${TY_CLAUDE_PROFILES:-}" ]]; then
  echo "No profiles configured. Copy config.example.env to config.env and set TY_CLAUDE_PROFILES."
  exit 0
fi

echo "Routing threshold: skip a profile at or above ${MAX_PERCENT}% used"
echo
for raw in $TY_CLAUDE_PROFILES; do
  dir="${raw/#\~/$HOME}"
  if ! out=$("$PLUGIN_DIR/usage.sh" show "$dir" 2>&1); then
    echo "$dir"
    echo "  unavailable — ${out#usage.sh: }"
  else
    echo "$out"
    pct=$("$PLUGIN_DIR/usage.sh" percent "$dir" 2>/dev/null)
    if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= MAX_PERCENT )); then
      echo "  -> skipped by the router (at or above ${MAX_PERCENT}%)"
    fi
  fi
  echo
done
