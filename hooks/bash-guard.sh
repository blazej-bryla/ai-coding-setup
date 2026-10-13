#!/bin/bash
# PreToolUse (matcher: Bash) hook (v3.4.1) — runs alongside rtk-guard.sh.
# Agents never start or kill dev servers and never run tests in watch mode (WORKFLOW.md: servers are
# the human's, `wts`). Each segment of the command (split on && || ; | and newlines, past leading
# VAR=val / env / time / sudo / xargs / rtk) is checked; a hit → deny with a one-line reason.
# Heredoc bodies and quoted strings are blanked first, so commit messages and echo text don't trip it.
# Fails open: any internal error → logged to ~/.agents/rules/errors.log, command allowed.
set -u
ERRLOG=${RULES_DIR:-$HOME/.agents/rules}/errors.log
logerr() { printf '%s\terror\tbash-guard\t%s\n' "$(date '+%F %T')" "$*" >>"$ERRLOG" 2>/dev/null; exit 0; }
trap 'logerr "unexpected failure (line $LINENO)"' ERR

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}
# server/process/watch patterns: lib/config.sh (WT_SERVER_CMD_RE, WT_SERVER_PROC_RE, WT_SERVER_PROC_NAMES, WT_WATCH_CMD_RE)
. "$(dirname "$0")/lib/config.sh"
SERVER='Dev servers are the human'"'"'s: ask them to run `wts <slug> <side>`'
KILL='Dev servers are the human'"'"'s: ask them to run `wts <slug> <side> --take`'
WATCH="Run tests without watch mode: $WT_TEST_CMD"

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || logerr "bad hook input"
[ -n "$cmd" ] || exit 0

# blank heredoc bodies and quoted strings, then one segment per line
segs=$(printf '%s\n' "$cmd" | perl -0777 -pe '
  s/<<-?\s*([\x27"]?)(\w+)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|$)/<<H/gs;
  s/\x27[^\x27]*\x27/Q/g; s/"(?:[^"\\]|\\.)*"/Q/g;
  s/&&|\|\||;|\||\n|\$\(|`|\(|\)/\n/g;
  s/^[ \t]*//mg;
  s/^(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|env|time|sudo|command|exec|nohup|rtk|xargs(?:\s+-\S+)*)\s+)+//mg;
') || logerr "perl split failed"
flat=$(printf '%s' "$segs" | tr '\n' ' ')

ps_is_server() { local c; c=$(ps -o command= -p "$1" 2>/dev/null) || return 1; printf %s "$c" | grep -qE "$WT_SERVER_PROC_RE"; }

while IFS= read -r s; do
  [ -n "$s" ] || continue
  # dev servers
  if printf %s "$s" | grep -qE "$WT_SERVER_CMD_RE"; then
    deny "$SERVER"
  fi
  # killing dev-server processes
  if printf %s "$s" | grep -qE '^(kill|pkill|killall)\b'; then
    args=${s#* }; [ "$args" = "$s" ] && args=""
    if printf %s "$args" | grep -qE "\\b($WT_SERVER_PROC_NAMES)\\b" \
       || printf %s "$flat" | grep -qE "\\b(lsof|pgrep)\\b.*\\b($WT_SERVER_PROC_NAMES|LISTEN|:[0-9]{4})|\\b(lsof)[[:space:]]+-t"; then
      deny "$KILL"
    fi
    for p in $args; do
      case "$p" in *[!0-9]*|'') continue ;; esac
      ps_is_server "$p" && deny "$KILL"
    done
  fi
  # watch-mode tests
  if { [ -n "$WT_WATCH_CMD_RE" ] && printf %s "$s" | grep -qE "$WT_WATCH_CMD_RE"; } \
     || { printf %s "$s" | grep -qE '^(npx[[:space:]]+)?vitest\b' && ! printf %s "$s" | grep -qE '^(npx[[:space:]]+)?vitest[[:space:]]+(.*[[:space:]])?(run|--run)\b'; } \
     || printf %s "$s" | grep -qE '^(npx[[:space:]]+)?jest\b.*--watch'; then
    deny "$WATCH"
  fi
done <<<"$segs"
exit 0
