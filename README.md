# ai-coding-setup — a Claude Code workflow for FE + BE monorepo teams

Skills, subagents and hooks that take a tracker issue from plan to merged PR:

```
/kickoff <issue>     plan: context.md → grilling → tickets (FE + BE in one run)
/work [<ticket.md>]  the task's ticket loop (FE + BE, one frontier): parallel implementers in their own worktrees,
                     then review → teach → squash-merge → commit, one ticket at a time; a ticket file = that ticket only
/bugfix <issue>      quick path for obvious bugs, full root-cause path otherwise
/deep-review         review sized by a risk classifier; parallel specialists + a refute phase
/pr                  PR body in the repo's own `pr` skill sections, with screenshots
/deslop              simplify the branch's changes before /pr (optional)
/address-review      unresolved PR threads, one by one
/commit              one clean commit, terse message
/wf-init             map a repo's own skills onto the workflow's steps (a per-repo profile)
```

It assumes a monorepo with a frontend app and a backend app (one worktree and one session per task), Linear as the tracker,
GitHub for PRs and [agent-browser](https://github.com/vercel-labs/agent-browser) for UI checks.
Everything specific to your stack — repo paths, dev and setup commands, ports, the database, tracker
labels — is configuration (see [Configure](#configure)). Which steps a repo's own skills take over
(planning, implementing, tests, review, PR body, change summary, conventions) is its profile, written by
`/wf-init` (see [Profiles](#profiles)). `WORKFLOW.md` is the one-page tour.

**Monorepo mode only.** Since v3.8 the workflow expects one repo holding both apps (one worktree and one
session per task). For a two-repo setup (separate FE and BE repositories), use release **v3.7.1**.

## Layout

| Path | What |
|---|---|
| `skills/` | the slash commands above (`SKILL.md` each; `deep-review/prompts/` are the reviewer prompts) |
| `skills/_shared/` | text several skills read: `TEACH.md` (the teach round), `IDENTITY.md` (slug, side, base) |
| `agents/` | subagents, namespaced so a repo's own `.claude/agents/` never shadows them: `wf-implementer`, `wf-explore`, `wf-context-gatherer`, `wf-reviewer-*` |
| `hooks/` | `worktree-create.sh` (per-task worktrees, ports, per-worktree DB via `lib/db.sh`), `bash-guard.sh` (agents never start/kill dev servers or run watch-mode tests), `rtk-guard.sh`, `pr-created.sh`; `lib/config.sh` = every setting with its default |
| `shell/worktrees.zsh` | `wt`, `wts`, `wtwho`, `wtrm`, `wtclean`, `wtdb`, `ablogin`, `friction` |
| `bin/` | `wtconf` (prints the effective config; `--ports` a worktree's ports), `wfprofile` (reads a repo's profile), `pr-diagram-check`, `settings-sync`, `quiet` (pass/fail commands: one `ok:` line or the last 40 lines), `abcheck` (one browser check, a compact PASS/FAIL summary), `tickets` (one line per ticket) |
| `config.example.zsh` | template for your `config.local.zsh` |

## Requirements

- Claude Code (recent), macOS (BSD `sed -i ''`)
- `jq`, `perl`, `git`, `zsh`; `gh` ≥ 2.99 (`--attach`) for `/pr`
- Linear MCP server (`linear`) for `/kickoff`, `/bugfix` and story mode
- [agent-browser](https://github.com/vercel-labs/agent-browser) CLI for UI verification and screenshots
- optional: Docker with the backend's Postgres for per-worktree databases
- optional: [rtk](https://github.com/rtk-ai/rtk) (only `hooks/rtk-guard.sh` uses it — drop that hook if you don't use rtk)
- optional: `python3` with `playwright` for `/pr` diagrams

## Install

Skills and hooks refer to `~/.agents/…`, so clone the repo there (or let `install.sh` link `~/.agents` to your clone):

```sh
git clone <URL of this repo> ~/.agents
~/.agents/install.sh            # links skills/* and agents/*.md into ~/.claude; safe to re-run
~/.agents/install.sh --dry-run  # show what it would do
```

### settings.json

Merge into `~/.claude/settings.json`:

```json
{
  "permissions": { "allow": ["Bash(~/.agents/bin/wtconf:*)", "Bash(~/.agents/bin/quiet:*)", "Bash(~/.agents/bin/abcheck:*)", "Bash(~/.agents/bin/tickets:*)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
        { "type": "command", "command": "$HOME/.agents/hooks/rtk-guard.sh" },
        { "type": "command", "command": "$HOME/.agents/hooks/bash-guard.sh" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.agents/hooks/pr-created.sh" } ] }
    ],
    "WorktreeCreate": [
      { "hooks": [ { "type": "command", "command": "$HOME/.agents/hooks/worktree-create.sh" } ] }
    ]
  }
}
```

`bin/settings-sync` merges a repo-kept settings file (`~/.agents/settings.v3.1.json`, not included —
create your own) with the live one; a key set to `null` there is deleted. Skip it if you edit
`~/.claude/settings.json` directly.

## Configure

```sh
cp ~/.agents/config.example.zsh ~/.agents/config.local.zsh   # then edit
echo 'source ~/.agents/shell/worktrees.zsh' >> ~/.zshrc
~/.agents/bin/wtconf                                         # check what the hooks and skills will see
```

`config.local.zsh` holds your real values: repo paths, the deployed API and base-branch FE, the
remote-API port, dev and setup commands, the patterns `bash-guard` uses to spot server starts and
watch-mode tests, the per-worktree database (container, prefix, migrate command — or off), what your
SSO login screen looks like, tracker labels and statuses. Every key and
its default is documented in `config.example.zsh` and `hooks/lib/config.sh`. The hooks and the shell
helpers read the file directly; skills read it through `wtconf`. Don't commit it to a
public repo — the leak guard refuses a `config.local.zsh`.

Per-project knowledge that isn't a single value — test commands, conventions the implementer follows and
the codebase reviewer enforces (what your linter can't see, one line each), which directories count as modules for `/pr` diagrams — goes in a worker contract,
`~/.agents/projects/<repo>.md` (<repo> = the monorepo's directory name; one Conventions section per app),
pulled into each worktree through the repo's `CLAUDE.local.md` (`@~/.agents/projects/<repo>.md`; the
worktree hook copies it and keeps it out of git via `.git/info/exclude`). Write your own; none are published.

## Profiles

A profile, `~/.agents/profiles/<id>.json` (id = the repo's origin URL, so every clone and worktree finds it),
says per step ("slot") whose text runs it: `plan.grill`, `plan.tickets`, `build.implement`, `build.tdd`,
`review`, `pr.body`, `pr.create`, `notify.summary`, `conventions`, `env`. Each slot is `mine`, `none`,
`project:<path>` (a skill in the repo) or `mine+project:<path>`, with `overrides` — plain text the workflow
states to the project skill (e.g. "seams are pre-agreed in the ticket — don't ask", "commit only as `wip:`")
— and a sha256 fingerprint of every project file it relies on, read from one git ref (e.g. the default
branch). `env` holds the repo's config values. Run `/wf-init` in a repo to write one: it discovers the repo's
skills, agents and conventions, flags project skills that would break the workflow's gates (asking a user
from a background worker, pushing, committing without the teach round), asks per slot, writes the profile and
dry-runs `/work` and `/pr` against it. No profile → every slot is the workflow's own, with a one-line hint. A
fingerprinted file that changed or vanished stops the next run with the file named; re-running `/wf-init`
then shows only that difference.

## Third-party pieces (install them yourself)

The workflow calls these but does not ship them:

- **Matt Pocock's skills** — `/kickoff` loads `grilling`, `domain-modeling` and `to-tickets` from
  [mattpocock/skills](https://github.com/mattpocock/skills) v1.3.1:

  ```sh
  npx skills@1.7.0 add https://github.com/mattpocock/skills/tree/v1.3.1 -g -s grilling -s domain-modeling -s to-tickets -a claude-code
  ```

  then move them into `~/.agents/skills/` and link them into `~/.claude/skills/` (re-run `./install.sh`).
  `/kickoff` asks `to-tickets` for extra ticket fields (Repo, Touches, Verify by, Prior art) as a caller requirement.
- **diagram-design** — optional diagrams in `/pr` ([cathrynlavery/diagram-design](https://github.com/cathrynlavery/diagram-design)).
  In Claude Code: `/plugin marketplace add cathrynlavery/diagram-design`, then
  `/plugin install diagram-design@diagram-design`; PNG export needs `pip install playwright && playwright install chromium`.
  `bin/pr-diagram-check` tells `/pr` whether it is available; without it `/pr` simply skips the diagram.
- Your repo's own skills (optional) — mapped per step by `/wf-init`; without a profile the workflow uses its own.

## Leak guard

The repo is generated from a private one. `.githooks/pre-commit` (enable with
`git config core.hooksPath .githooks`) and the `leak-guard` GitHub Actions workflow scan for home
paths, emails, tokens and a committed `config.local.zsh` (`scripts/public-denylist.txt`) and run
gitleaks. Keep secrets in your environment, never in this repo.

## Credits

- `/deslop` and a few rules (issue-cause skepticism, agree-first replies, read-in-full, the dependency rule, the teach brief format) are adapted from [earendil-works/pi](https://github.com/earendil-works/pi) (MIT, © 2025 Mario Zechner).

## License

See [LICENSE](LICENSE).
