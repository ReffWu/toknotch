#!/bin/bash
# Read-only reconnaissance for an Antigravity provider.
#
# Every provider in this app was written against real files on a real machine,
# and the bugs that mattered were only findable that way: Cursor reports `used`
# and `limit` as 0 on a free plan, and Codex writes `procStart` in UTC while
# everything around it is local. Guessing either would have shipped a number
# that was quietly wrong. So this looks, and reports, and changes nothing.
#
# What the first run established, and why this script no longer guesses:
#   * State is in ~/.gemini/antigravity, NOT Application Support. That folder
#     is only the Electron shell's browser profile.
#   * There is no state.vscdb. Antigravity is not shaped like Cursor, so the
#     provider cannot be a copy of CursorLocalProvider.
#   * Usage comes from https://cloudcode-pa.googleapis.com/v1internal, and the
#     call that carries plan and quota is `:loadCodeAssist`.
#   * The credential is a keychain item, service `gemini`, account
#     `antigravity`.
set -uo pipefail

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
STATE=~/.gemini/antigravity
LOG=~/Library/Logs/Antigravity/language_server.log

say "1. Installed?"
[ -d /Applications/Antigravity.app ] \
  && defaults read /Applications/Antigravity.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null \
     | sed 's/^/  version /' \
  || echo "  not in /Applications"

say "2. Signed in?"
# The decisive test. The language server says so in plain words, and the
# absence of the error is what "signed in" looks like — the first run of this
# script mistook the error text itself for a success.
if [ -f "$LOG" ]; then
  # The log is cumulative, so errors from before a sign-in live in it forever.
  # Asking "does this string appear" therefore reports a signed-in install as
  # signed out — which it did. Compare *positions* instead: a loadCodeAssist
  # after the last failure means the token started working.
  last_fail=$(grep -n "not logged into Antigravity" "$LOG" | tail -1 | cut -d: -f1)
  last_call=$(grep -n "loadCodeAssist" "$LOG" | tail -1 | cut -d: -f1)
  if [ -z "${last_call:-}" ]; then
    echo "  unknown — the backend has not been called yet"
  elif [ -z "${last_fail:-}" ] || [ "$last_call" -gt "$last_fail" ]; then
    echo "  YES — loadCodeAssist (line $last_call) is newer than the last auth failure (${last_fail:-none})"
  else
    echo "  NO — the newest loadCodeAssist still precedes an auth failure."
    echo "  Sign in inside the app, then run this again."
  fi
  grep -c "loadCodeAssist" "$LOG" 2>/dev/null | sed 's/^/  loadCodeAssist calls: /'
else
  echo "  no language server log yet — has it been opened?"
fi

say "3. Credential"
security find-generic-password -s gemini -a antigravity 2>/dev/null \
  | grep -E '"cdat"|"acct"|"svce"' | sed 's/^/  /' || echo "  no keychain item"

say "4. State on disk"
[ -d "$STATE" ] && du -sh "$STATE"/* 2>/dev/null | sed 's/^/  /'

say "5. Anything resembling a quota, anywhere in state"
grep -rlniE "quota|rate.?limit|remaining|reset_at|tier" "$STATE" 2>/dev/null | head -10 \
  || echo "  nothing yet — usage appears only after the app is actually used"

say "6. What the backend was asked, and what came back"
grep -oE "v1internal:[a-zA-Z]+" "$LOG" 2>/dev/null | sort | uniq -c | sed 's/^/  /'
grep -iE "loadCodeAssist" "$LOG" 2>/dev/null | tail -3 | cut -c1-300 | sed 's/^/  /'

say "Done. Paste this back and the provider gets written against what is real."
