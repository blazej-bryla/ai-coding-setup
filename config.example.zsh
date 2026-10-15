# config.example.zsh — template for ~/.agents/config.local.zsh, the one place your stack and infra
# values live. hooks/lib/config.sh reads that file (or $AGENTS_CONFIG) and fills every key you leave
# out with the default shown here. Hooks source it from bash, so keep to plain `export NAME='value'`
# lines. `~/.agents/bin/wtconf` prints the effective values — that's how the skills read them.
#
#   cp ~/.agents/config.example.zsh ~/.agents/config.local.zsh   # then edit
#
# The shell helpers pick it up through shell/worktrees.zsh (source that from ~/.zshrc).

# --- repos and worktrees ---------------------------------------------------------------------------
export FE_REPO="$HOME/Workspace/my-frontend"          # main checkout of the frontend repo
export BE_REPO="$HOME/Workspace/my-backend"           # main checkout of the backend repo
export WT_ROOT="$HOME/Workspace/my-worktrees"         # task worktrees: $WT_ROOT/<slug>-fe, <slug>-be
export WT_BASE_BRANCH='main'                          # base branch when origin/HEAD doesn't say
export WT_STAGING_BRANCH='staging'                    # what `wt <branch> <side> --staging` branches from

# --- remote API mode ---------------------------------------------------------------------------------
# A FE worktree without its own BE worktree talks to a deployed API. If that API (or your SSO
# provider) accepts only one local origin, the FE has to run on that port — one task at a time;
# `wts … --take` and `wtwho` manage who holds it.
export WT_REMOTE_API=''                               # e.g. https://api.dev.example.com; empty = no remote mode
export WT_REMOTE_FE_PORT='3000'
export WT_BASELINE_FE_URL=''                          # deployed FE of the base branch: /pr BEFORE shots + pixel diff, a11y baseline
export WT_FE_PORT_BASE='5200'                         # worktree ports: base + (slug checksum % 40)
export WT_BE_PORT_BASE='3100'

# --- stack ----------------------------------------------------------------------------------------------
export FE_API_VAR='API_BASE_URL'                      # FE env var holding the backend origin (written to .env.local)
export WT_FE_DEV_CMD='npm run dev -- --port "$PORT"'  # how `wts` starts the FE; $PORT and $FE_API_VAR are set
export WT_FE_REMOTE_DEV_CMD='npm run dev'             # the main checkout against the remote API (sequential /pr shots)
export WT_BE_DEV_CMD='npm run dev'                    # how `wts <slug> be` starts the BE
export WT_FE_PROC_RE='node|npm'                       # processes `wts --take` may stop (ERE on the command line)
export WT_FE_SETUP_CMD='npm ci --prefer-offline --no-audit --no-fund'   # run in every new FE worktree
export WT_BE_SETUP_CMD='npm ci --prefer-offline --no-audit --no-fund'   # run in every new BE worktree
export WT_TEST_CMD='npm test -- --run'                # the non-watch test command bash-guard points agents to

# bash-guard: agents never start servers, kill them, or run tests in watch mode (EREs on each command segment)
export WT_SERVER_CMD_RE='^npm[[:space:]]+(run[[:space:]]+)?(dev|start)\b'
export WT_SERVER_PROC_RE='(^|[/ ])node( |$)'          # `kill <pid>` is refused when the pid's command matches
export WT_SERVER_PROC_NAMES='node'                    # `pkill <name>` / lsof-pipelines naming these are refused
export WT_WATCH_CMD_RE=''                             # extra watch-mode commands, e.g. a bare `npm test`

# --- per-worktree database (Postgres in Docker); leave WT_DB_CONTAINER empty to switch it off -------------
export DB_NAME_VARS='DB_NAME'                         # BE env var(s) naming the database; the first is the main one
export WT_DB_CONTAINER=''                             # e.g. my-db-local
export WT_DB_PREFIX='app_'                            # worktree DBs are <prefix><slug>; nothing else is ever dropped
export WT_DB_SOURCE_ENV="$BE_REPO/.env"               # where the source DB name, user and password come from
export WT_DB_USER_VAR='DB_USER'
export WT_DB_PASSWORD_VAR='DB_PASSWORD'
export WT_DB_MIGRATE_CMD=''                           # e.g. npm run migrate; empty = copy only

# --- browser login, tracker, PRs ------------------------------------------------------------------------
export WT_LOGIN_SCREEN_HINT='a login screen'          # what the SSO login page looks like, so agents recognise it
export WT_TRACKER_LABELS='story=story fe=frontend be=backend'   # story label; FE/BE sub-issue labels (also ticket title prefixes)
export WT_TRACKER_REVIEW_STATUS=''                    # status /work offers to set when a branch is done; empty = don't
export WT_EPIC_BRANCH=''                              # e.g. epic/{KEY}; empty = the epic issue's own branch name
export WT_STORY_PR_LABEL=''                           # label for story PRs; empty = none
export WT_PR_SKILL='.claude/skills/create-pr/SKILL.md'                 # the project's own PR skill, if any
export WT_CHANGE_SUMMARY_SKILL='.claude/skills/change-summary/SKILL.md'

# --- /work -------------------------------------------------------------------------------------------------
export WT_WORKER_TIMEOUT_MIN='30'                     # minutes before /work asks about an implementer that has not returned

# agent-browser encrypts the saved login state with this key — keep the real value out of every repo
# (~/.zshrc or a secret manager):
# export AGENT_BROWSER_ENCRYPTION_KEY=...
