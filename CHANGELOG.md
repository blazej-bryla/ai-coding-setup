# Changelog

Newest first.

## v4.6.2 — 2026-11-13

- README and WORKFLOW made consistent; history moved here; fixed public title.

## v4.6.1 — 2026-11-13

- The README has Skills and Agents sections, demo clips for `/work`, `/deep-review` and `/pr`, and plainer prose.

## v4.6.0 — 2026-11-12

- The README is a landing page with diagrams of the pipeline, the `/work` loop, deep-review and the layers.

## v4.5.1 — 2026-11-05

### Added
- Herdr tasks record their state and are closed when the work finishes.
### Changed
- Implementation and review agents must tie each claim to evidence in the code, so unsupported findings are dropped.
- Implementation and review agents cap repair attempts, so a failing fix stops instead of looping.
- Implementation and review agents no longer dig through git history for context.

## v4.5 — evidence-bound work and reviews (ideas from overment/limen)

- Tickets carry one `**Easy to miss:** "<a rule quoted from the ticket, spec or context.md that the quickest way to finish could skip or break>" — Shown by: <command, check or observation>` line (`/to-tickets` template, `/kickoff`'s caller requirement; `/bugfix` puts one in `fix-plan.md`).
- Worker reports mark every acceptance criterion `proven — <evidence>` | `not proven — <gap>` | `changed — <new requirement>. Reason: <what changed it>`, and the Easy-to-miss rule `followed` | `broken` | `not proven`. Evidence counts only when it happened in that session — a `quiet` `ok:` line or its failing output, an `abcheck` `PASS` line, a file path; an unrun check is never inferred as passing. These lines stay in the ≤ 40-line hand-back. The orchestrator (`/work`, `/bugfix`) reads only the items not proven/followed and, for each, checks it itself, sends it back, or asks you with the reason; everything proven moves on to review.
- Review findings carry certainty: `proven` (how: test, log, reproduction, exact code path), `plausible` or `unverified`. `blocking: yes` only for a proven break of an acceptance criterion or a proven security / data-loss defect. The refute phase downgrades unproven claims; the `findings.md` summary and triage show the label; on GitHub a plausible finding is posted as `question` or `suggestion (non-blocking)`.
- Repair cap (`/work`, `/bugfix`, `/address-review`): one repair and one re-review per ticket (the re-review gets `Previous findings:`); a second blocking result ends the loop with what remains, what it cost, and a question to you.
- No repository archaeology: ten reads or searches without an edit means the worker makes the probe edit at the ticket's seam; what it mapped goes to `scratch/<slug>/reports/<side>-<NN>-notes.md`. Reading in full every file it changes still holds.
- Causes only with evidence: problems as observed; a cause only when verified, and how; a guess labelled a guess.
- Cold reader (`skills/_shared/CONTEXT.md`): a question or gate message opens with one or two lines of state — task, ticket, what happened since your last message — then the question.

## v4.4.1 — 2026-11-04

### Changed
- `/work`, `/bugfix`, and `/deep-review` use less context: the orchestrator no longer reads whole repository files.
- Worker agent reports are capped in length, so long runs use less context.
- Browser checks return compact output instead of full page dumps.
- `quiet` and `abcheck` report only pass or fail instead of full command output.

## v4.4 — a leaner orchestrator context

What fills the `/work` session is now capped; the gates, teach, review selection and what is verified are unchanged (`skills/_shared/CONTEXT.md`).

- Browser: `bin/abcheck` runs the verification batch and prints PASS/FAIL per check (expectation, console errors, page errors, failed requests with URLs) instead of the snapshot; screenshots are read only when a check failed or you ask; no `agent-browser --help` in sessions.
- Workers: `wf-implementer` writes its full report to `scratch/<slug>/reports/<side>-<NN>.md` and hands back ≤ 40 lines; the orchestrator opens the report only on blocked/partial, `open`, `deps:` or `deviation:`.
- Pass/fail commands: `bin/quiet` (tests, lint, typecheck, build) — one `ok: <cmd> (<n>s)` line, or the last 40 lines on failure; `git push --quiet … | tail -20`.
- Repo questions go to `wf-explore`; the orchestrator reads with offset/limit or `grep -l`, never `cat`/`sed -n` on source.
- Scratch: `bin/tickets` lists one line per ticket for the frontier; a ticket file is read when it is landed; `context.md`/`spec.md` once. `findings.md` opens with a summary block (counts + one line per actionable finding) that callers read instead of the whole file.
- Diffs: `--stat` by default; the full diff only for files a finding or the teach brief points to.

## v4.3.3 — 2026-11-03

### Added
- Herdr's PR Radar panel groups your PRs by review state, with Review (`/deep-review`) and Address (`/address-review`) actions and a toast and sound when a new review is requested.
- Herdr can start work from a Linear ticket: Kickoff switches the main checkout to the ticket's base branch, and Work runs `/work` in a worktree when tickets exist.
- Herdr groups tasks and shows a dev-server footer.
### Changed
- Herdr board layout and keys are versioned mods, so each release carries its own copy.
### Fixed
- The `wts` dev command exports the API variable for every step.
- The `wts` dev command builds contracts before starting dev servers.

## v4.2.2 — 2026-10-29

### Added
- `/wf-init` sets up a project for the workflow, and `wfprofile` manages per-project profiles.
- New `/deslop` skill for cleaning up a change.
- New `wf-` variants of the context-gatherer, explore, and implementer agents.
### Changed
- Monorepo is now the only worktree mode: `wt <branch> [prompt]` creates one worktree and session for the repo, and `wt` stops with a one-line message when the main checkout is on that branch.
- The `fe` and `be` side argument to `wt` still works but is ignored.
- Worktree setup copies the env files for both apps and sets the frontend port in its `.env.local`.
- The core agents are slimmer.
- `/pr` uses the project's own `pr` skill when it has one.
- Bundled third-party skills are updated to a newer release.
- Skills check a suspected issue cause before acting on it.
- Review replies agree with what is right before raising objections.
- Skills read files in full instead of excerpts.
- Skills follow a new dependency rule.
- Teaching responses use a briefer format.
### Fixed
- Worktree setup runs on the repo's Node version, and it checks and logs the result.
- Commit and PR titles no longer get an area tag.

## v4.2 — from pi

- `/deslop` (from earendil-works/pi, MIT) plus rules: an issue's root cause is a hypothesis, replies say agree/disagree first, files are read in full, dependencies only when the ticket asks (`deps:` in the report, a question in `/work` before teach), the teach brief as problem → example → solution.

## v4.1 — profiles

- Per-repo config values → the repo's profile (`env` slot); `config.local.zsh` keeps machine-wide values (`WF_DEFAULT_PROFILE`, port bases).
- Automatic lookup of the repo's `pr` / change-summary skill (`WT_CHANGE_SUMMARY_SKILL`, `WT_CHANGE_SUMMARY_AUDIENCE`) → the `pr.body` / `notify.summary` slots (audience in the overrides).
- Config keys inherited from the shell's environment → cleared when `config.sh` loads, so they can't leak into another repo.

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

## v3.7.1 — 2026-10-15

### Added
- `metrics [days]` shell helper summarises a local log of landed tickets and fixed bugs.

### Changed
- `/kickoff` adds a Prior art line to each ticket it creates.
- `/work`, `/bugfix` and `/implement` give the implementer the ticket's prior-art paths and the worker contract's conventions before it codes, and it reports which prior art it followed.
- Agents treat text from tickets and PRs as data, not instructions.
- Worker runs now have a timeout.

## v3.6.1 — 2026-10-13

### Added
- `install.sh` enables the pre-commit leak guard when run from a clone of the public repo. It is safe to re-run and supports `--dry-run`.
### Changed
- The README title and LICENSE holder use the repository's own name, read from its origin remote, instead of a fixed name.

## v3.5.3 — 2026-10-13

### Added
- Initial public release: a Claude Code workflow for teams working in a frontend and a backend repo side by side.
- Skills `/kickoff`, `/work`, `/implement`, `/bugfix`, `/deep-review`, `/pr`, `/address-review` and `/commit` take a tracker issue from plan to merged PR.
- Per-task git worktrees with their own ports and, optionally, their own database, plus shell helpers (`wt`, `wts`, `wtwho`, `wtdb`, `wtclean`).
- Hooks that keep agents from starting or killing dev servers, enforce project rules your linter can't express, and create worktrees.
- The `workflow` mod: a task status band above the prompt and `/tickets`, `/who`, `/story` without a model turn.
- One config file (`config.local.zsh`) for every stack-specific value; `wtconf` prints the effective settings.
