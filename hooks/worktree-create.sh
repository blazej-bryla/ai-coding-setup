#!/bin/bash
# WorktreeCreate hook (v3.1) — replaces Claude Code's default `git worktree add`.
# Fired by `claude --worktree <name>` and by subagents with `isolation: worktree`.
# `wt` passes the task slug as <name> (--worktree rejects names over 64 chars) and the
# full branch in $WT_BRANCH; the hook uses WT_BRANCH only when its slug matches <name>.
# Input on stdin: JSON with "name" (what was passed to --worktree). Prints the
# worktree path on stdout; everything else goes to stderr.
#
#   name = TODO-12-add-due-dates (with or without a user/ prefix)
#          → slug todo-12, worktree $WT_ROOT/todo-12-<fe|be>, branch exactly as given
#   name = #1234 → slug pr-1234, $WT_ROOT/pr-1234-<side>, branch pr-1234 from the PR head
#   new branches start from $WT_BASE, else the branch origin/HEAD points to ($WT_BASE_BRANCH);
#          an explicit WT_BASE that exists as a LOCAL branch wins over origin/<base>
#          (a stacked ticket's blocker may not be pushed yet), e.g. wt <ticket> fe --base <blocker>
#   name with no issue key → a subagent worktree (isolation: worktree): branch wip/<name>
#          from the CURRENT HEAD of $CLAUDE_PROJECT_DIR, never from origin/<base>;
#          dir $WT_ROOT/<name>-<side>
#
# side = fe when this repo is FE_REPO, else be. FE and BE worktrees of one task share
# the slug, so they share the port offset: FE $WT_FE_PORT_BASE+off, BE $WT_BE_PORT_BASE+off. Idempotent.
# Repos, ports, env var names, setup commands, DB: lib/config.sh (+ ~/.agents/config.local.zsh).
set -eu

. "$(dirname "$0")/lib/config.sh"
FE_REMOTE_API=$WT_REMOTE_API                     # FE worktree with no BE worktree talks to this API
base=${WT_BASE:-$(git -C "${CLAUDE_PROJECT_DIR:-.}" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}
base=${base:-$WT_BASE_BRANCH}
repo=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
name=$(jq -r '.name // empty')
[ -n "$name" ] || { echo "worktree-create: no name in hook input" >&2; exit 1; }

main=$(git -C "$repo" worktree list --porcelain | head -1 | cut -d' ' -f2-)   # main checkout, also from a worktree
case "$main" in "$FE_REPO"|"$FE_REPO"/) side=fe ;; *) side=be ;; esac

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
dir=$WT_ROOT/$slug-$side

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

  ex="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/info/exclude"      # screenshots (agent-browser writes them to <worktree>/.shots/)
  mkdir -p "$(dirname "$ex")"; grep -qx '.shots/' "$ex" 2>/dev/null || echo '.shots/' >> "$ex"
  cp "$repo"/.env "$repo"/.env.local "$repo"/CLAUDE.local.md "$dir"/ 2>/dev/null || true   # CLAUDE.local.md imports the private worker contract (~/.agents/projects/<repo>.md)

  setvar() {  # setvar <file> <KEY> <value> — replace the KEY= line or append it; never a duplicate
    local f=$1 k=$2 v=$3
    if grep -q "^$k=" "$f" 2>/dev/null; then sed -i '' "s|^$k=.*|$k=$v|" "$f"; else printf '%s=%s\n' "$k" "$v" >> "$f"; fi
  }

  off=$(( $(printf %s "$slug" | cksum | cut -d' ' -f1) % 40 ))
  if [ "$side" = fe ]; then
    port=$((WT_FE_PORT_BASE + off))                            # remote-API mode runs on $WT_REMOTE_FE_PORT regardless of PORT
    setvar "$dir/.env.local" PORT "$port"                     # `wts` starts the FE dev command with this PORT
    if [ -d "$WT_ROOT/$slug-be" ]; then                        # this task's BE exists → point at it
      setvar "$dir/.env.local" "$FE_API_VAR" "http://localhost:$((WT_BE_PORT_BASE + off))"
    elif [ -n "$FE_REMOTE_API" ]; then                         # no BE worktree → the remote API
      setvar "$dir/.env.local" "$FE_API_VAR" "$FE_REMOTE_API"
    fi
  else
    port=$((WT_BE_PORT_BASE + off))
    setvar "$dir/.env" PORT "$port"                            # BE keeps its port in .env
    db=$(printf %s "$slug" | tr -c 'a-zA-Z0-9' _ | tr A-Z a-z)
    [ -n "$WT_DB_CONTAINER" ] && for v in $DB_NAME_VARS; do   # per-worktree DB only when configured
      cur=$(grep -h "^$v=" "$dir/.env" 2>/dev/null | tail -1 | cut -d= -f2-)
      # subagent: keep the task's $WT_DB_PREFIX* db name copied from the caller's .env; never the main db
      if [ -n "${from_head:-}" ] && case "$cur" in "$WT_DB_PREFIX"*) true ;; *) false ;; esac; then continue; fi
      setvar "$dir/.env" "$v" "$WT_DB_PREFIX$db"
    done
  fi
  echo "worktree-create: $dir on $branch, PORT=$port" >&2

  (cd "$dir" && set +u \
    && { n="${NVM_DIR:-$HOME/.nvm}/nvm.sh"; [ ! -s "$n" ] || { . "$n" && nvm use --silent >&2; } || true; } \
    && if [ "$side" = fe ]; then eval "$WT_FE_SETUP_CMD"; else eval "$WT_BE_SETUP_CMD"; fi >&2) \
    || echo "worktree-create: setup command failed in $dir — run it by hand" >&2

  if [ "$side" = be ] && [ -z "${from_head:-}" ] && [ -n "$WT_DB_CONTAINER" ]; then   # task worktrees only (subagents get no db): copy of the source db + this branch's migrations
    . "$(dirname "$0")/lib/db.sh"                              # (needs node_modules, so after npm ci)
    wt_db_ensure "$dir" \
      || echo "worktree-create: WARNING database setup for $dir failed (see above) — worktree is fine; fix it, then \`wtdb $slug\`" >&2
  fi
fi

echo "$dir"
