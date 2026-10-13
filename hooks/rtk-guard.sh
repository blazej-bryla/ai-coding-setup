#!/bin/bash
# PreToolUse (matcher: Bash) hook — wraps `rtk hook claude`.
# RTK rewrites commands to `rtk …`; Claude Code's worktree isolation guard rejects a
# rewritten `rtk git …`, so no commit can happen inside a worktree session. Here every
# chain segment (start, or after && || ; |, past leading VAR=val assignments) that RTK
# turned into `rtk git` / `rtk gh` goes back to literal `git` / `gh`; everything else keeps
# RTK. When git/gh was restored, RTK's permissionDecision is dropped so the normal
# allow/ask/deny rules (e.g. ask on git push) still apply to those commands.
set -u

in=$(cat)
out=$(printf '%s' "$in" | rtk hook claude) || exit 0
new=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)
[ -n "$new" ] || { printf '%s' "$out"; exit 0; }            # RTK didn't rewrite: pass its output on

fixed=$(printf '%s' "$new" | perl -pe 's/(^|&&|\|\||;|\|)(\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*)rtk\s+(git|gh)\b/$1$2$3/g')
orig=$(printf '%s' "$in" | jq -r '.tool_input.command // empty')

[ "$fixed" = "$new" ] && { printf '%s' "$out"; exit 0; }     # no git/gh touched: RTK as is
[ "$fixed" = "$orig" ] && exit 0                               # only git/gh: run unchanged
printf '%s' "$out" | jq -c --arg c "$fixed" \
  '.hookSpecificOutput.updatedInput.command = $c | del(.hookSpecificOutput.permissionDecision)'
