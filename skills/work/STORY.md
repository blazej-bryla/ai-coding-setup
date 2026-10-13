# Story mode — the single place its rules live

`context.md` frontmatter `mode: story` (or `/work mode:story`). Missing `mode:` = `local` = today's flow, untouched: squash into the task branch, no Linear calls, no push. Everything in /work before landing — wave planning, spawn, review, verify, teach — is shared; this file says only what story mode does differently. Goal: no PR anyone reviews is huge. Stacks are a tool for that, not a goal.

## 1. When it applies

`/kickoff` recommends story when the Linear issue carries the configured story label (`story=` in `~/.agents/bin/wtconf -v WT_TRACKER_LABELS`); then its sub-tickets are published as Linear sub-issues. Without the label it recommends local, and the user picks local files or Linear — under their control; ticket count and rough changed lines per repo are shown as a hint only. Tickets on Linear ⇔ `mode: story` (one PR per ticket needs each sub-issue's `branchName`); the user can still choose `local` for one PR. The story label wins over the parent-based subtask/regular classification.

## 2. Branches and topology

- **Story branch** = `branch:` in context.md (the story issue's `branchName`), the same name in both repos. **Story base** = `base:` in context.md: the configured base branch (`WT_BASE_BRANCH`), or the epic's branch when the story has an epic parent — the configured `WT_EPIC_BRANCH` pattern with `{KEY}` = the epic's issue key, when set and that branch exists on origin, else the epic's `branchName`; neither on origin → ask, never create it. `wt` creates the story branch from `origin/<base>` (the hook); `/work` pushes it once per repo at the start when origin lacks it (the push goes through the user's `ask`); already on origin → fetch only. The orchestrator session runs in the story branch's worktree (`wt <story branch> <side> [--base <epic>] /work`).
- **Linearised edges** (cut by /kickoff): every ticket has at most ONE same-repo blocker. A ticket T with several → keep B = the deepest of them (most same-repo ancestors; tie → the higher number); for each other blocker X that is not already an ancestor of B, take A = the highest ancestor of B (B included) that is not also an ancestor of X, and re-point A's single blocker to X; repeat until every blocker of T is B or an ancestor of B, then T keeps only B. No new work is invented: only the order is serialised, and every original dependency still holds transitively. Cross-repo edges (`be/02`) don't count and never become a base — FE never stacks on a BE branch.
- **Base per ticket** (`**Base:**` in the ticket file): no same-repo blocker → `story` (sibling: its own PR on the story branch, no stack); one blocker → that ticket's `NN` (stacked: base = the blocker's `**Branch:**`).
- **Chains** = maximal paths along `Base: NN` edges. At a fork (01→02 and 01→03→04) the lowest-numbered child continues the chain; each other child starts its own chain whose bottom base is the parent's branch. `gh stack link` only for chains of length ≥2; a lone ticket (sibling or fork child without children) is a plain PR.

## 3. Ticket file — the state, written before every next action

/kickoff writes these under `**Repo:**`; /work and /pr update them; re-running /work resumes from them:

```
**Linear:** TODO-1234
**Branch:** <Linear gitBranchName>
**Base:** story | <NN>
**Base tip:** — | <sha of the base when the ticket was built>
**PR:** — | <url>
**PR status:** — | draft | ready | approved | merged
```

Resume, per ticket, on every /work start (before planning the wave):

| State on disk | Action |
|---|---|
| not done, `Branch` absent locally | frontier as usual → spawn |
| not done, `Branch` exists with commits beyond `Base tip` | worker's wip survived — inspect, respawn on it or land it |
| done, `PR: —` | landing step 3 (push + PR question) |
| `PR:` set | `gh pr view <url> --json state,isDraft,reviewDecision,baseRefName` → write `PR status`; then §6 drafts and §7 restack |

## 4. Spawn — two extra lines in the worker's prompt

Write `**Base tip:** $(git rev-parse <base ref>)` into the ticket file first (base ref = the story branch for `story`, ticket NN's `Branch` otherwise — the local ref: a landed blocker counts as done the moment it is committed on its branch, no push or PR needed). Then add to the prompt: `Branch: <Branch>` and `Base: <Base tip>`. The implementer starts in its own `wip/…` worktree as always and switches to the ticket branch first (its step 2). No hook, no `WT_BASE` involved: the Agent tool passes neither a worktree name nor env per spawn.

## 5. Landing — replaces /work step 4.5 "Merge and commit"

Review, verify (ui shots: see below), teach — unchanged. Then:

1. **Commit on the ticket branch, in the worker's worktree** — `git -C <wt> reset --soft <Base tip>` (folds the wip commits), then load and follow `~/.agents/skills/commit/SKILL.md` with every git command as `git -C <wt>`; staged = exactly the ticket's paths. One clean commit, no `wip:`. No squash into the story branch — the story branch only ever receives merged PRs. Set the ticket's status done and tick its criteria.
2. **UI verification** needs the ticket's code under the user's dev server, which runs in the orchestrator's worktree: `git checkout --detach <Base tip>` there → `<NN>-before.png`; `git checkout --detach <Branch>` → the step-4.3 batch → `<NN>-after.png`; then `git switch <story branch>`. The orchestrator's tree must be clean; never leave it detached.
3. **ONE AskUserQuestion: "push + open PR?"** (default yes). Yes → `git -C <wt> push -u origin <Branch>` (the user's `ask` on git push applies), then `/pr ticket <NN>` (`~/.agents/skills/pr/SKILL.md`, read the file) — it picks the base, the draft state and the screenshots; write `PR`/`PR status` right after. No → leave `PR: —`; the next /work offers it again.
4. **Stack link** — the ticket's chain has ≥2 tickets AND every branch of that chain is pushed with an open PR → `gh stack link --base <chain bottom base> <branch> <branch> …` (bottom to top). `link` pushes branches by itself through the GitHub API, past the user's `ask` on git push — so it runs only when nothing is left to push. No `--open` (§6 decides ready).
5. **Close** — `git worktree remove <wt>` and delete the `wip/…` branch only once the PR is open (otherwise keep the worktree for the resume); the ticket branch stays. Send `DONE` per §8.

Never edit Linear statuses, descriptions or labels from here — the tracker's GitHub integration (if enabled) moves the sub-issue when its PR opens.

## 6. Drafts

Siblings and the bottom PR of a chain: ready for review. Higher PRs in a chain: draft until the PR directly below is approved. /pr ticket states this to the project's /create-pr explicitly as the author's decision (its "never `--draft`" rule defers to the author, and this file is the author's decision). Nothing polls: on every /work resume (and `/pr ticket`), a draft whose lower PR shows `reviewDecision: APPROVED` → ask "mark #N ready for review?" → `gh pr ready <N>`, write `PR status: ready`.

## 7. Restack

- **A lower PR merged** → rely on GitHub's native cascading rebase of the stack, then `git fetch origin` and, for each local ticket branch above it, `git branch -f <Branch> origin/<Branch>` — only when the local branch has no commits missing from origin (`git log origin/<Branch>..<Branch>` empty); otherwise show them and ask. Rewrite `Base tip` to the new base sha.
- **Review fixes landed in a lower branch** (its tip moved past what the upper ticket's `Base tip` recorded) → from the top of the chain: `git rebase --update-refs --onto <lower Branch> <upper's Base tip> <top Branch>`. Always `--onto` with the recorded tip: a plain rebase re-applies or empties the lower commits after a squash. Conflicts are shown, never resolved silently. Then ask once, listing the branches, before `git push --force-with-lease origin <b> …` — never a force push without that answer. Rewrite each `Base tip`.
- `gh stack rebase`/`sync` are not used: there is no local stack tracking (`link` keeps none).

## 8. Cross-repo edges

The `WAITING`/`DONE` protocol of `/implement` section 0 is unchanged; in story mode `DONE` is sent when the BE ticket's PR is **opened** (landing step 3), not when it merges, and carries `pr=<url>` after `branch=`. FE never bases on a BE branch: a FE ticket that needs BE behaviour verifies against the BE worktree's server (`server=`).

## 9. The story PR

When the frontier is empty, /work's final report proposes `/pr story`: story branch → `base:` (the base branch or the epic). Ready when every sub-PR is merged into the story branch; otherwise draft, open sub-PRs marked "(open)"; `/pr story update` refreshes the list. Body through the project's /create-pr template: `## Changes` = one bullet per sub-PR (`#<n> <title> — <issue key> — <one-line summary>`), `## Review notes` = "Every change here was reviewed in its sub-PR (links above); review this PR for integration and conflicts only.", `## Visual` = "n/a — screenshots live in the sub-PRs". Title from the story issue. No screenshots, no change-summary. Label: the configured `WT_STORY_PR_LABEL` when set (`gh label list` to confirm it exists), else none.
