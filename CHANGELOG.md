# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow the maintainer's releases.

## [4.5.1] - 2026-11-05

### Added
- Herdr tasks record their state and are closed when the work finishes.
### Changed
- Implementation and review agents must tie each claim to evidence in the code, so unsupported findings are dropped.
- Implementation and review agents cap repair attempts, so a failing fix stops instead of looping.
- Implementation and review agents no longer dig through git history for context.

## [4.4.1] - 2026-11-04

### Changed
- `/work`, `/bugfix`, and `/deep-review` use less context: the orchestrator no longer reads whole repository files.
- Worker agent reports are capped in length, so long runs use less context.
- Browser checks return compact output instead of full page dumps.
- `quiet` and `abcheck` report only pass or fail instead of full command output.

## [4.3.3] - 2026-11-03

### Added
- Herdr's PR Radar panel groups your PRs by review state, with Review (`/deep-review`) and Address (`/address-review`) actions and a toast and sound when a new review is requested.
- Herdr can start work from a Linear ticket: Kickoff switches the main checkout to the ticket's base branch, and Work runs `/work` in a worktree when tickets exist.
- Herdr groups tasks and shows a dev-server footer.
### Changed
- Herdr board layout and keys are versioned mods, so each release carries its own copy.
### Fixed
- The `wts` dev command exports the API variable for every step.
- The `wts` dev command builds contracts before starting dev servers.

## [4.2.2] - 2026-10-29

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

## [3.7.1] - 2026-10-15

### Added
- `metrics [days]` shell helper summarises a local log of landed tickets and fixed bugs.

### Changed
- `/kickoff` adds a Prior art line to each ticket it creates.
- `/work`, `/bugfix` and `/implement` give the implementer the ticket's prior-art paths and the worker contract's conventions before it codes, and it reports which prior art it followed.
- Agents treat text from tickets and PRs as data, not instructions.
- Worker runs now have a timeout.

## [3.6.1] - 2026-10-13

### Added
- `install.sh` enables the pre-commit leak guard when run from a clone of the public repo. It is safe to re-run and supports `--dry-run`.
### Changed
- The README title and LICENSE holder use the repository's own name, read from its origin remote, instead of a fixed name.

## [3.5.3] - 2026-10-13

### Added
- Initial public release: a Claude Code workflow for teams working in a frontend and a backend repo side by side.
- Skills `/kickoff`, `/work`, `/implement`, `/bugfix`, `/deep-review`, `/pr`, `/address-review` and `/commit` take a tracker issue from plan to merged PR.
- Per-task git worktrees with their own ports and, optionally, their own database, plus shell helpers (`wt`, `wts`, `wtwho`, `wtdb`, `wtclean`).
- Hooks that keep agents from starting or killing dev servers, enforce project rules your linter can't express, and create worktrees.
- The `workflow` mod: a task status band above the prompt and `/tickets`, `/who`, `/story` without a model turn.
- One config file (`config.local.zsh`) for every stack-specific value; `wtconf` prints the effective settings.
