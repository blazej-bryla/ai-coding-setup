#!/bin/bash
# WorktreeCreate hook (v3.8, monorepo) — replaces Claude Code's default `git worktree add`.
# Fired by `claude --worktree <name>` and by subagents with `isolation: worktree`.
# `wt` passes the task slug as <name> (--worktree rejects names over 64 chars) and the
# full branch in $WT_BRANCH; the hook uses WT_BRANCH only when its slug matches <name>.
# Input on stdin: JSON with "name" (what was passed to --worktree). Prints the
# worktree path on stdout; everything else goes to stderr.
#
#   name = TODO-12-add-due-dates (with or without a user/ prefix)
#          → slug todo-12, worktree $WT_ROOT/todo-12 (both apps), branch exactly as given
#   name = #1234 → slug pr-1234, $WT_ROOT/pr-1234, branch pr-1234 from the PR head
#   new branches start from $WT_BASE, else the branch origin/HEAD points to ($WT_BASE_BRANCH);
#          an explicit WT_BASE that exists as a LOCAL branch wins over origin/<base>
#          (a stacked ticket's blocker may not be pushed yet), e.g. wt <ticket> --base <blocker>
#   name with no issue key → a subagent worktree (isolation: worktree): branch wip/<name>
#          from the CURRENT HEAD of $CLAUDE_PROJECT_DIR, never from origin/<base>; dir $WT_ROOT/<name>
#
# One worktree per task holds both apps: the env files of BOTH app dirs are copied, the FE PORT goes into
# $WT_FE_DIR/.env.local and the BE PORT into $WT_BE_DIR/.env (one offset from the slug: FE
# $WT_FE_PORT_BASE+off, BE $WT_BE_PORT_BASE+off), the BE's DB name is written, then ONE install:
# `nvm use` the repo's .nvmrc (else engines.node), $WT_SETUP_CMD — all output in
# <worktree>/.shots/setup.log. Then the dev binaries ($WT_FE_DEV_BIN, $WT_BE_DEV_BIN) must be in node_modules,
# else the hook fails (no worktree reported ready without deps) and logs to ~/.agents/friction.log.
# A worktree whose deps are missing is set up again on the next run (e.g. after `nvm install <v>`).
# No database and no app extras here: `wts <slug> be` creates the db (lib/db.sh) and runs $WT_BE_SETUP_CMD,
# `wts <slug> fe` runs $WT_FE_SETUP_CMD (e.g. e2e browsers) — each once per worktree, lazily. Idempotent.
# Repo, app dirs, ports, env var names, setup commands, DB: lib/config.sh (+ ~/.agents/config.local.zsh).
set -eu

. "$(dirname "$0")/lib/config.sh"
. "$(dirname "$0")/lib/node.sh"
base=${WT_BASE:-$(git -C "${CLAUDE_PROJECT_DIR:-.}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}
base=${base:-$WT_BASE_BRANCH}
repo=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
name=$(jq -r '.name // empty')
[ -n "$name" ] || { echo "worktree-create: no name in hook input" >&2; exit 1; }

slugof() {  # issue key, uppercased; fallback: strip user/ prefix
  local k; k=$(printf %s "$1" | grep -oiE '[a-z]+-[0-9]+(-[0-9]+)?' | head -1 | tr A-Z a-z)
  [ -n "$k" ] && printf %s "$k" || printf %s "${1#*/}"
}

case "$name" in
  \#*) num=${name#\#}; branch="pr-$num"; slug="pr-$num"
       git -C "$repo" fetch origin "pull/$num/head:$branch" >&2 ;;
  *)   if printf %s "$name" | grep -qiE '(^|[^a-z0-9])[a-z]+-[0-9]+(-[0-9]+)?([-_/.]|$)'; then   # key must end at a boundary: agent-4f2a is not a key
         slug=$(slugof "$name"); branch=$name
         # full branch name comes from `wt` via env; honour it only for THIS task's name,
         # never for subagent worktrees (they inherit the env but must branch from HEAD)
         if [ -n "${WT_BRANCH:-}" ] && [ "$(slugof "$WT_BRANCH")" = "$slug" ]; then branch=$WT_BRANCH; fi
       else                                                      # subagent: build on top of the caller
         branch="wip/$name"; slug=$name; from_head=1
       fi ;;
esac
dir=$WT_ROOT/$slug

if [ ! -d "$dir" ]; then
  mkdir -p "$WT_ROOT"
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add "$dir" "$branch" >&2
  elif [ -n "${from_head:-}" ]; then
    git -C "$repo" worktree add "$dir" -b "$branch" HEAD >&2
  elif git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git -C "$repo" fetch origin "$branch" >&2
    git -C "$repo" worktree add "$dir" -b "$branch" "origin/$branch" >&2
  elif [ -n "${WT_BASE:-}" ] && git -C "$repo" show-ref --verify --quiet "refs/heads/$WT_BASE"; then
    git -C "$repo" worktree add "$dir" -b "$branch" "$WT_BASE" >&2
  else
    git -C "$repo" fetch origin "$base" >&2
    git -C "$repo" worktree add "$dir" -b "$branch" "origin/$base" >&2
  fi

  ex="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "$(dirname "$ex")"
  for p in .shots/ CLAUDE.local.md; do   # screenshots (agent-browser writes them to <worktree>/.shots/); the private worker-contract import
    grep -qx "$p" "$ex" 2>/dev/null || echo "$p" >> "$ex"
  done
  cp "$repo"/CLAUDE.local.md "$dir"/ 2>/dev/null || true   # imports the private worker contract (~/.agents/projects/<repo>.md)
  for app in "$WT_FE_DIR" "$WT_BE_DIR"; do                 # env files of BOTH apps
    cp "$repo/$app"/.env "$repo/$app"/.env.local "$dir/$app"/ 2>/dev/null || true
  done

  setvar() {  # setvar <file> <KEY> <value> — replace the KEY= line or append it; never a duplicate
    local f=$1 k=$2 v=$3
    if grep -q "^$k=" "$f" 2>/dev/null; then sed -i '' "s|^$k=.*|$k=$v|" "$f"; else printf '%s=%s\n' "$k" "$v" >> "$f"; fi
  }

  off=$(( $(printf %s "$slug" | cksum | cut -d' ' -f1) % 40 ))
  fe_port=$((WT_FE_PORT_BASE + off)) be_port=$((WT_BE_PORT_BASE + off))
  setvar "$dir/$WT_FE_DIR/.env.local" PORT "$fe_port"     # `wts <slug> fe` (local mode) runs the FE on it; remote mode uses $WT_REMOTE_FE_PORT
  setvar "$dir/$WT_BE_DIR/.env" PORT "$be_port"           # the BE keeps its port in .env; `wts <slug> fe` points the FE at it while it listens
  db=$(printf %s "$slug" | tr -c 'a-zA-Z0-9' _ | tr A-Z a-z)
  [ -n "$WT_DB_CONTAINER" ] && for v in $DB_NAME_VARS; do   # the name only; `wts <slug> be` creates the db
    cur=$(grep -h "^$v=" "$dir/$WT_BE_DIR/.env" 2>/dev/null | tail -1 | cut -d= -f2-)
    # subagent: keep the task's $WT_DB_PREFIX* db name copied from the caller's .env; never the main db
    if [ -n "${from_head:-}" ] && case "$cur" in "$WT_DB_PREFIX"*) true ;; *) false ;; esac; then continue; fi
    setvar "$dir/$WT_BE_DIR/.env" "$v" "$WT_DB_PREFIX$db"
  done
  echo "worktree-create: $dir on $branch, FE PORT=$fe_port, BE PORT=$be_port" >&2
fi

if ! wt_deps_check "$dir" >/dev/null 2>&1; then   # new worktree, or an earlier setup that failed
  log=$dir/.shots/setup.log
  mkdir -p "$dir/.shots"
  echo "worktree-create: installing in $dir — log in .shots/setup.log" >&2
  if (cd "$dir" && set +eu \
      && echo "== $(date -u +%FT%TZ) setup in $dir" \
      && wt_node_use "$dir" && echo "node -v: $(node -v), npm -v: $(npm -v)" \
      && echo "== $WT_SETUP_CMD" && eval "$WT_SETUP_CMD" \
      && echo "== deps check" && wt_deps_check "$dir") >"$log" 2>&1 </dev/null; then
    echo "worktree-create: setup ok — $(grep -m1 '^node: ' "$log")" >&2
  else
    why=$(grep -m1 -E '^(node|deps): ' "$log" || tail -1 "$log")
    echo "worktree-create: setup failed — see .shots/setup.log ($dir/.shots/setup.log)" >&2
    echo "worktree-create: $why" >&2
    jq -nc --arg d "$(date -u +%FT%TZ)" --arg s "$slug" --arg w "worktree setup failed: $why" --arg l "$log" \
      '{date:$d,session:$s,slug:$s,side:"setup",what:$w,workaround:("see "+$l+", fix, run wt again"),cost:"blocked"}' \
      >> "$HOME/.agents/friction.log" || true
    exit 1
  fi
fi

echo "$dir"
