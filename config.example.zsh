# config.example.zsh — template for ~/.agents/config.local.zsh, the one place your stack and infra
# values live. hooks/lib/config.sh reads that file (or $AGENTS_CONFIG) and fills every key you leave
# out with the default shown here. Hooks source it from bash, so keep to plain `export NAME='value'`
# lines. `~/.agents/bin/wtconf` prints the effective values — that's how the skills read them.
#
#   cp ~/.agents/config.example.zsh ~/.agents/config.local.zsh   # then edit
#
# The shell helpers pick it up through shell/worktrees.zsh (source that from ~/.zshrc).
#
# Several repos? Per-repo values can live in each repo's profile instead (~/.agents/profiles/<id>.json,
# slot `env`, written by /wf-init; they win over this file inside that repo), and this file keeps only
# machine-wide values such as the port bases and WF_DEFAULT_PROFILE:
# export WF_DEFAULT_PROFILE=''                         # profile id the shell helpers use outside a profiled repo

# --- repo and worktrees ----------------------------------------------------------------------------
# One monorepo holds the frontend and the backend app; one worktree (and one Claude session) per task.
export MONO_REPO="$HOME/Workspace/my-app"             # main checkout of the monorepo (FE_REPO / BE_REPO are aliases)
export WT_FE_DIR='apps/web'                           # the frontend app, relative to the repo root
export WT_BE_DIR='apps/api'                           # the backend app, relative to the repo root
export WT_ROOT="$HOME/Workspace/my-worktrees"         # task worktrees: $WT_ROOT/<slug>
export WT_BASE_BRANCH='main'                          # base branch when origin/HEAD doesn't say
export WT_STAGING_BRANCH='staging'                    # what `wt <branch> --staging` branches from

# --- remote API mode ---------------------------------------------------------------------------------
# A FE whose worktree's BE isn't running talks to a deployed API. If that API (or your SSO
# provider) accepts only one local origin, the FE has to run on that port — one task at a time;
# `wts … --take` and `wtwho` manage who holds it.
export WT_REMOTE_API=''                               # e.g. https://api.dev.example.com; empty = no remote mode
export WT_REMOTE_FE_PORT='3000'
export WT_BASELINE_FE_URL=''                          # deployed FE of the base branch: /pr BEFORE shots + pixel diff, a11y baseline
export WT_FE_PORT_BASE='5200'                         # worktree ports: base + (slug checksum % 40)
export WT_BE_PORT_BASE='3100'

# --- stack — every command runs from the worktree root and targets one workspace -------------------------
export FE_API_VAR='API_BASE_URL'                      # FE env var holding the backend origin (`wts` sets it inline)
export WT_FE_DEV_CMD='npm run dev -w web -- --port "$PORT"'   # how `wts` starts the FE; $PORT and $FE_API_VAR are set
export WT_BE_DEV_CMD='npm run dev -w api'             # how `wts <slug> be` starts the BE (PORT from $WT_BE_DIR/.env)
export WT_FE_PROC_RE='node|npm'                       # processes `wts --take` may stop (ERE on the command line)
export WT_SETUP_CMD='npm ci --prefer-offline --no-audit --no-fund'   # the one install in every new worktree
export WT_FE_SETUP_CMD=''                             # FE extras (e.g. e2e browsers), once, on the first `wts <slug> fe`
export WT_BE_SETUP_CMD=''                             # BE extras, once, on the first `wts <slug> be`
export WT_FE_DEV_BIN=''                               # FE dev binary the setup must leave in node_modules/.bin (e.g. next); empty = any node_modules
export WT_BE_DEV_BIN=''                               # same for the BE (e.g. nest)
export WT_FE_TEST_CMD='npm test -w web'               # non-watch unit tests of each app
export WT_BE_TEST_CMD='npm test -w api'
export WT_TEST_CMD='npm test -w web | npm test -w api'   # what bash-guard points agents to

# bash-guard: agents never start servers, kill them, or run tests in watch mode (EREs on each command segment)
export WT_SERVER_CMD_RE='^npm[[:space:]]+(run[[:space:]]+)?(dev|start)\b'
export WT_SERVER_PROC_RE='(^|[/ ])node( |$)'          # `kill <pid>` is refused when the pid's command matches
export WT_SERVER_PROC_NAMES='node'                    # `pkill <name>` / lsof-pipelines naming these are refused
export WT_WATCH_CMD_RE=''                             # extra watch-mode commands, e.g. a bare `npm test`

# --- per-worktree database (Postgres in Docker); leave WT_DB_CONTAINER empty to switch it off -------------
export DB_NAME_VARS='DB_NAME'                         # BE env var(s) naming the database; the first is the main one
export WT_DB_CONTAINER=''                             # e.g. my-db-local
export WT_DB_PREFIX='app_'                            # worktree DBs are <prefix><slug>; nothing else is ever dropped
export WT_DB_SOURCE_ENV="$MONO_REPO/apps/api/.env"    # where the source DB name, user and password come from
export WT_DB_USER_VAR='DB_USER'
export WT_DB_PASSWORD_VAR='DB_PASSWORD'
export WT_DB_MIGRATE_CMD=''                           # e.g. npm run migrate -w api; empty = copy only

# --- browser login, tracker, PRs ------------------------------------------------------------------------
export WT_LOGIN_SCREEN_HINT='a login screen'          # what the SSO login page looks like, so agents recognise it
export WT_TRACKER_LABELS='story=story fe=frontend be=backend'   # story label; FE/BE sub-issue labels (also ticket title prefixes)
export WT_TRACKER_REVIEW_STATUS=''                    # status /work offers to set when a branch is done; empty = don't
export WT_EPIC_BRANCH=''                              # e.g. epic/{KEY}; empty = the epic issue's own branch name
export WT_STORY_PR_LABEL=''                           # label for story PRs; empty = none

# agent-browser encrypts the saved login state with this key — keep the real value out of every repo
# (~/.zshrc or a secret manager):
# export AGENT_BROWSER_ENCRYPTION_KEY=...
