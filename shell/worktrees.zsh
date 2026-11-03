# ---- worktrees (v3.8: monorepo) ---------------------------------------------
# One identifier for everything: the task key in the branch name (todo-12). One worktree per task,
# $WT_ROOT/<slug>, holding both apps ($WT_FE_DIR, $WT_BE_DIR); one Claude session named <slug>.
# Creation happens in the WorktreeCreate hook; these helpers only get you there.
# Repo, app dirs, ports, commands, DB: hooks/lib/config.sh (values in ~/.agents/config.local.zsh; `wtconf` lists them).
WF_USE_DEFAULT_PROFILE=1   # not exported: outside a profiled repo the helpers use $WF_DEFAULT_PROFILE (config.local.zsh)
source "${${(%):-%x}:A:h}/../hooks/lib/config.sh"
unset WF_USE_DEFAULT_PROFILE
source "${${(%):-%x}:A:h}/../hooks/lib/node.sh"   # wt_node_use: the repo's Node before any npm call; wt_deps_check
case ":$PATH:" in *":$HOME/.agents/bin:"*) ;; *) export PATH="$HOME/.agents/bin:$PATH" ;; esac   # settings-sync
# Browser: agent-browser CLI. One session per task, `--session <slug> --restore`, seeded with
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
_app() { [ "$1" = fe ] && echo "$WT_FE_DIR" || echo "$WT_BE_DIR"; }
_port() { grep -h '^PORT=' "$1/.env.local" "$1/.env" 2>/dev/null | head -1 | cut -d= -f2; }

# wt <branch> [--base <branch>|--staging] [prompt…]
#   Claude in the task's worktree for that branch (the hook creates it; base = origin/HEAD unless overridden)
#   `wt <branch> fe|be …` still works: the side is ignored (one worktree per task)
wt() {
  local branch=$1 base=""
  [ -z "$branch" ] && { echo "usage: wt <branch> [--base <branch>|--staging] [prompt]"; return 1; }
  shift
  case "$1" in fe|be) echo "wt: side '$1' ignored — one worktree and one session per task"; shift ;; esac
  case "$1" in --staging) base=$WT_STAGING_BRANCH; shift ;; --base) base=$2; shift 2 ;; esac
  local slug; slug=$(_slug "$branch")
  if [ ! -d "$WT_ROOT/$slug" ] && [ "$(git -C "$MONO_REPO" symbolic-ref -q --short HEAD)" = "$branch" ]; then
    echo "the main checkout is on this branch — git -C $MONO_REPO switch $WT_BASE_BRANCH, then run wt again"; return 1
  fi
  cd "$MONO_REPO" && WT_BRANCH=$branch WT_BASE=$base claude --worktree "$slug" --name "$slug" --permission-mode acceptEdits --add-dir "$HOME/.agents/scratch" "$@"   # scratch: task state (context.md, tickets) lives outside the worktree
}
# Remote-API mode: the deployed API (and the SSO dev app) may accept only localhost:$WT_REMOTE_FE_PORT,
# so one FE task at a time holds that port (browser sessions are per task and run in parallel). `wtwho` shows who; `wts … --take` swaps.
_listener() { lsof -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }            # pid listening on port
_pcwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; }             # cwd of pid
_holder() { local pid; pid=$(_listener "$1") || return 1; [ -n "$pid" ] && _pcwd "$pid"; }

# wts <slug|branch> <fe|be> [--local|--remote] [--port N] [--take]
#   both: `nvm use` the repo's .nvmrc / engines.node, deps present (else: fix, `wt <slug>` reinstalls)
#   be: the per-worktree DB first (created lazily, here), the BE extras once, then the BE on its PORT (.shots/.be-url while it runs)
#   fe: the FE extras once (e.g. e2e browsers), then: this worktree's BE listening → local API, else the remote API — decided now; env files untouched
wts() {
  local slug=$1 side=$2 mode="" port="" take=""; shift 2
  while [ $# -gt 0 ]; do case "$1" in --local) mode=local;; --remote) mode=remote;; --port) port=$2; shift;; --take) take=1;; esac; shift; done
  case "$side" in fe|be) ;; *) echo "usage: wts <slug> <fe|be> [--local|--remote] [--port N] [--take]"; return 1 ;; esac
  local key; key=$(_slug "$slug")
  cd "$WT_ROOT/$key" || return 1
  wt_node_use "$PWD" || { echo "wts: wrong Node for $key (see above)"; return 1; }
  wt_deps_check "$PWD" || { echo "wts: deps missing in $key — see .shots/setup.log; \`wt $key\` runs the setup again"; return 1; }
  if [ "$side" = be ]; then
    if [ -n "$WT_DB_CONTAINER" ]; then
      bash $_WTDB ensure "$PWD" || { echo "wts: database not ready (see above) — fix it, then run wts $key be again"; return 1; }
    fi
    if [ -n "$WT_BE_SETUP_CMD" ] && [ ! -f .shots/.be-setup ]; then   # once per worktree
      eval "$WT_BE_SETUP_CMD" || { echo "wts: BE setup failed — $WT_BE_SETUP_CMD"; return 1; }
      mkdir -p .shots && : > .shots/.be-setup
    fi
    local bport; bport=$(_port "$WT_BE_DIR")
    [ -n "$bport" ] || bport=$(( WT_BE_PORT_BASE + $(printf %s "$key" | cksum | cut -d' ' -f1) % 40 ))   # worktree made before the hook
    setopt local_options local_traps
    local burlf="$PWD/.shots/.be-url"
    mkdir -p .shots && echo "http://localhost:$bport" > "$burlf"   # the Herdr board reads it, like .fe-url
    trap "rm -f '$burlf'" EXIT INT TERM
    eval "$WT_BE_DEV_CMD"; return
  fi
  if [ -n "$WT_FE_SETUP_CMD" ] && [ ! -f .shots/.fe-setup ]; then   # once per worktree
    eval "$WT_FE_SETUP_CMD" || { echo "wts: FE setup failed — $WT_FE_SETUP_CMD"; return 1; }
    mkdir -p .shots && : > .shots/.fe-setup
  fi
  local fe="$WT_FE_DIR" bep api
  bep=$(_port "$WT_BE_DIR")
  [ -z "$mode" ] && { [ -n "$bep" ] && [ -n "$(_listener "$bep")" ] && mode=local || mode=remote; }
  if [ "$mode" = local ]; then
    port=${port:-$(_port "$fe")}
    [ -n "$port" ] || port=$(( WT_FE_PORT_BASE + $(printf %s "$key" | cksum | cut -d' ' -f1) % 40 ))   # worktree made before the hook
    api="http://localhost:$bep"
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
      case "$holder" in "$WT_ROOT"/*|"$MONO_REPO"|"$MONO_REPO"/*) ;; *)
        echo "port $port held by something else ($(ps -o command= -p "$pid" | cut -c1-60), cwd ${holder:-?}) — refusing --take"; return 1 ;; esac
      local p=$pid pp
      while [ -n "$p" ] && [ "$p" != 1 ]; do                  # the listener plus its dev-server parents
        ps -o command= -p "$p" | grep -qE "$WT_FE_PROC_RE" || break
        kill "$p" 2>/dev/null
        p=$(ps -o ppid= -p "$p" | tr -d ' ')
      done
      local hroot=${holder%/$WT_FE_DIR}                       # npm -w runs the FE in the app dir
      rm -f "$hroot/.shots/.fe-url"
      local n=0; while [ -n "$(_listener "$port")" ] && [ $n -lt 30 ]; do sleep 0.5; n=$((n+1)); done
      [ -z "$(_listener "$port")" ] || { echo "port $port still busy after --take"; return 1; }
      echo "took :$port from ${hroot:t}"
    fi
    echo "FE :$port → remote API ($api)"
  fi
  setopt local_options local_traps
  local urlf="$PWD/.shots/.fe-url"
  mkdir -p .shots && echo "http://localhost:$port" > "$urlf"   # skills read AFTER_URL from here
  trap "rm -f '$urlf'" EXIT INT TERM
  local PORT=$port
  local -x "$FE_API_VAR=$api"   # exported for every step of WT_FE_DEV_CMD (e.g. a build step before the dev server), not only the first
  eval "$WT_FE_DEV_CMD"
}

# wtwho — who holds the shared remote-API FE port, and which task worktrees run a FE / BE on their own ports
wtwho() {
  local h d p s r=$WT_REMOTE_FE_PORT; h=$(_holder "$r")
  if [ -n "$h" ]; then h=${h%/$WT_FE_DIR}; echo "$r → ${h:t}"; else echo "$r → free"; fi
  for d in "$WT_ROOT"/*(N/); do
    for s in fe be; do
      p=$(_port "$d/$(_app $s)"); [ -n "$p" ] && [ "$p" != "$r" ] && [ -n "$(_listener "$p")" ] && echo "$p → ${d:t} ($s)"
    done
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
# cdwt <slug|branch> [fe|be] — the task's worktree, or one app's dir in it
cdwt() { cd "$WT_ROOT/$(_slug "$1")${2:+/$(_app "$2")}"; }
wtls() { git -C "$MONO_REPO" worktree list; }

# Per-worktree BE database ($WT_DB_PREFIX<slug>, in container $WT_DB_CONTAINER) — hooks/lib/db.sh
_WTDB=${${(%):-%x}:A:h}/../hooks/lib/db.sh
_wtdbname() {  # <worktree> — its BE's db name ($WT_BE_DIR/.env; a pre-v3.8 <slug>-be worktree: .env)
  local f="$1/$WT_BE_DIR/.env"; [ -f "$f" ] || f="$1/.env"
  grep -h "^${DB_NAME_VARS%% *}=" "$f" 2>/dev/null | tail -1 | cut -d= -f2-
}
_wtdbdrop() {  # ask, drop on y — only $WT_DB_PREFIX* (db.sh refuses anything else, and the source db)
  local n=$1 a
  [[ -n $WT_DB_CONTAINER && -n $n && $n == ${WT_DB_PREFIX}* ]] || return 0
  bash $_WTDB exists "$n" || return 0
  printf 'drop database %s? [y/N] ' "$n"; read -r a </dev/tty
  [[ $a == [yY] ]] && bash $_WTDB drop "$n"
  return 0
}
# wtdb <slug|branch> [--fresh] — create this task's BE database now (`wts <slug> be` does it lazily): copy of the source db (--fresh: empty) + this branch's migrations
wtdb() {
  [ -z "$1" ] && { echo "usage: wtdb <slug> [--fresh]"; return 1; }
  local d="$WT_ROOT/$(_slug "$1")"
  [ -d "$d" ] || { echo "no worktree $d"; return 1; }
  bash $_WTDB ensure "$d" $2
}

_wtmain() { git -C "$1" worktree list --porcelain 2>/dev/null | head -1 | cut -d' ' -f2-; }   # main checkout of a worktree's repo

# wtrm <slug|branch> — remove this task's worktree (pre-v3.8 <slug>-fe / <slug>-be too); branches stay
wtrm() {
  local slug d db main; slug=$(_slug "$1")
  for d in "$WT_ROOT/$slug" "$WT_ROOT/$slug-fe" "$WT_ROOT/$slug-be"; do
    [ -d "$d" ] || continue
    db=$(_wtdbname "$d"); main=$(_wtmain "$d")
    git -C "${main:-$MONO_REPO}" worktree remove --force "$d" && echo "removed $d" && _wtdbdrop "$db"
  done
}

# wtclean — remove worktrees whose branch is merged into the base branch or gone from origin
#   (every repo with a worktree under $WT_ROOT: the monorepo and any pre-v3.8 FE/BE repo)
wtclean() {
  local repo d br track base db
  local -aU repos; repos=("$MONO_REPO")
  for d in "$WT_ROOT"/*(N/); do repos+=("$(_wtmain "$d")"); done
  for repo in ${repos:#}; do
    git -C "$repo" fetch --prune origin >/dev/null 2>&1
    base=$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo "origin/$WT_BASE_BRANCH")
    git -C "$repo" worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{print w, $2}' |
    while read -r d br; do
      case "$d" in "$WT_ROOT"/*) ;; *) continue ;; esac
      br=${br#refs/heads/}
      track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$br")
      if [ "$track" = "[gone]" ] || git -C "$repo" merge-base --is-ancestor "$br" "$base" 2>/dev/null; then
        db=$(_wtdbname "$d")
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
