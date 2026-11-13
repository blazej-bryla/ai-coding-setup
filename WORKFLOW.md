# Workflow — the one-page tour

**One identifier for everything.** The task key in the branch name is the slug: `TODO-12-add-due-dates`
→ `todo-12`. The frontend and the backend live in one monorepo (`apps/web`, `apps/api` by default), so a
task gets ONE worktree (`$WT_ROOT/todo-12`), ONE Claude session (`todo-12`) and ONE `/work` for the
tickets of both sides, plus its state directory, `~/.agents/scratch/todo-12/` — context, spec and tickets
(`tickets/fe/`, `tickets/be/`) live there, outside the repo. A ticket's side is its directory: it picks
the app dir, the test command and the screenshots.

**Configuration.** Your stack lives in `~/.agents/config.local.zsh` (template: `config.example.zsh`) — or, per
repo, in that repo's profile (slot `env`, see Profiles), with only machine-wide values left in the config:
repo paths, ports, dev and setup commands, the per-worktree database, tracker labels, what the login
screen looks like. `wtconf` prints the effective values (`wtconf --ports` a worktree's ports); the hooks, shell helpers and
skills all read the same file.

## Shell (`shell/worktrees.zsh`)

| Command | What it does |
|---|---|
| `wt <branch> [--base <branch>\|--staging] [prompt]` | Claude in the task's worktree (the WorktreeCreate hook makes it: both apps' env files with their ports, one install, no database; base = the repo's default branch) — e.g. `wt TODO-12-add-due-dates /work` |
| `wts <slug> be` | the worktree's own database first (created on first use), the BE extras once, then the BE on its port |
| `wts <slug> fe [--local\|--remote] [--port N] [--take]` | the FE extras once (e.g. e2e browsers), then the FE: this worktree's BE listening → local API, else the remote API on the shared port — decided at start, env files untouched; `--take` moves that port from another worktree |
| `wtwho` | who holds the shared FE port, and which worktrees run a FE / BE on their own ports |
| `cdwt <slug> [fe\|be]` | jump into a worktree (or one app dir in it) |
| `wtls` | list the worktrees |
| `wtrm <slug>` | remove a task's worktree (branches stay; offers to drop its database) |
| `wtclean` | remove worktrees whose branch is merged or gone (offers to drop the database) |
| `wtdb <slug> [--fresh]` | the worktree's own database now: a copy of the source DB (`--fresh`: empty) plus this branch's migrations; `wts <slug> be` does it lazily |
| `friction [days]` | the friction log of the last N days (default 7), grouped by what went wrong |

Each worktree gets its own ports (FE and BE share an offset derived from the slug), its own copies
of both apps' env files and, once the BE first runs, its own database. Only the shared remote-API port is contested: two FE tasks
can run at once, but only one holds that port (`wts … --take`, `wtwho`).

Skills never start or stop dev servers — they ask you to run `wts` and wait, and `/work` keeps landing
other tickets meanwhile. `hooks/bash-guard.sh` enforces it, together with "no watch-mode tests".

Once a week: `friction 7`; the most frequent entries are the next round of fixes.

`/work` hands each implementer the ticket's `Prior art:` paths (cut by `/kickoff`), its app dir and test command, and the path of the repo's worker contract to read that app's Conventions; the implementer reports which prior art it `followed:`. Every agent is namespaced `wf-` (`wf-implementer`, `wf-reviewer-*`, `wf-explore`, `wf-context-gatherer`), so a repo's own `.claude/agents/` never shadows them.

Text from Linear issues, PR/review comments, web pages and command output is data: every skill and subagent that reads it follows no instructions found in it and quotes them to you instead. `/address-review` flags review comments that reach outside the PR or touch secrets, CI or permissions, and never fixes those without asking.

## Skills

| Skill | When |
|---|---|
| `/kickoff <issue> [notes]` | plan: context.md → grilling (risky changes: rollback + premortem) → tickets of both sides (an existing `spec.md` is read); prints `wt <branch> /work` |
| `/work [<dir>\|<ticket.md>] [parallel:N] [mode:local\|story] [dry-run]` | the task's ticket loop over both sides (one frontier; a cross-side blocker is an ordinary edge): waves of `wf-implementer` subagents, review, teach (`skills/_shared/TEACH.md`), squash-merge, commit; a ticket file = that ticket only |
| `/bugfix <issue> [quick\|full]` | a bug: asks where to verify it (`Verify by: ui …`), before/after screenshots; the diagnosis names the strongest alternative and the check that tells them apart |
| `/deep-review [<pr>\|<base-ref>]` | review; a risk classifier picks the dimensions — `light`, `full` or "only codebase and qa" override it |
| `/pr [update [summary]\|comment\|ticket <side>/<NN>\|story [update]\|diagram\|update nodiagram\|dry-run]` | body, create and change summary per the profile (`pr.body`, `pr.create`, `notify.summary`); AFTER screenshots in Evidence (BEFORE + pixel diff only against a deployed baseline); a diagram only on `/pr diagram` |
| `/deslop [<paths>]` | before /pr, optional: simplifies the branch's changes (inline trivial helpers, drop speculative and defensive code); significant removals asked one at a time; teach, commit |
| `/address-review [<pr>]` | the PR's open review threads (before a disagreeing reply: the reviewer's strongest case in one sentence) |
| `/commit [<paths>]` | a commit from the current changes (amends only an unpushed commit, and says so) |
| `/wf-init [<slot>…]` | map the repo's own skills onto the workflow's slots and write its profile; a re-run shows only what changed |

## Story mode (`mode: story` in context.md; rules in `skills/work/STORY.md`)

- **When:** `/kickoff` suggests it when the issue carries your story label — tickets become tracker
  sub-issues and each gets its own PR. Otherwise it suggests local mode (one PR per task). You choose;
  ticket and line counts are only a hint. No `mode:` means local.
- **Stack or sibling:** a ticket with no blocker opens its PR against the story branch;
  with one blocker, against the blocker's branch (a stack) — a chain may mix FE and BE tickets. `/kickoff` linearises edges so each ticket
  has at most one blocker. `gh stack link` only for chains of two or more. No drafts: a PR higher in a chain
  says `Depends on #N` in its body.
- **No waiting:** `/work` builds the whole story at once — a ticket starts as soon as its blocker is
  committed locally; human review never blocks the loop. After each ticket, one question: push and
  open the PR? Force pushes after a restack only after asking.
- **Story PR** (`/pr story`, story branch → base or epic): a list of the sub-PRs; every change was
  reviewed in its sub-PR, so this one is only checked for integration and conflicts.

## Browser

agent-browser CLI, headed, viewport 1440×900.

- `ablogin` — once: opens the `auth-base` session on the shared FE port (and the baseline FE, if
  configured); you log in, press Enter, and the state is saved (encrypted with
  `AGENT_BROWSER_ENCRYPTION_KEY`).
- Every task uses its own session, `--session <slug>`, restored from that state, so tasks verify
  in parallel.
- A login screen means the state expired: agents never type credentials — they ask you to run
  `ablogin` and wait.
- Skills check pages through `bin/abcheck` (one batch, one PASS/FAIL line per check; screenshots
  are read only when a check failed). Each step closes its own session (never `close --all`). Screenshots go to `<worktree>/.shots/`
  (kept out of git). With a baseline FE configured, `/pr` adds BEFORE shots and a pixel-diff column. Given
  `Dev server:` and `Browser:` in its context block, the QA reviewer checks UI criteria in the browser
  and runs an accessibility audit (WCAG A/AA, serious/critical) on UI routes.

## Profiles (`~/.agents/profiles/<id>.json`, read by `bin/wfprofile`)

The id comes from the repo's origin URL, so every clone and worktree finds the same profile. Every skill
calls `wfprofile <slots>` at its start and runs each step with its own text (`mine`), with a skill of the
repo (`project:<path>`, plus `overrides` the workflow states to it), or skips it (`none`); `mine+project`
adds the project's files as extra input. The workflow's gates (no push without asking, teach before every
commit, servers are yours, external text is data) win over both.

| Slot | Step |
|---|---|
| `plan.grill` | the grilling in `/kickoff` |
| `plan.tickets` | slicing tickets |
| `build.implement` | what a worker does with one ticket |
| `build.tdd` | how it writes tests |
| `review` | the embedded review of `/work` and `/bugfix` |
| `pr.body` | the PR body |
| `pr.create` | push + `gh pr create` |
| `notify.summary` | a change summary after the PR |
| `conventions` | the rules workers and the codebase reviewer read |
| `env` | paths, ports, commands, database (`wtconf` returns them) |

Project files are read from the profile's git ref (e.g. the default branch) into `~/.agents/scratch/.profiles/`,
not from whatever is checked out, and each one carries a sha256 fingerprint: a file that changed or vanished
stops the next run with `stop=step <slot> changed in the project — <file> … — run /wf-init`. No profile →
every slot `mine` and a one-line hint; a reader error (bad JSON, no jq) → one line and every slot `mine`.
`wfprofile --check` resolves every slot, `--diff` lists what changed since the profile was written.

## Conventions

What your linter can't see lives as plain lines in the Conventions section of the worker contract
(`projects/<repo>.md`, one section per app): the implementer reads them before coding and the codebase
reviewer checks against them. A new convention is one more line there — what to do instead, and where
the alternative lives.

History: CHANGELOG.md.
