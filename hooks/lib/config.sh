# config.sh — the workflow's stack and infra settings, in one place. POSIX sh; sourced by
# shell/worktrees.zsh, the hooks and bin/wtconf (skills read values through `wtconf`).
#
# Real values live in the config file (default ~/.agents/config.local.zsh, override with
# $AGENTS_CONFIG; plain `export NAME='value'` lines). Anything it leaves unset gets the neutral
# default below. A value already in the environment is overridden by the config file.

_agents_cfg=${AGENTS_CONFIG:-$HOME/.agents/config.local.zsh}
# shellcheck disable=SC1090
[ -f "$_agents_cfg" ] && . "$_agents_cfg"
unset _agents_cfg

# repos and worktrees
: "${FE_REPO:=$HOME/Workspace/my-frontend}"
: "${BE_REPO:=$HOME/Workspace/my-backend}"
: "${WT_ROOT:=$HOME/Workspace/my-worktrees}"
: "${WT_BASE_BRANCH:=main}"                 # fallback when origin/HEAD is unknown
: "${WT_STAGING_BRANCH:=staging}"           # `wt … --staging`

# remote API mode: a FE worktree without its own BE talks to a deployed API that may accept
# exactly one local origin — the FE then runs on WT_REMOTE_FE_PORT, one task at a time
: "${WT_REMOTE_API:=}"
: "${WT_REMOTE_FE_PORT:=3000}"
: "${WT_BASELINE_FE_URL:=}"                 # deployed FE of the base branch: /pr BEFORE shots, a11y baseline
: "${WT_FE_PORT_BASE:=5200}"                # worktree ports: base + (slug checksum % 40)
: "${WT_BE_PORT_BASE:=3100}"

# stack commands and names
: "${FE_API_VAR:=API_BASE_URL}"             # FE env var holding the backend origin
: "${WT_FE_DEV_CMD:=npm run dev -- --port \"\$PORT\"}"   # eval'd by wts with PORT and FE_API_VAR exported
: "${WT_FE_REMOTE_DEV_CMD:=npm run dev}"    # main checkout against the remote API (sequential /pr shots)
: "${WT_BE_DEV_CMD:=npm run dev}"
: "${WT_FE_PROC_RE:=node|npm}"              # processes `wts --take` may stop (ERE on the command line)
: "${WT_FE_SETUP_CMD:=npm ci --prefer-offline --no-audit --no-fund}"
: "${WT_BE_SETUP_CMD:=npm ci --prefer-offline --no-audit --no-fund}"
: "${WT_TEST_CMD:=the non-watch test command from AGENTS.md}"

# bash-guard: what counts as starting a server / a server process / a watch-mode test run (ERE)
: "${WT_SERVER_CMD_RE:=^npm[[:space:]]+(run[[:space:]]+)?(dev|start)\\b}"
: "${WT_SERVER_PROC_RE:=(^|[/ ])node( |\$)}"
: "${WT_SERVER_PROC_NAMES:=node}"
: "${WT_WATCH_CMD_RE:=}"

# per-worktree BE database (Postgres in a Docker container); empty container = feature off
: "${DB_NAME_VARS:=DB_NAME}"                # BE env var(s) naming the database; the first is the main one
: "${WT_DB_CONTAINER:=}"
: "${WT_DB_PREFIX:=app_}"
: "${WT_DB_SOURCE_ENV:=$BE_REPO/.env}"
: "${WT_DB_USER_VAR:=DB_USER}"
: "${WT_DB_PASSWORD_VAR:=DB_PASSWORD}"
: "${WT_DB_MIGRATE_CMD:=}"

# browser login, tracker, PRs
: "${WT_LOGIN_SCREEN_HINT:=a login screen}"
: "${WT_TRACKER_LABELS:=story=story fe=frontend be=backend}"
: "${WT_TRACKER_REVIEW_STATUS:=}"                # empty = /work leaves the status alone
: "${WT_EPIC_BRANCH:=}"                     # e.g. epic/{KEY}; empty = the epic issue's branchName
: "${WT_STORY_PR_LABEL:=}"
: "${WT_PR_SKILL:=.claude/skills/create-pr/SKILL.md}"
: "${WT_CHANGE_SUMMARY_SKILL:=.claude/skills/change-summary/SKILL.md}"

export FE_REPO BE_REPO WT_ROOT WT_BASE_BRANCH WT_STAGING_BRANCH WT_REMOTE_API WT_REMOTE_FE_PORT \
  WT_BASELINE_FE_URL WT_FE_PORT_BASE WT_BE_PORT_BASE FE_API_VAR WT_FE_DEV_CMD WT_FE_REMOTE_DEV_CMD \
  WT_BE_DEV_CMD WT_FE_PROC_RE WT_FE_SETUP_CMD WT_BE_SETUP_CMD WT_TEST_CMD WT_SERVER_CMD_RE \
  WT_SERVER_PROC_RE WT_SERVER_PROC_NAMES WT_WATCH_CMD_RE DB_NAME_VARS WT_DB_CONTAINER WT_DB_PREFIX \
  WT_DB_SOURCE_ENV WT_DB_USER_VAR WT_DB_PASSWORD_VAR WT_DB_MIGRATE_CMD WT_LOGIN_SCREEN_HINT \
  WT_TRACKER_LABELS WT_TRACKER_REVIEW_STATUS WT_EPIC_BRANCH WT_STORY_PR_LABEL WT_PR_SKILL \
  WT_CHANGE_SUMMARY_SKILL
