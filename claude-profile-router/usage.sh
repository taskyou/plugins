#!/bin/bash
# Read how much of a Claude subscription a profile has spent.
#
#   usage.sh percent <config-dir>   -> one bare number, the binding limit's used %
#   usage.sh show    <config-dir>   -> a human summary (used by status.sh)
#
# A "profile" is a CLAUDE_CONFIG_DIR: one logged-in Claude account. This reads
# that profile's stored OAuth token and calls the same endpoint Claude Code's own
# /usage command uses. It is strictly read-only — no token is refreshed,
# rewritten, or printed.
#
# Exits non-zero (with a message on stderr) whenever the answer isn't
# trustworthy: no credentials, an expired login, a failed request with no usable
# cache. route.sh treats that as "skip this profile", so a broken probe never
# routes a task somewhere wrong.
set -uo pipefail

API="${TY_CLAUDE_API:-https://api.anthropic.com}"
CACHE_DIR="${TY_CLAUDE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ty/claude-usage}"
CACHE_TTL="${TY_CLAUDE_CACHE_TTL:-60}"        # serve without refetching, seconds
CACHE_STALE="${TY_CLAUDE_CACHE_STALE:-1800}"  # usable when a live fetch fails

die() { echo "usage.sh: $*" >&2; exit 1; }

# --- JSON ---------------------------------------------------------------------
# The usage response is too nested for sed to be honest about, so this needs a
# real parser. jq if it's here, python3 otherwise; both are absent often enough
# that "neither" gets a clear message rather than a confusing empty answer.
#
# TY_CLAUDE_JSON forces a backend. That exists so the two dialects can be tested
# against each other — a machine with both installed would otherwise only ever
# exercise jq, and the python3 branch could rot unnoticed until it ran on a box
# without jq.
case "${TY_CLAUDE_JSON:-auto}" in
  jq)      command -v jq      >/dev/null 2>&1 || die "TY_CLAUDE_JSON=jq but jq is not installed"; JSON=jq ;;
  python3) command -v python3 >/dev/null 2>&1 || die "TY_CLAUDE_JSON=python3 but python3 is not installed"; JSON=python3 ;;
  auto)
    if command -v jq >/dev/null 2>&1; then JSON=jq
    elif command -v python3 >/dev/null 2>&1; then JSON=python3
    else die "needs jq or python3 to read the usage API (brew install jq)"
    fi ;;
  *) die "TY_CLAUDE_JSON must be auto, jq, or python3" ;;
esac

# json_field <json> <jq-filter> <python-expr>
# Two dialects for one question. Keep the pair in sync when you touch either.
json_field() {
  local body="$1" jqf="$2" pyf="$3"
  if [[ "$JSON" == jq ]]; then
    printf '%s' "$body" | jq -r "$jqf" 2>/dev/null
  else
    printf '%s' "$body" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
$pyf" 2>/dev/null
  fi
}

# --- credentials --------------------------------------------------------------
# Claude Code namespaces each config dir's credentials by the first 8 hex digits
# of the SHA-256 of the absolute path, so two logged-in accounts can coexist.
# Reproducing that derivation is what lets this read a profile's token without
# asking anyone to paste one. If Anthropic changes the scheme, the keychain
# lookup misses, the .credentials.json fallback misses, and the profile reports
# as unavailable — loudly on stderr, never silently as "0% used".
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  else
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  fi
}

normalize_dir() {
  local d="${1/#\~/$HOME}"
  while [[ "$d" == */ && "$d" != "/" ]]; do d="${d%/}"; done
  printf '%s' "$d"
}

# creds_blob <config-dir> -> the raw credential JSON on stdout
creds_blob() {
  local dir="$1" svc blob
  svc="Claude Code-credentials-$(sha256_of "$dir" | cut -c1-8)"

  if command -v security >/dev/null 2>&1; then
    blob=$(security find-generic-password -s "$svc" -w 2>/dev/null)
    [[ -n "$blob" ]] && { printf '%s' "$blob"; return 0; }
  fi
  if [[ -f "$dir/.credentials.json" ]]; then
    cat "$dir/.credentials.json"; return 0
  fi
  # The default ~/.claude may still use the pre-namespacing service name.
  if [[ "$dir" == "$HOME/.claude" ]] && command -v security >/dev/null 2>&1; then
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    [[ -n "$blob" ]] && { printf '%s' "$blob"; return 0; }
  fi
  return 1
}

# --- cache --------------------------------------------------------------------
# The usage endpoint rate-limits (429), and routing probes it on every spawn —
# without a cache a busy board walks straight into losing the numbers it routes
# on. Cached on disk rather than in memory because every probe is a fresh
# process.
cache_file() { printf '%s/%s.json' "$CACHE_DIR" "$(sha256_of "$1" | cut -c1-16)"; }

file_age() {
  local f="$1" mtime now
  mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || return 1
  now=$(date +%s)
  echo $(( now - mtime ))
}

cache_read() { # <config-dir> <max-age>
  local f; f=$(cache_file "$1")
  [[ -f "$f" ]] || return 1
  local age; age=$(file_age "$f") || return 1
  (( age <= $2 )) || return 1
  cat "$f"
}

cache_write() { # <config-dir> <body>
  local f; f=$(cache_file "$1")
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  # write-then-rename: several spawns can probe the same profile at once, and a
  # reader must never see a half-written file.
  printf '%s' "$2" > "$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null
  rm -f "$f.tmp.$$" 2>/dev/null
  return 0
}

# --- fetch --------------------------------------------------------------------
# fetch_usage <config-dir> -> usage JSON on stdout
fetch_usage() {
  local dir="$1" blob token expires now body code

  blob=$(creds_blob "$dir") || die "no Claude credentials for $dir (log in once with CLAUDE_CONFIG_DIR=$dir claude)"

  token=$(json_field "$blob" '.claudeAiOauth.accessToken // empty' \
    "print(d.get('claudeAiOauth',{}).get('accessToken',''))")
  [[ -n "$token" ]] || die "no OAuth token stored for $dir"

  # expiresAt is epoch MILLIseconds. Don't refresh it here — that would fight
  # Claude Code's own credential management and risk corrupting the entry.
  expires=$(json_field "$blob" '.claudeAiOauth.expiresAt // 0' \
    "print(d.get('claudeAiOauth',{}).get('expiresAt',0) or 0)")
  now=$(( $(date +%s) * 1000 ))
  if [[ "$expires" =~ ^[0-9]+$ ]] && (( expires > 0 && expires < now )); then
    die "credentials for $dir have expired (run a claude session with CLAUDE_CONFIG_DIR=$dir to refresh)"
  fi

  if body=$(cache_read "$dir" "$CACHE_TTL"); then
    printf '%s' "$body"; return 0
  fi

  body=$(curl -sS --max-time 10 -w $'\n%{http_code}' \
    -H "Authorization: Bearer $token" "$API/api/oauth/usage" 2>/dev/null)
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"

  if [[ "$code" == "200" ]]; then
    cache_write "$dir" "$body"
    printf '%s' "$body"; return 0
  fi

  # A failed request is not the same as a bad account: a snapshot from a few
  # minutes ago is a far better basis for routing than nothing.
  if body=$(cache_read "$dir" "$CACHE_STALE"); then
    echo "usage.sh: $dir — live read failed (HTTP ${code:-?}), using cached numbers" >&2
    printf '%s' "$body"; return 0
  fi

  case "$code" in
    401) die "credentials for $dir were rejected (401) — this profile needs a fresh login" ;;
    429) die "the usage API is rate-limiting (429) — not the account's quota; retry shortly" ;;
    *)   die "could not read usage for $dir (HTTP ${code:-no response})" ;;
  esac
}

# --- reporting ----------------------------------------------------------------
# The binding limit is the WORST window, not the average: a 5-hour session at 98%
# blocks the next task even when the weekly window is untouched. Falls back to
# the older five_hour/seven_day shape if `limits` is missing, so an API rollback
# doesn't leave routing reading 0%.
binding_percent() {
  json_field "$1" \
    '[(.limits // [])[].percent, (.five_hour.utilization // empty), (.seven_day.utilization // empty)] | map(select(. != null)) | (max // 0) | floor' \
    "
lim = d.get('limits') or []
vals = [l.get('percent') or 0 for l in lim]
if not vals:
    for k in ('five_hour','seven_day'):
        w = d.get(k) or {}
        if w.get('utilization') is not None: vals.append(w['utilization'])
print(int(max(vals or [0])))"
}

# account_email <config-dir> — which login this profile is, for the human-facing
# `show` output. A second request, so it is never made on the routing path, and
# it is best-effort: a profile's numbers are the point, its address is a label.
# Cached for a day, since it only changes when you re-login.
account_email() {
  local dir="$1" f blob token body age
  f="$(cache_file "$dir").email"
  if [[ -f "$f" ]] && age=$(file_age "$f") && (( age <= 86400 )); then
    cat "$f"; return 0
  fi
  blob=$(creds_blob "$dir") || return 1
  token=$(json_field "$blob" '.claudeAiOauth.accessToken // empty' \
    "print(d.get('claudeAiOauth',{}).get('accessToken',''))")
  [[ -n "$token" ]] || return 1
  body=$(curl -sS --max-time 10 -H "Authorization: Bearer $token" \
    "$API/api/oauth/profile" 2>/dev/null) || return 1
  local email
  email=$(json_field "$body" '.account.email // empty' \
    "print(d.get('account',{}).get('email',''))")
  [[ -n "$email" ]] || return 1
  mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s' "$email" > "$f" 2>/dev/null
  printf '%s' "$email"
}

describe() {
  json_field "$1" \
    '[(.limits // [])[]] | if length == 0 then "no limits reported" else (max_by(.percent) | "\(.percent|floor)% used (\(.kind)\(if .resets_at then ", resets " + (.resets_at|sub("\\..*";"")|sub("T";" ")) else "" end))") end' \
    "
lim = d.get('limits') or []
if not lim:
    print('no limits reported')
else:
    w = max(lim, key=lambda l: l.get('percent') or 0)
    r = w.get('resets_at')
    r = ', resets ' + r.split('.')[0].replace('T',' ') if r else ''
    print('%d%% used (%s%s)' % (int(w.get('percent') or 0), w.get('kind'), r))"
}

# --- main ---------------------------------------------------------------------
[[ $# -ge 2 ]] || die "usage: usage.sh {percent|show} <config-dir>"
mode="$1"; dir="$(normalize_dir "$2")"
usage_json="$(fetch_usage "$dir")" || exit 1

case "$mode" in
  percent) binding_percent "$usage_json" ;;
  show)
    echo "$dir"
    if email=$(account_email "$dir" 2>/dev/null) && [[ -n "$email" ]]; then
      echo "  $email"
    fi
    echo "  $(describe "$usage_json")"
    ;;
  *) die "unknown mode: $mode" ;;
esac
