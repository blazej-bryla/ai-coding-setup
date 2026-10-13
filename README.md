# agents — a Claude Code workflow for two-repo (FE + BE) teams

Skills, subagents, hooks and a small Claude Code mod that take a tracker issue from plan to merged PR:

```
/kickoff <issue>     plan: context.md → grilling → spec / tickets (both repos in one run)
/work                ticket loop: parallel implementer subagents in their own worktrees,
                     then review → teach → squash-merge → commit, one ticket at a time
/implement           one ticket in this session
/bugfix <issue>      quick path for obvious bugs, full root-cause path otherwise
/deep-review         review sized by a risk classifier; parallel specialists + a refute phase
/pr                  PR via the project's own PR skill, with before/after screenshots
/address-review      unresolved PR threads, one by one
/commit              one clean commit, terse message
```

It assumes a frontend repo and a backend repo worked on side by side, Linear as the tracker,
GitHub for PRs and [agent-browser](https://github.com/vercel-labs/agent-browser) for UI checks.
Everything specific to your stack — repo paths, dev and setup commands, ports, the database, tracker
labels — is configuration (see [Configure](#configure)). `WORKFLOW.md` is the one-page tour.

## Layout

| Path | What |
|---|---|
| `skills/` | the slash commands above (`SKILL.md` each; `deep-review/prompts/` are the reviewer prompts) |
| `agents/` | subagents: `implementer`, `planner`, `Explore`, `context-gatherer`, `reviewer-*` |
| `hooks/` | `worktree-create.sh` (per-task worktrees, ports, per-worktree DB via `lib/db.sh`), `rules-guard.sh` + `rules-engine.jq` + `rules-check.sh` (project rules your linter can't express), `bash-guard.sh` (agents never start/kill dev servers or run watch-mode tests), `rtk-guard.sh`, `pr-created.sh`, `notify.sh`; `lib/config.sh` = every setting with its default |
| `rules/my-frontend.json` | example rules file for the rules engine |
| `mods/workflow/` | Claude Code mod: task status band above the prompt, `/tickets` `/who` `/story` without a model turn |
| `shell/worktrees.zsh` | `wt`, `wts`, `wtwho`, `wtrm`, `wtclean`, `wtdb`, `ablogin`, `friction` |
| `bin/` | `wtconf` (prints the effective config), `pr-diagram-check`, `settings-sync` |
| `config.example.zsh` | template for your `config.local.zsh` |

## Requirements

- Claude Code (recent; the mod needs `CLAUDE_CODE_PLUGIN_DIRS` support), macOS (`osascript`, BSD `sed -i ''`)
- `jq`, `perl`, `git`, `zsh`; `gh` ≥ 2.99 (`--attach`) for `/pr`
- Linear MCP server (`linear`) for `/kickoff`, `/bugfix` and story mode
- [agent-browser](https://github.com/vercel-labs/agent-browser) CLI for UI verification and screenshots
- optional: Docker with the backend's Postgres for per-worktree databases
- optional: [rtk](https://github.com/rtk-ai/rtk) (only `hooks/rtk-guard.sh` uses it — drop that hook if you don't use rtk)
- optional: `python3` with `playwright` for `/pr` diagrams

## Install

Skills and hooks refer to `~/.agents/…`, so clone the repo there (or let `install.sh` link `~/.agents` to your clone):

```sh
git clone https://github.com/<you>/agents-public ~/.agents
~/.agents/install.sh            # links skills/* and agents/*.md into ~/.claude; safe to re-run
~/.agents/install.sh --dry-run  # show what it would do
```

### settings.json

Merge into `~/.claude/settings.json`:

```json
{
  "env": { "CLAUDE_CODE_PLUGIN_DIRS": "~/.agents/mods/workflow" },
  "permissions": { "allow": ["Bash(~/.agents/bin/wtconf:*)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "$HOME/.agents/hooks/rtk-guard.sh" },
        { "type": "command", "command": "$HOME/.agents/hooks/bash-guard.sh" } ] },
      { "matcher": "Edit|Write|MultiEdit", "hooks": [
        { "type": "command", "command": "$HOME/.agents/hooks/rules-guard.sh" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.agents/hooks/pr-created.sh" } ] }
    ],
    "WorktreeCreate": [
      { "hooks": [ { "type": "command", "command": "$HOME/.agents/hooks/worktree-create.sh" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "$HOME/.agents/hooks/notify.sh" } ] }
    ]
  }
}
```

`bin/settings-sync` merges a repo-kept settings file (`~/.agents/settings.v3.1.json`, not included —
create your own) with the live one; skip it if you edit `~/.claude/settings.json` directly.

## Configure

```sh
cp ~/.agents/config.example.zsh ~/.agents/config.local.zsh   # then edit
echo 'source ~/.agents/shell/worktrees.zsh' >> ~/.zshrc
~/.agents/bin/wtconf                                         # check what the hooks and skills will see
```

`config.local.zsh` holds your real values: repo paths, the deployed API and base-branch FE, the
remote-API port, dev and setup commands, the patterns `bash-guard` uses to spot server starts and
watch-mode tests, the per-worktree database (container, prefix, migrate command — or off), what your
SSO login screen looks like, tracker labels and statuses, and your project's PR skill. Every key and
its default is documented in `config.example.zsh` and `hooks/lib/config.sh`. The hooks, the shell
helpers and the mod read the file directly; skills read it through `wtconf`. Don't commit it to a
public repo — the leak guard refuses a `config.local.zsh`.

Rules files are named after the repo directories: `rules/<basename of FE_REPO>.json` and
`rules/<basename of BE_REPO>.json` (the example matches the default `my-frontend`).

Per-project knowledge that isn't a single value — test commands, conventions the codebase reviewer
enforces, which directories count as modules for `/pr` diagrams — goes in a worker contract,
`~/.agents/projects/<repo>.md`, pulled into each worktree through the repo's gitignored
`CLAUDE.local.md` (`@~/.agents/projects/<repo>.md`). Write your own; none are published.

## Third-party pieces (install them yourself)

The workflow calls these but does not ship them:

- **Matt Pocock's skills** — `/kickoff` and friends load `grilling`, `domain-modeling`, `to-spec`,
  `to-tickets`, `handoff` (plus `grill-with-docs`, `writing-great-skills`) from
  [mattpocock/skills](https://github.com/mattpocock/skills):

  ```sh
  npx skills add mattpocock/skills    # pick the seven above; install into ~/.agents/skills
  ```

  then link them into `~/.claude/skills/` (re-run `./install.sh`).
- **diagram-design** — optional diagrams in `/pr` ([cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design)).
  In Claude Code: `/plugin marketplace add cathrynlavery/diagram-design`, then
  `/plugin install diagram-design@diagram-design`; PNG export needs `pip install playwright && playwright install chromium`.
  `bin/pr-diagram-check` tells `/pr` whether it is available; without it `/pr` simply skips the diagram.
- Your projects' own PR and change-summary skills (optional; `/pr` has a built-in fallback).

## Leak guard

The repo is generated from a private one. `.githooks/pre-commit` (enable with
`git config core.hooksPath .githooks`) and the `leak-guard` GitHub Actions workflow scan for home
paths, emails, tokens and a committed `config.local.zsh` (`scripts/public-denylist.txt`) and run
gitleaks. Keep secrets in your environment, never in this repo.

## License

See [LICENSE](LICENSE).
