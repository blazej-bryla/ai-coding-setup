# config.sh — the workflow's stack and infra settings, in one place. POSIX sh; sourced by
# shell/worktrees.zsh, the hooks and bin/wtconf (skills read values through `wtconf`).
#
# Values come from, in order of precedence: the repo's profile (`env` slot of ~/.agents/profiles/<id>.json,
# see bin/wfprofile), the machine config (default ~/.agents/config.local.zsh, override with $AGENTS_CONFIG;
# plain `export NAME='value'` lines), then the neutral defaults below. A value already in the environment
# is overridden by both files.

# Every key below, cleared first: a value inherited from the environment (e.g. exported by the shell helpers
# of an interactive shell that started Claude) must not leak into another repo.
_WF_KEYS="MONO_REPO WT_FE_DIR WT_BE_DIR FE_REPO BE_REPO WT_ROOT WT_BASE_BRANCH WT_STAGING_BRANCH WT_REMOTE_API WT_REMOTE_FE_PORT WT_BASELINE_FE_URL WT_FE_PORT_BASE WT_BE_PORT_BASE FE_API_VAR WT_FE_DEV_CMD WT_BE_DEV_CMD WT_FE_PROC_RE WT_SETUP_CMD WT_FE_SETUP_CMD WT_BE_SETUP_CMD WT_FE_DEV_BIN WT_BE_DEV_BIN WT_FE_TEST_CMD WT_BE_TEST_CMD WT_TEST_CMD WT_SERVER_CMD_RE WT_SERVER_PROC_RE WT_SERVER_PROC_NAMES WT_WATCH_CMD_RE DB_NAME_VARS WT_DB_CONTAINER WT_DB_PREFIX WT_DB_SOURCE_ENV WT_DB_USER_VAR WT_DB_PASSWORD_VAR WT_DB_MIGRATE_CMD WT_LOGIN_SCREEN_HINT WT_TRACKER_LABELS WT_TRACKER_REVIEW_STATUS WT_EPIC_BRANCH WT_STORY_PR_LABEL"
eval "unset $_WF_KEYS"

_agents_cfg=${AGENTS_CONFIG:-$HOME/.agents/config.local.zsh}
# shellcheck disable=SC1090
[ -f "$_agents_cfg" ] && . "$_agents_cfg"
unset _agents_cfg

# v4.1: per-repo values come from the repo's profile (~/.agents/profiles/<id>.json, slot `env`), found by the
# origin of $CLAUDE_PROJECT_DIR (else $PWD); they win over config.local.zsh, which keeps machine-wide values.
# The shell helpers set WF_USE_DEFAULT_PROFILE=1: outside a profiled repo they use $WF_DEFAULT_PROFILE.
# Any failure (no jq, no profile, bad JSON) → nothing loaded, the defaults below apply.
_wf_env=$(WF_USE_DEFAULT_PROFILE="${WF_USE_DEFAULT_PROFILE:-}" "${AGENTS_DIR:-$HOME/.agents}/bin/wfprofile" --env 2>/dev/null) && [ -n "$_wf_env" ] && eval "$_wf_env"
unset _wf_env

# repo and worktrees (v3.8: monorepo — one worktree per task, $WT_ROOT/<slug>, holding both apps)
: "${MONO_REPO:=$HOME/Workspace/my-app}"   # main checkout of the monorepo
: "${WT_FE_DIR:=apps/web}"                 # FE app dir, relative to the repo root (its .env.local, its rules)
: "${WT_BE_DIR:=apps/api}"                 # BE app dir, relative to the repo root (its .env, its db)
FE_REPO=$MONO_REPO BE_REPO=$MONO_REPO      # aliases: one repo for both sides
: "${WT_ROOT:=$HOME/Workspace/my-worktrees}"
: "${WT_BASE_BRANCH:=main}"                 # fallback when origin/HEAD is unknown
: "${WT_STAGING_BRANCH:=staging}"           # `wt … --staging`

# remote API mode: a FE whose worktree's BE isn't running talks to a deployed API that may accept
# exactly one local origin — the FE then runs on WT_REMOTE_FE_PORT, one task at a time
: "${WT_REMOTE_API:=}"
: "${WT_REMOTE_FE_PORT:=3000}"
: "${WT_BASELINE_FE_URL:=}"                 # deployed FE of the base branch: /pr BEFORE shots, a11y baseline
: "${WT_FE_PORT_BASE:=5200}"                # worktree ports: base + (slug checksum % 40)
: "${WT_BE_PORT_BASE:=3100}"

# stack commands and names — every command runs from the worktree root and targets its workspace
: "${FE_API_VAR:=API_BASE_URL}"             # FE env var holding the backend origin
: "${WT_FE_DEV_CMD:=npm run dev -w web -- --port \"\$PORT\"}"   # eval'd by wts with PORT and FE_API_VAR set
: "${WT_BE_DEV_CMD:=npm run dev -w api}"    # the BE reads its PORT from $WT_BE_DIR/.env
: "${WT_FE_PROC_RE:=node|npm}"              # processes `wts --take` may stop (ERE on the command line)
: "${WT_SETUP_CMD:=npm ci --prefer-offline --no-audit --no-fund}"   # the one install, at worktree creation
: "${WT_FE_SETUP_CMD:=}"                    # FE extras (e.g. e2e browsers), lazily: first `wts <slug> fe` in a worktree
: "${WT_BE_SETUP_CMD:=}"                    # BE extras, lazily: first `wts <slug> be` in a worktree
: "${WT_FE_DEV_BIN:=}"                      # FE dev binary the setup must leave in node_modules/.bin (app's or root's); empty = any node_modules
: "${WT_BE_DEV_BIN:=}"                      # same for the BE
: "${WT_FE_TEST_CMD:=npm test -w web}"      # non-watch unit tests of each app
: "${WT_BE_TEST_CMD:=npm test -w api}"
: "${WT_TEST_CMD:=$WT_FE_TEST_CMD | $WT_BE_TEST_CMD}"   # what bash-guard points agents to

# bash-guard: what counts as starting a server / a server process / a watch-mode test run (ERE)
: "${WT_SERVER_CMD_RE:=^npm[[:space:]]+(run[[:space:]]+)?(dev|start)\\b}"
: "${WT_SERVER_PROC_RE:=(^|[/ ])node( |\$)}"
: "${WT_SERVER_PROC_NAMES:=node}"
: "${WT_WATCH_CMD_RE:=}"

# per-worktree BE database (Postgres in a Docker container); empty container = feature off
: "${DB_NAME_VARS:=DB_NAME}"                # BE env var(s) naming the database; the first is the main one
: "${WT_DB_CONTAINER:=}"
: "${WT_DB_PREFIX:=app_}"
: "${WT_DB_SOURCE_ENV:=$MONO_REPO/$WT_BE_DIR/.env}"
: "${WT_DB_USER_VAR:=DB_USER}"
: "${WT_DB_PASSWORD_VAR:=DB_PASSWORD}"
: "${WT_DB_MIGRATE_CMD:=}"

# browser login, tracker, PRs
: "${WT_LOGIN_SCREEN_HINT:=a login screen}"
: "${WT_TRACKER_LABELS:=story=story fe=frontend be=backend}"
: "${WT_TRACKER_REVIEW_STATUS:=}"                # empty = /work leaves the status alone
: "${WT_EPIC_BRANCH:=}"                     # e.g. epic/{KEY}; empty = the epic issue's branchName
: "${WT_STORY_PR_LABEL:=}"

eval "export $_WF_KEYS"
unset _WF_KEYS
