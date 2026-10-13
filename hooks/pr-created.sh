#!/bin/bash
# PostToolUse (matcher: Bash) hook — safety net for PRs created outside /pr.
# When a Bash call ran `gh pr create` and its output carries a PR URL, tell Claude to run
# the project's /change-summary for that PR. Anything else: exit 0, no output.
set -u

in=$(cat)
cmd=$(printf '%s' "$in" | jq -r '.tool_input.command // empty' 2>/dev/null)
case "$cmd" in *"gh pr create"*) ;; *) exit 0 ;; esac

url=$(printf '%s' "$in" | jq -r '.tool_response | tostring' 2>/dev/null \
  | grep -oE 'https://github\.com/[^/[:space:]"]+/[^/[:space:]"]+/pull/[0-9]+' | head -1)
[ -n "$url" ] || exit 0

. "$(dirname "$0")/lib/config.sh"
jq -n --arg url "$url" --arg skill "$WT_CHANGE_SUMMARY_SKILL" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
  ("PR " + $url + " was just created. If this checkout has " + $skill + ", run it now for this PR (read the file and follow it; inputs: the PR URL, base branch, `git log <base>..HEAD --oneline`). Skip if /pr already ran it in this turn.")}}'
