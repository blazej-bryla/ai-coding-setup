#!/bin/bash
# PreToolUse (matcher: Bash) hook (v3.8) — runs alongside rtk-guard.sh.
# Agents start and stop dev servers only through ~/.agents/bin/wtsrv (never the dev command directly, never
# `kill`) and never run tests in watch mode. Each segment of the command (split on && || ; | and newlines, past leading
# VAR=val / env / time / sudo / xargs / rtk) is checked; a hit → deny with a one-line reason.
# git push: plain push to a task branch passes; force, --delete/--all/--mirror/--tags or a protected target → ask.
# Heredoc bodies and quoted strings are blanked first, so commit messages and echo text don't trip it.
# Fails open: any internal error → logged to ~/.agents/hooks-errors.log, command allowed.
set -u
ERRLOG=$HOME/.agents/hooks-errors.log
logerr() { printf '%s\terror\tbash-guard\t%s\n' "$(date '+%F %T')" "$*" >>"$ERRLOG" 2>/dev/null; exit 0; }
trap 'logerr "unexpected failure (line $LINENO)"' ERR

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}
ask() {
  jq -nc --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
}
# server/process/watch patterns: lib/config.sh (WT_SERVER_CMD_RE, WT_SERVER_PROC_RE, WT_SERVER_PROC_NAMES, WT_WATCH_CMD_RE)
. "$(dirname "$0")/lib/config.sh"
SERVER='Start dev servers with ~/.agents/bin/wtsrv up <slug> fe|be (never the dev command directly)'
KILL='Stop dev servers with ~/.agents/bin/wtsrv down <slug> [fe|be]; never kill server processes'
WATCH="Run tests without watch mode: $WT_TEST_CMD"

input=$(cat) || logerr "bad hook input"
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || logerr "bad hook input"
[ -n "$cmd" ] || exit 0
hook_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || hook_cwd=""
[ -n "$hook_cwd" ] || hook_cwd=$PWD

# blank heredoc bodies and quoted strings, then one segment per line
segs=$(printf '%s\n' "$cmd" | perl -0777 -pe '
  s/<<-?\s*([\x27"]?)(\w+)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|$)/<<H/gs;
  s/\x27[^\x27]*\x27/Q/g; s/"(?:[^"\\]|\\.)*"/Q/g;
  s/&&|\|\||;|\||\n|\$\(|`|\(|\)/\n/g;
  s/^[ \t]*//mg;
  s/^(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|env|time|sudo|command|exec|nohup|rtk|xargs(?:\s+-\S+)*)\s+)+//mg;
') || logerr "perl split failed"
flat=$(printf '%s' "$segs" | tr '\n' ' ')

# git push: protected = base, staging, main/master, the epic pattern ({KEY} = any key)
is_protected() {
  local b=${1#refs/heads/} epic
  [ -n "$b" ] || return 1
  case "$b" in main|master) return 0 ;; esac
  [ -n "${WT_BASE_BRANCH:-}" ] && [ "$b" = "$WT_BASE_BRANCH" ] && return 0
  [ -n "${WT_STAGING_BRANCH:-}" ] && [ "$b" = "$WT_STAGING_BRANCH" ] && return 0
  if [ -n "${WT_EPIC_BRANCH:-}" ]; then
    epic=${WT_EPIC_BRANCH//\{KEY\}/*}
    # shellcheck disable=SC2053
    [[ "$b" == $epic ]] && return 0
  fi
  return 1
}
cur_branch() { git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true; }
want_ask() { [ -n "$ASK_REASON" ] || ASK_REASON=$1; }  # deny of a later segment still wins
check_push() { # $1 = segment, $2 = dir it runs in
  local -a w; local i=1 dir=$2 a sub="" remote="" br t; local -a refs=()
  set -f; read -ra w <<<"$1"; set +f
  # git global options before the subcommand
  while [ "$i" -lt "${#w[@]}" ]; do
    a=${w[$i]}
    case "$a" in
      -C) i=$((i+1)); a=${w[$i]:-}; case "$a" in /*) dir=$a ;; *) dir=$dir/$a ;; esac ;;
      -c|--git-dir|--work-tree|--namespace) i=$((i+1)) ;;
      -*) ;;
      *) sub=$a; break ;;
    esac
    i=$((i+1))
  done
  [ "$sub" = push ] || return 0
  i=$((i+1))
  while [ "$i" -lt "${#w[@]}" ]; do
    a=${w[$i]}
    case "$a" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) { want_ask "git push: force push ($a) needs your approval"; return 0; } ;;
      --delete|--all|--branches|--mirror|--tags|--prune) { want_ask "git push: $a can delete or overwrite remote refs, needs your approval"; return 0; } ;;
      --repo|--push-option|--receive-pack|--exec|-o) i=$((i+1)) ;;
      --) ;;
      --*) ;;
      -*) case "$a" in *f*) { want_ask "git push: force push ($a) needs your approval"; return 0; } ;; *d*) { want_ask "git push: delete ($a) needs your approval"; return 0; } ;; esac ;;
      *) if [ -z "$remote" ]; then remote=$a; else refs+=("$a"); fi ;;
    esac
    i=$((i+1))
  done
  if [ "${#refs[@]}" -eq 0 ]; then
    br=$(cur_branch "$dir")
    [ -n "$br" ] || { want_ask "git push: can't tell the current branch in $dir — needs your approval"; return 0; }
    is_protected "$br" && { want_ask "git push: current branch $br is protected — needs your approval"; return 0; }
    return 0
  fi
  for a in "${refs[@]}"; do
    case "$a" in +*) { want_ask "git push: force refspec $a needs your approval"; return 0; } ;; :*) { want_ask "git push: refspec $a deletes a remote branch — needs your approval"; return 0; } ;; esac
    t=${a##*:}
    case "$t" in HEAD|@) t=$(cur_branch "$dir"); [ -n "$t" ] || { want_ask "git push: can't tell the current branch in $dir — needs your approval"; return 0; } ;; esac
    is_protected "$t" && { want_ask "git push: target branch ${t#refs/heads/} is protected — needs your approval"; return 0; }
  done
  return 0
}

ps_is_server() { local c; c=$(ps -o command= -p "$1" 2>/dev/null) || return 1; printf %s "$c" | grep -qE "$WT_SERVER_PROC_RE"; }

seg_dir=$hook_cwd ASK_REASON=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  # cd before a git push changes which branch is current
  case "$s" in
    cd|cd\ *) a=${s#cd}; a=${a# }; a=${a%% *}
      case "$a" in ''|'~') seg_dir=$HOME ;; '~/'*) seg_dir=$HOME/${a#'~/'} ;; /*) seg_dir=$a ;; *) seg_dir=$seg_dir/$a ;; esac ;;
  esac
  # git push to protected branches, force and destructive pushes → ask
  case "$s" in git|git\ *) check_push "$s" "$seg_dir" ;; esac
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
[ -z "$ASK_REASON" ] || ask "$ASK_REASON"
exit 0
