# ---- worktrees (v3.7) ------------------------------------------------------
# One identifier for everything: the task key in the branch name (todo-12).
# Creation happens in the WorktreeCreate hook; these helpers only get you there.
# Repos, ports, commands, DB: hooks/lib/config.sh (values in ~/.agents/config.local.zsh; `wtconf` lists them).
source "${${(%):-%x}:A:h}/../hooks/lib/config.sh"
case ":$PATH:" in *":$HOME/.agents/bin:"*) ;; *) export PATH="$HOME/.agents/bin:$PATH" ;; esac   # settings-sync
# Browser: agent-browser CLI. One session per task side, `--session <slug>-<side> --restore`, seeded with
# `--state $AB_STATE` (the login `ablogin` saves; --state wins over the restored state, so re-running ablogin
# refreshes every task session on its next open). Headed via ~/.agent-browser/config.json; the viewport isn't a
# config key, so every session starts with `set viewport 1440 900`. State is encrypted with
# AGENT_BROWSER_ENCRYPTION_KEY (exported in ~/.zshrc, never in ~/.agents).
# MCP instead of the CLI, should a skill ever need it:
# claude mcp add --scope user agent-browser -- agent-browser mcp
export AB_STATE=~/.agent-browser/auth-base.json

_slug() {  # TODO-12-add-due-dates | dev/todo-7-1-x | todo-12  →  todo-12 | todo-7-1
  local k; k=$(printf %s "$1" | grep -oiE '[a-z]+-[0-9]+(-[0-9]+)?' | head -1 | tr A-Z a-z)
  [ -n "$k" ] && printf %s "$k" || printf %s "${1#*/}"
}
_repo() { [ "$1" = fe ] && echo "$FE_REPO" || echo "$BE_REPO"; }
_port() { grep -h '^PORT=' "$1/.env.local" "$1/.env" 2>/dev/null | head -1 | cut -d= -f2; }

# wt <branch> <fe|be> [--base <branch>|--staging] [prompt…]
#   Claude in the worktree for that branch (the hook creates it; base = origin/HEAD unless overridden)
wt() {
  local branch=$1 side=$2 base=""
  [ -z "$side" ] && { echo "usage: wt <branch> <fe|be> [--base <branch>|--staging] [prompt]"; return 1; }
  shift 2
  case "$1" in --staging) base=$WT_STAGING_BRANCH; shift ;; --base) base=$2; shift 2 ;; esac
  local slug; slug=$(_slug "$branch")
  cd "$(_repo "$side")" && WT_BRANCH=$branch WT_BASE=$base claude --worktree "$slug" --name "$slug-$side" --permission-mode acceptEdits --add-dir "$HOME/.agents/scratch" "$@"   # scratch: task state (context.md, tickets) lives outside the worktree
}
# Remote-API mode: the deployed API (and the SSO dev app) may accept only localhost:$WT_REMOTE_FE_PORT,
# so one FE task at a time holds that port (browser sessions are per task and run in parallel). `wtwho` shows who; `wts … --take` swaps.
_listener() { lsof -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }            # pid listening on port
_pcwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; }             # cwd of pid
_holder() { local pid; pid=$(_listener "$1") || return 1; [ -n "$pid" ] && _pcwd "$pid"; }

# wts <slug|branch> <fe|be> [--local|--remote] [--port N] [--take]
wts() {
  local slug=$1 side=$2 mode="" port="" take=""; shift 2
  while [ $# -gt 0 ]; do case "$1" in --local) mode=local;; --remote) mode=remote;; --port) port=$2; shift;; --take) take=1;; esac; shift; done
  cdwt "$slug" "$side" || return 1
  if [ "$side" = be ]; then eval "$WT_BE_DEV_CMD"; return; fi
  local key; key=$(_slug "$slug")
  [ -z "$mode" ] && { [ -d "$WT_ROOT/$key-be" ] && mode=local || mode=remote; }
  local api
  if [ "$mode" = local ]; then
    port=${port:-$(_port "$PWD")}
    [ -n "$port" ] || port=$(( WT_FE_PORT_BASE + $(printf %s "$key" | cksum | cut -d' ' -f1) % 40 ))   # worktree made before the hook
    local be="$WT_ROOT/$key-be"
    [ -d "$be" ] && api="http://localhost:$(_port "$be")"   # BE made after FE: .env.local may still say remote
    [ -n "$api" ] || api=$(grep -h "^$FE_API_VAR=" .env.local | tail -1 | cut -d= -f2-)
    echo "FE :$port → local BE ($api)"
    echo "local mode on :$port — SSO login works only if this port is an allowed callback of your auth provider"
  else
    port=${port:-$WT_REMOTE_FE_PORT}                     # the remote API may accept this origin only
    api=$WT_REMOTE_API
    local pid holder
    pid=$(_listener "$port")
    if [ -n "$pid" ]; then
      holder=$(_pcwd "$pid")
      if [ -z "$take" ]; then
        echo "port $port busy — held by ${holder:t} ($holder) — \`wts $key fe --take\` to take it, or --local / --port N"; return 1
      fi
      case "$holder" in "$WT_ROOT"/*|"$FE_REPO") ;; *)
        echo "port $port held by something else ($(ps -o command= -p "$pid" | cut -c1-60), cwd ${holder:-?}) — refusing --take"; return 1 ;; esac
      local p=$pid pp
      while [ -n "$p" ] && [ "$p" != 1 ]; do                  # the listener plus its dev-server parents
        ps -o command= -p "$p" | grep -qE "$WT_FE_PROC_RE" || break
        kill "$p" 2>/dev/null
        p=$(ps -o ppid= -p "$p" | tr -d ' ')
      done
      rm -f "$holder/.shots/.fe-url"
      local n=0; while [ -n "$(_listener "$port")" ] && [ $n -lt 30 ]; do sleep 0.5; n=$((n+1)); done
      [ -z "$(_listener "$port")" ] || { echo "port $port still busy after --take"; return 1; }
      echo "took :$port from ${holder:t}"
    fi
    echo "FE :$port → remote API ($api)"
  fi
  setopt local_options local_traps
  local urlf="$PWD/.shots/.fe-url"
  mkdir -p .shots && echo "http://localhost:$port" > "$urlf"   # skills read AFTER_URL from here
  trap "rm -f '$urlf'" EXIT INT TERM
  local PORT=$port
  eval "$FE_API_VAR=\$api $WT_FE_DEV_CMD"
}

# wtwho — who holds the shared remote-API FE port, and which FE worktree ports (local mode) are up
wtwho() {
  local h d p r=$WT_REMOTE_FE_PORT; h=$(_holder "$r")
  if [ -n "$h" ]; then echo "$r → ${h:t}"; else echo "$r → free"; fi
  for d in "$WT_ROOT"/*-fe(N); do
    p=$(_port "$d"); [ -n "$p" ] && [ "$p" != "$r" ] && [ -n "$(_listener "$p")" ] && echo "$p → ${d:t}"
  done
}
# ablogin — log in once in a headed session (auth-base); task sessions start from its saved state
ablogin() {
  local ab=(agent-browser --session auth-base --restore)
  [ -n "$AGENT_BROWSER_ENCRYPTION_KEY" ] || echo "note: AGENT_BROWSER_ENCRYPTION_KEY not set — the state will be saved unencrypted"
  "${ab[@]}" open "http://localhost:$WT_REMOTE_FE_PORT" >/dev/null || return 1
  "${ab[@]}" set viewport 1440 900 >/dev/null
  [ -n "$WT_BASELINE_FE_URL" ] && "${ab[@]}" tab new "$WT_BASELINE_FE_URL" >/dev/null
  echo "log in in the agent-browser window (localhost:$WT_REMOTE_FE_PORT${WT_BASELINE_FE_URL:+ and $WT_BASELINE_FE_URL}), then press Enter"
  read -r
  "${ab[@]}" state save "$AB_STATE" && "${ab[@]}" close >/dev/null
}
cdwt() { cd "$WT_ROOT/$(_slug "$1")-$2"; }
wtls() { local s; for s in fe be; do echo "== $s"; git -C "$(_repo $s)" worktree list; done; }

# Per-worktree BE database ($WT_DB_PREFIX<slug>, in container $WT_DB_CONTAINER) — hooks/lib/db.sh
_WTDB=${${(%):-%x}:A:h}/../hooks/lib/db.sh
_wtdbname() { grep -h "^${DB_NAME_VARS%% *}=" "$1/.env" 2>/dev/null | tail -1 | cut -d= -f2-; }
_wtdbdrop() {  # ask, drop on y — only $WT_DB_PREFIX* (db.sh refuses anything else, and the source db)
  local n=$1 a
  [[ -n $WT_DB_CONTAINER && -n $n && $n == ${WT_DB_PREFIX}* ]] || return 0
  bash $_WTDB exists "$n" || return 0
  printf 'drop database %s? [y/N] ' "$n"; read -r a </dev/tty
  [[ $a == [yY] ]] && bash $_WTDB drop "$n"
  return 0
}
# wtdb <slug|branch> [--fresh] — create this task's BE database: copy of the source db (--fresh: empty) + this branch's migrations
wtdb() {
  [ -z "$1" ] && { echo "usage: wtdb <slug> [--fresh]"; return 1; }
  local d="$WT_ROOT/$(_slug "$1")-be"
  [ -d "$d" ] || { echo "no BE worktree $d"; return 1; }
  bash $_WTDB ensure "$d" $2
}

# wtrm <slug|branch> [fe|be] — remove this task's worktree(s); branches stay
wtrm() {
  local slug side d db; slug=$(_slug "$1")
  for side in ${=${2:-fe be}}; do
    d="$WT_ROOT/$slug-$side"
    [ -d "$d" ] || continue
    [ "$side" = be ] && db=$(_wtdbname "$d")
    git -C "$(_repo $side)" worktree remove --force "$d" && echo "removed $d" && [ "$side" = be ] && _wtdbdrop "$db"
  done
}

# wtclean — remove worktrees whose branch is merged into the base branch or gone from origin
wtclean() {
  local side repo d br track base db
  for side in fe be; do
    repo=$(_repo $side)
    git -C "$repo" fetch --prune origin >/dev/null 2>&1
    base=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/$WT_BASE_BRANCH")
    git -C "$repo" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{print w, $2}' |
    while read -r d br; do
      case "$d" in "$WT_ROOT"/*) ;; *) continue ;; esac
      br=${br#refs/heads/}
      track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$br")
      if [ "$track" = "[gone]" ] || git -C "$repo" merge-base --is-ancestor "$br" "$base" 2>/dev/null; then
        db=""; [ "$side" = be ] && db=$(_wtdbname "$d")
        git -C "$repo" worktree remove --force "$d" && git -C "$repo" branch -D "$br" >/dev/null 2>&1 && echo "cleaned $d ($br)"
        [ -n "$db" ] && [ ! -d "$d" ] && _wtdbdrop "$db"
      fi
    done
    git -C "$repo" worktree prune
  done
}

# friction [days] — ~/.agents/friction.log (JSON lines) of the last N days (default 7), grouped by `what`, newest first
friction() {
  local f=~/.agents/friction.log since
  [ -s "$f" ] || { echo "friction.log is empty"; return 0; }
  since=$(date -u -v-"${1:-7}"d +%Y-%m-%dT%H:%M:%SZ)
  jq -rs --arg since "$since" '
    map(select(.date >= $since)) | group_by(.what)
    | map({what: .[0].what, n: length, last: (map(.date) | max), items: (sort_by(.date) | reverse)})
    | sort_by(.last) | reverse | .[]
    | "\(.n)× \(.what)  (last \(.last[0:10]))",
      (.items[] | "    \(.date[0:10]) \(.slug)-\(.side) [\(.cost)] — \(.workaround)")' "$f"
}

# metrics [days] — ~/.agents/metrics.log (JSON lines, one per landed ticket / fixed bug) of the last N days (default 7)
metrics() {
  local f=~/.agents/metrics.log since
  [ -s "$f" ] || { echo "metrics.log is empty"; return 0; }
  since=$(date -u -v-"${1:-7}"d +%Y-%m-%dT%H:%M:%SZ)
  jq -rs --arg since "$since" --arg days "${1:-7}" '
    def r1: . * 10 | round / 10;
    def avg(f): map(f) | add / length | r1;
    def tot(f): map(f) | add;
    map(select(.date >= $since)) as $t | ($t | length) as $n
    | if $n == 0 then "no tickets in the last \($days) days" else
      ($t | map(select(.implementer_runs > 1)) | length) as $re
      | "\($n) tickets, \($t | map(.slug) | unique | length) tasks, last \($days) days",
        "  wall minutes      avg \($t | avg(.wall_minutes))   total \($t | tot(.wall_minutes))",
        "  implementer runs  avg \($t | avg(.implementer_runs))   total \($t | tot(.implementer_runs))   respawned \($re)/\($n) (\($re * 100 / $n | round)%)",
        "  reviewers         avg \($t | avg(.reviewers_selected | length))",
        "  findings          avg \($t | avg(.findings_kept)) kept, \($t | avg(.findings_fixed)) fixed   total \($t | tot(.findings_kept)) kept, \($t | tot(.findings_fixed)) fixed",
        "  teach             avg \($t | avg(.teach_questions)) questions   total \($t | tot(.teach_wrong))/\($t | tot(.teach_questions)) wrong",
        "  prior art         \($t | map(select(.prior_art)) | length)/\($n)",
        "  slowest:",
        ($t | sort_by(-.wall_minutes) | .[:5][]
          | "    \(.wall_minutes) min  \(.slug)-\(.side) \(.ticket) [\(.mode)]  runs \(.implementer_runs), findings \(.findings_kept)")
      end' "$f"
}
