# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow the maintainer's releases.

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
