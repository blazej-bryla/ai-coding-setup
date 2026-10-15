---
name: implement
description: Implement one ticket end to end — semi-autonomous coding, then verify, review, teach, commit — and coordinate with sibling sessions by messages, never by timers or polling.
argument-hint: "optional: tickets dir or a single ticket file (default: this task's tickets/<side>/); optional after:<session>[#NN]"
disable-model-invocation: true
model: sonnet[1m]
effort: high
---

# Implement

Execute ONE ticket end to end: pick it from the frontier, build it autonomously, verify it, review it, make sure the user understands the change (teach), commit, then tell the sessions that were waiting on it. Planning is not this skill's job — the ticket says what to build; if it's too vague to act on, say so and stop rather than inventing scope.

State lives in `~/.agents/scratch/<slug>/` — outside every checkout, shared by all worktrees of all repos. Resolve `~` to the absolute home directory before using paths in tools.

## 0. Identity and peers

One identifier for everything: the **task key** in the branch name. Slug = first match of `[a-z]+-[0-9]+(-[0-9]+)?` in the branch name, lowercased (`TODO-12-add-due-dates` → `todo-12`, `dev/todo-7-1-x` → `todo-7-1`); no key → branch minus the `user/` prefix. Side = `fe` when this checkout's main worktree is `$FE_REPO`, else `be` (`git worktree list --porcelain | head -1`). From these: scratch dir `~/.agents/scratch/<slug>/`, tickets `tickets/<side>/` (a legacy `tickets/` with no side dir counts as this side's), session name `<slug>-<side>`, worktree `$WT_ROOT/<slug>-<side>`. Base branch = `$WT_BASE` when set, else the branch `origin/HEAD` points to, else the configured `WT_BASE_BRANCH` (`~/.agents/bin/wtconf -v WT_BASE_BRANCH`) — never assume `main`.

This session is one worker among several. Call `ListAgents` once: note this session's own name and which sibling sessions are live. If this session isn't named `<slug>-<side>`, ask the user to `/rename` it before continuing: siblings address it by name.

Peer messages go through `SendMessage`, plain text, first line in exactly this shape, detail below it only if needed:

- `WAITING <my-slug> for=<slug>[#NN]` — to the session you are parked on (step 1). `#NN` = one ticket of that session; no `#NN` = all of its tickets.
- `DONE <slug> ticket=<NN> branch=<branch> commit=<short-hash> remaining=<count> server=<http://localhost:PORT>` — after step 6, to every session that sent a matching `WAITING`, and to a session named `orchestrator` if one is live. Story mode (`~/.agents/skills/work/STORY.md` §8): sent when the ticket's PR is opened, not when it merges, with `pr=<url>` after `branch=`. `server=` is this worktree's dev server on this worktree's PORT (.env.local, else .env: `grep -h '^PORT=' .env.local .env | head -1`), so a sibling FE session can point at this backend.
- `DEVIATION <slug> <one line>` — an interface, API contract, or decision changed from what context.md/spec.md settled. Send immediately to every live session that could depend on it, and record it in context.md before doing anything else.

Never `sleep`, never poll git or the filesystem for another session's progress, never re-send an identical message (Claude Code drops repeats anyway).

## 1. Pick the ticket — or park on its blocker

The argument is optional: without one, the tickets dir is `~/.agents/scratch/<slug>/tickets/<side>/`. Read every ticket's title, "Blocked by", status, and acceptance criteria. A blocker written as `be/02` or `fe/03` is the other side's ticket — its file lives in `tickets/<that side>/`, and its owner is the session `<slug>-<that side>`. Load `context.md` and `spec.md` from the ticket dir's parent — the settled plan: respect its decisions, glossary terms, testing seams, and any API contract it fixes.

Compute the **frontier**: tickets not done whose blockers are all done. A single ticket file passed as argument is the candidate regardless of the frontier.

- **Unblocked, no `after:`** → confirm the ticket in one line and go to step 2. Several on the frontier and no file passed → ask which (AskUserQuestion). Empty frontier and nothing to wait on → report what blocks and stop.
- **`after:<session>[#NN]` passed, or the candidate depends on work in another session** → **park**:
  1. `ListAgents` → is that session live? No → report and stop; the user starts it or does that work first.
  2. Send it `WAITING <my-slug> for=<session>[#NN]` with `notify_when_idle` attached to the same `SendMessage` call (the message is delivered first, the idle notice comes later — a safety net, not the signal).
  3. Say in one line what you are waiting on, then **END THE TURN**. Parked, this session costs nothing.
  4. On every wake-up — a `DONE` message, an idle notice, or anything else — check the truth on disk: `~/.agents/scratch/<slug>/tickets/` of the session you wait on. Awaited ticket (or all its tickets) done → continue to step 2. Not done → re-subscribe with `notify_when_idle` (no message body) and end the turn again. An idle notice is one-shot and means only "that session finished a turn"; the ticket files decide.
  5. If the `DONE` carries `server=` and this is the FE side, set the FE app's backend-URL variable (the configured `FE_API_VAR`: `~/.agents/bin/wtconf -v FE_API_VAR`) to `<server>` in `./.env.local` — overwrite the line, don't append a duplicate — and say so in one line. If the FE dev server doesn't reload env files on change, ask the user to restart it.

## 2. Sync, then implement — autonomously, in the main conversation

Sync first: `git fetch origin`; if the awaited work landed in another worktree of this repo, rebase onto its branch — the commits are already in the shared object store, no push needed — otherwise rebase onto the base branch (section 0). A conflict is never resolved silently: show it and ask.

Code here, not in a subagent, and without stopping for edit approvals — the session runs with `acceptEdits`, and the user reviews the finished diff at steps 4–5, not each edit. Do not narrate edits. Stop only for: a decision the ticket/context/spec leaves open (AskUserQuestion), an acceptance criterion you cannot meet, or the gates below. Delegate only research to Explore subagents on `model: sonnet`, and only when the answer isn't already in context.md/spec.md.

Before writing any code, read the ticket's `**Prior art:**` paths and copy their structure — file layout, naming, how they fetch, validate and test (missing or `none` → no prior art) — and the "Conventions" section of the repo's worker contract, `~/.agents/projects/<repo>.md` (repo = the directory name of the configured `FE_REPO` / `BE_REPO`), the same references `/work` hands its implementers.

Build the ticket as the tracer bullet it describes — a narrow but complete vertical slice, demoable on its own. Prefer the seams the spec chose. Run the relevant tests as you go; a green run is part of the slice.

FE and BE are separate sessions in separate repos, one owner per repo. The API contract lives in spec.md/context.md and is owned by the BE ticket that implements it. Never invent a contract on the FE side: if it is unclear, ask the BE session by message and park until the answer arrives. If you must change a contract, send `DEVIATION` first.

## 3. Verify

Walk the ticket's acceptance criteria one by one against actual behaviour (run the thing, not just the type-checker). Tick the criteria checkboxes in the ticket file as each is verified. All green → proceed. If something can't be met, tell the user and decide together before going further.

## 4. Review — the deep-review subagents, scoped to this ticket

Nobody watched the edits land, so this gate carries more weight than before. Run the reviewer pass exactly as the "Reuse" section of `~/.agents/skills/deep-review/SKILL.md` describes — the risk-based selection applies (classifier + rules); when a flag looks wrong for what you know of the change, add that dimension rather than drop it — nobody watched these edits land. This ticket's parameters: diff command = the uncommitted changes (`git diff` plus untracked files); requirements sources for the QA reviewer = this ticket's file plus `context.md`/`spec.md`. Step 3b (findings log, repeat → rule proposal) is part of that pass; ticket = this ticket's id.

Fixes land in the same commit as the ticket. Only a clean (or consciously accepted) review proceeds to teach — and findings fixed here are good teach material.

## 5. Teach — always before any commit

Never commit without this step. It also applies to intermediate commits: each commit is preceded by a teach round covering the changes since the last commit.

Open with a **diff brief**: 3–6 lines — what changed, where, why this shape — so the user sees the change before being quizzed on it. Then quiz until they can defend it:

- 2–4 questions (1–2 when the diff is trivial) via AskUserQuestion, one at a time — concrete, about THIS diff ("why did the new query go through X instead of Y?", "what happens now when <edge case>?"). Multiple-choice with plausible distractors; every question carries a **"Skip teach — commit now"** option, and stop/skip at any point ends teach immediately.
- Explanation level, starting at 1: **Level 1** terse, expert-to-expert; **Level 2** plain language, data flow step by step; **Level 3** first principles: analogies, a traced example with real values, no jargon.
- Correct → confirm briefly, next question. Wrong → level +1, re-explain at the new level, re-ask differently; stay at the raised level for the rest of the round.
- End with a 2–3 sentence recap at the level you finished on.

## 6. Commit

Commit by loading and following `~/.agents/skills/commit/SKILL.md` (user-invoked — read the file, don't call the Skill tool), scoped to the ticket's paths. Terse message, no attribution — that skill handles it. No push: pushing stays with the user.

## 7. Close out and notify

Close the ticket in its own `.md` file: all acceptance checkboxes ticked (done during verification) and the status line set to done. If the implementation settled or changed anything the plan didn't capture — a decision made mid-build, a discovered constraint, a renamed concept — update `~/.agents/scratch/<slug>/context.md`; skip when nothing changed.

Then notify: go through every `WAITING … for=<this slug>[#NN]` message this session has received; for each whose `#NN` is this ticket, or has no `#NN` and no tickets remain, send `DONE …` to that session. Send `DONE …` to `orchestrator` too if it is live. Do not notify anyone else.

Report: what was built, test/criteria evidence, commit hash, who was notified, and the new frontier. Then ask: take the next frontier ticket in this session now, or stop here? If this conversation is already heavy, recommend stopping — `/clear` and re-run `/implement <tickets dir>` picks the frontier up fresh (state lives in the ticket files; a WAITING list is lost on `/clear`, so tell the user which sessions to re-park).
