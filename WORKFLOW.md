# Workflow — the one-page tour

**One identifier for everything.** The task key in the branch name is the slug: `TODO-12-add-due-dates`
→ `todo-12`. It names the worktrees (`$WT_ROOT/todo-12-fe`, `$WT_ROOT/todo-12-be`), the Claude sessions
(`todo-12-fe`, `todo-12-be`) and the task's state directory, `~/.agents/scratch/todo-12/` — context, spec
and tickets (`tickets/fe/`, `tickets/be/`) live there, outside both repos, so every worktree of the task
sees the same plan.

**Configuration.** Your stack lives in `~/.agents/config.local.zsh` (template: `config.example.zsh`):
repo paths, ports, dev and setup commands, the per-worktree database, tracker labels, what the login
screen looks like. `wtconf` prints the effective values; the hooks, shell helpers, mod and skills all
read the same file.

## Shell (`shell/worktrees.zsh`)

| Command | What it does |
|---|---|
| `wt <branch> <fe\|be> [--base <branch>\|--staging] [prompt]` | Claude in the task's worktree (the WorktreeCreate hook makes it; base = the repo's default branch) — e.g. `wt TODO-12-add-due-dates fe /work` |
| `wts <slug> <fe\|be> [--local\|--remote] [--port N] [--take]` | dev server in the worktree. A FE without a BE worktree runs against the remote API on the shared port; `--take` moves that port from another worktree |
| `wtwho` | who holds the shared FE port, and which local-mode FE ports are up |
| `cdwt <slug> <side>` | jump into a worktree |
| `wtls` | list the worktrees of both repos |
| `wtrm <slug> [fe\|be]` | remove a task's worktrees (branches stay; BE: offers to drop its database) |
| `wtclean` | remove worktrees whose branch is merged or gone (BE: offers to drop the database) |
| `wtdb <slug> [--fresh]` | the BE worktree's own database: a copy of the source DB (`--fresh`: empty) plus this branch's migrations; new BE worktrees get one from the hook |
| `friction [days]` | the friction log of the last N days (default 7), grouped by what went wrong |

Each worktree gets its own ports (FE and BE share an offset derived from the slug), its own `.env`
copy and, on the BE side, its own database. Only the shared remote-API port is contested: two FE tasks
can run at once, but only one holds that port (`wts … --take`, `wtwho`).

Skills never start or stop dev servers — they ask you to run `wts` and wait, and `/work` keeps landing
other tickets meanwhile. `hooks/bash-guard.sh` enforces it, together with "no watch-mode tests".

Once a week: `friction 7`; the most frequent entries are the next round of fixes.

## Skills

| Skill | When |
|---|---|
| `/kickoff <issue>` | plan: context.md → grilling → spec / tickets (both repos in one run) |
| `/work` | this side's ticket loop: waves of implementer subagents, review, teach, squash-merge, commit |
| `/implement` | one ticket in this session |
| `/bugfix <issue>` | a bug: asks where to verify it (`Verify by: ui …`), before/after screenshots |
| `/deep-review` | review; a risk classifier picks the dimensions — `light`, `full` or "only codebase and qa" override it |
| `/pr` | PR through the project's own PR skill + before/after screenshots + an optional diagram + change summary |
| `/address-review` | the PR's open review threads |
| `/commit` | a commit from the current changes (amends only an unpushed commit, and says so) |

## Story mode (`mode: story` in context.md; rules in `skills/work/STORY.md`)

- **When:** `/kickoff` suggests it when the issue carries your story label — tickets become tracker
  sub-issues and each gets its own PR. Otherwise it suggests local mode (one PR per repo). You choose;
  ticket and line counts are only a hint. No `mode:` means local.
- **Stack or sibling:** a ticket with no blocker in its repo opens its PR against the story branch;
  with one blocker, against the blocker's branch (a stack). `/kickoff` linearises edges so each ticket
  has at most one blocker. `gh stack link` only for chains of two or more. In a chain the bottom PR is
  ready for review, the ones above stay drafts until the one below is approved.
- **No waiting:** `/work` builds the whole story at once — a ticket starts as soon as its blocker is
  committed locally; human review never blocks the loop. After each ticket, one question: push and
  open the PR? Force pushes after a restack only after asking.
- **Story PR** (`/pr story`, story branch → base or epic): a list of the sub-PRs; every change was
  reviewed in its sub-PR, so this one is only checked for integration and conflicts.

## The `workflow` mod (`mods/workflow/`)

Loaded globally through `env.CLAUDE_CODE_PLUGIN_DIRS`. Read-only: it reads files and a few
environment variables, never writes, never touches tool calls or prompts, never calls the model.

**Band above the prompt** — only inside a task worktree, or in a main checkout whose branch has a
scratch directory:

```
todo-42 · fe · story   tickets 3/7 done   wave: 04, 05   waiting: be/02
PRs: #210 ready · #211 draft · #212 draft        :3000 → todo-42-fe
```

`wave` = tickets ready to start (blockers done), `waiting` = unfinished blockers in the other repo.
The data comes from `context.md` and `tickets/<side>/*.md`; who holds the shared port comes from the
`.shots/.fe-url` files `wts` writes. It refreshes after every turn and every 20 s; any read error just
hides the band.

**Commands without a Claude turn** (the output is a transcript line the model never sees):

| Command | Shows |
|---|---|
| `/tickets` | this side's frontier: ready / blocked (by what) / done, one line per ticket |
| `/who` | who holds the shared FE port and which worktrees run a FE |
| `/story` | story mode only: ticket, issue, branch, base, PR and its status |

Off for one session: `claude --safe-mode`; for good: remove `CLAUDE_CODE_PLUGIN_DIRS` from settings.
Tests: `claude plugin test ~/.agents/mods/workflow`; check: `claude plugin validate ~/.agents/mods/workflow`.

## Browser

agent-browser CLI, headed, viewport 1440×900.

- `ablogin` — once: opens the `auth-base` session on the shared FE port (and the baseline FE, if
  configured); you log in, press Enter, and the state is saved (encrypted with
  `AGENT_BROWSER_ENCRYPTION_KEY`).
- Every task uses its own session, `--session <slug>-<side>`, restored from that state, so tasks verify
  in parallel.
- A login screen means the state expired: agents never type credentials — they ask you to run
  `ablogin` and wait.
- Each step closes its own session (never `close --all`). Screenshots go to `<worktree>/.shots/`
  (kept out of git). With a baseline FE configured, `/pr` adds a pixel-diff column, and the QA reviewer
  runs an accessibility audit (WCAG A/AA, serious/critical) on UI routes.

## Rules (`rules/`)

What your linter can't see: `rules/<FE repo dir>.json`, `rules/<BE repo dir>.json`. `rules-guard.sh`
(PreToolUse on `Edit|Write|MultiEdit`, subagents included) checks only **added** occurrences — editing a
line that already broke a rule goes through.

- **block** → the edit is refused with the rule's message; **warn** → it goes through, the message
  reaches the model.
- Escape hatch: a `rule-ok: <id> <reason>` comment in the new text skips that rule for that edit.
- Hits go to `rules/hits.log`; hook errors to `rules/errors.log` (the hook then lets the edit through).
- `hooks/rules-check.sh <repo> [<range>]` runs the same rules over a diff's added lines;
  `--try <rule.json> <bad> <fix> [path]` tests a draft rule.
- Findings that repeat across tasks (codebase / light reviewers) land in `rules/findings-log.jsonl`;
  `/deep-review` step 3b then proposes a rule, or a line for the Conventions section of the worker
  contract. Nothing is added without your answer.
- A rule that misfires gets a better pattern or drops to warn; `rule-ok` is not a habit.
