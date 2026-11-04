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
| `wt <branch> [--base <branch>\|--staging] [prompt]` | Claude in the task's worktree (the WorktreeCreate hook makes it: both apps' env files with their ports, one install, no database; base = the repo's default branch) — e.g. `wt TODO-12-add-due-dates /work`. `wt <branch> fe\|be` still works; the side is ignored |
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
| `/kickoff <issue>` | plan: context.md → grilling (risky changes: rollback + premortem) → tickets of both sides (an existing `spec.md` is read); prints `wt <branch> /work` |
| `/work [<dir>\|<ticket.md>] [dry-run]` | the task's ticket loop over both sides (one frontier; a cross-side blocker is an ordinary edge): waves of `wf-implementer` subagents, review, teach (`skills/_shared/TEACH.md`), squash-merge, commit; a ticket file = that ticket only |
| `/bugfix <issue>` | a bug: asks where to verify it (`Verify by: ui …`), before/after screenshots; the diagnosis names the strongest alternative and the check that tells them apart |
| `/deep-review` | review; a risk classifier picks the dimensions — `light`, `full` or "only codebase and qa" override it |
| `/pr [dry-run]` | body, create and change summary per the profile (`pr.body`, `pr.create`, `notify.summary`); AFTER screenshots in Evidence (BEFORE + pixel diff only against a deployed baseline); a diagram only on `/pr diagram` |
| `/deslop` | before /pr, optional: simplifies the branch's changes (inline trivial helpers, drop speculative and defensive code); significant removals asked one at a time; teach, commit |
| `/address-review` | the PR's open review threads (before a disagreeing reply: the reviewer's strongest case in one sentence) |
| `/commit` | a commit from the current changes (amends only an unpushed commit, and says so) |
| `/wf-init` | map the repo's own skills onto the workflow's slots and write its profile; a re-run shows only what changed |

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

## v4 — what went, and what replaces it

- The rules engine (`rules-guard.sh`, `rules-engine.jq`, `rules-check.sh`, `rules/*.json`, `hits.log`, `findings-log`, deep-review step 3b, `rule-ok`) → one Conventions line per rule.
- Metrics (`metrics.log`, `Spawned:`/`Runs:`, `metrics`, the Metrics line of `/work`) → none; `friction` stays.
- The worker timer (`WT_WORKER_TIMEOUT_MIN`) → none; a worker's return is the only event.
- The `mods/workflow` mod (`CLAUDE_CODE_PLUGIN_DIRS`, `/tickets` `/who` `/story`) → `wtwho` and the ticket files.
- The `notify.sh` Notification hook → none.
- `/implement` → `/work <ticket.md>`; teach in `skills/_shared/TEACH.md`, identity and side in `skills/_shared/IDENTITY.md`.
- The cross-session protocol (`WAITING`/`DONE`/`DEVIATION`, parking, `after:`, `ListAgents`/`SendMessage`) → none; another task's work comes first, or becomes the base (`wt <branch> --base <its branch>`).
- `/handoff`, `/to-spec`, `/grill-with-docs`, `writing-great-skills` → `/clear` and resume from the files; an existing `spec.md` is still read.
- The `planner` agent → none.
- Unprefixed agents (`implementer`, `reviewer-*`, `context-gatherer`, `Explore`) → `wf-*`; `wf-context-gatherer` reads Linear, GitHub and the planning files it is given (no atlassian).
- `/pr` through `/create-pr` or `pull_request_template` (`WT_PR_SKILL`, `WT_PR_TEMPLATE`), sequential BEFORE/AFTER shots on the shared port, drafts → the repo's `pr` skill, AFTER always, BEFORE + diff from a baseline, `Depends on #N`.
- E2E browser install in the WorktreeCreate hook → the first `wts <slug> fe`.
- grilling, domain-modeling, to-tickets → mattpocock/skills v1.3.1.

## v4.1 — profiles

- Per-repo config values → the repo's profile (`env` slot); `config.local.zsh` keeps machine-wide values (`WF_DEFAULT_PROFILE`, port bases).
- Automatic lookup of the repo's `pr` / change-summary skill (`WT_CHANGE_SUMMARY_SKILL`, `WT_CHANGE_SUMMARY_AUDIENCE`) → the `pr.body` / `notify.summary` slots (audience in the overrides).
- Config keys inherited from the shell's environment → cleared when `config.sh` loads, so they can't leak into another repo.

## v4.2 — from pi

- `/deslop` (from earendil-works/pi, MIT) plus rules: an issue's root cause is a hypothesis, replies say agree/disagree first, files are read in full, dependencies only when the ticket asks (`deps:` in the report, a question in `/work` before teach), the teach brief as problem → example → solution.

## v4.4 — a leaner orchestrator context

What fills the `/work` session is now capped; the gates, teach, review selection and what is verified are unchanged (`skills/_shared/CONTEXT.md`).

- Browser: `bin/abcheck` runs the verification batch and prints PASS/FAIL per check (expectation, console errors, page errors, failed requests with URLs) instead of the snapshot; screenshots are read only when a check failed or you ask; no `agent-browser --help` in sessions.
- Workers: `wf-implementer` writes its full report to `scratch/<slug>/reports/<side>-<NN>.md` and hands back ≤ 40 lines; the orchestrator opens the report only on blocked/partial, `open`, `deps:` or `deviation:`.
- Pass/fail commands: `bin/quiet` (tests, lint, typecheck, build) — one `ok: <cmd> (<n>s)` line, or the last 40 lines on failure; `git push --quiet … | tail -20`.
- Repo questions go to `wf-explore`; the orchestrator reads with offset/limit or `grep -l`, never `cat`/`sed -n` on source.
- Scratch: `bin/tickets` lists one line per ticket for the frontier; a ticket file is read when it is landed; `context.md`/`spec.md` once. `findings.md` opens with a summary block (counts + one line per actionable finding) that callers read instead of the whole file.
- Diffs: `--stat` by default; the full diff only for files a finding or the teach brief points to.
