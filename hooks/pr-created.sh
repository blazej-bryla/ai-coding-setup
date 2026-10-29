#!/bin/bash
# PostToolUse (matcher: Bash) hook — safety net for PRs created outside /pr.
# When a Bash call ran `gh pr create` and its output carries a PR URL, tell Claude to run
# the project's change-summary (the profile's notify.summary slot) for that PR. Anything else: exit 0, no output.
set -u

in=$(cat)
cmd=$(printf '%s' "$in" | jq -r '.tool_input.command // empty' 2>/dev/null)
case "$cmd" in *"gh pr create"*) ;; *) exit 0 ;; esac

url=$(printf '%s' "$in" | jq -r '.tool_response | tostring' 2>/dev/null \
  | grep -oE 'https://github\.com/[^/[:space:]"]+/[^/[:space:]"]+/pull/[0-9]+' | head -1)
[ -n "$url" ] || exit 0

r=$("$(dirname "$0")/../bin/wfprofile" notify.summary 2>/dev/null) || exit 0   # stop / error → stay quiet
file=$(printf '%s\n' "$r" | sed -n 's/^file=//p' | head -1)
[ -n "$file" ] || exit 0                                   # no project change-summary mapped
ov=$(printf '%s\n' "$r" | sed -n 's/^overrides=//p')
jq -n --arg url "$url" --arg f "$file" --arg ov "$ov" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
  ("PR " + $url + " was just created. Run the project change-summary for it: read " + $f + " and follow it (inputs: the PR URL, base branch, `git log <base>..HEAD --oneline`" + (if $ov != "" then "; caller overrides: " + $ov else "" end) + "). Skip if /pr already ran it in this turn.")}}'
