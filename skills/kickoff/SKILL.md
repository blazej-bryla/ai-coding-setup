---
name: kickoff
description: Plan a Linear task end to end — grilled context.md in ~/.agents/scratch/<slug>/, then spec/tickets.
argument-hint: "<Linear issue link> + optional intent/notes"
disable-model-invocation: true
model: opus[1m]
effort: high
---

# Kickoff

Turn a pasted Linear issue into a fully grilled `context.md` (plus optional spec and tickets) under `~/.agents/scratch/<slug>/`. All state lives in files, so the skill is **resumable**: re-running it with the same link continues from the first missing artifact instead of starting over.

Throughout: pull context lazily — the issue itself first, the wider story only when it exists — and delegate heavy research (story-wide Linear reads, codebase exploration) to subagents on `sonnet` so the main conversation stays small and cheap tokens do the fetching. Keep the interview and every decision in the main conversation — subagents cannot talk to the user.

## 1. Fetch the issue and derive the workdir

If no Linear link/ID was passed as an argument or pasted, ask for it.

Fetch the issue directly with the linear MCP `get_issue` (one compact call is cheaper than a subagent round-trip): title, full description, comments, labels, `branchName`, parent issue reference. The parent reference classifies the task — a parent story means **subtask**, no parent means **regular task**; ask the user only when the data is genuinely ambiguous (e.g. the parent is a grouping container, not a story). The configured story label (`story=` in `~/.agents/bin/wtconf -v WT_TRACKER_LABELS`) wins over the parent: the issue is a **story** — the regular-task branch, with sub-issues on Linear recommended (story mode, `~/.agents/skills/work/STORY.md`), even when it has an epic parent. This classification decides the branch taken in step 5.

Derive the slug from `branchName` with the task-key rule: first match of `[a-z]+-[0-9]+(-[0-9]+)?`, lowercased (`jdoe/todo-42-add-due-dates` → `todo-42`, `todo-7-1-x` → `todo-7-1`); no key → branch minus the username prefix. Side = `fe` in the configured `FE_REPO`, `be` in `BE_REPO` (`~/.agents/bin/wtconf FE_REPO BE_REPO`). One task = one slug = one scratch dir for both repos. Workdir = `~/.agents/scratch/<slug>/` (resolve `~` to the absolute home directory in tool calls); create it if missing.

**Subtask only** — pull the story context: derive the parent story's slug the same way. Spawn ONE `context-gatherer` subagent (retrieval on `sonnet` — never let this inherit the main model) to fetch the parent story (title, description) and sibling sub-issues (titles + statuses) from Linear, and to summarize whatever exists in `~/.agents/scratch/<parent-slug>/` (`context.md`, `spec.md`, tickets — broader context for this subtask). It returns one compact digest.

## 2. Resume check

Inspect the workdir before doing any work:

| Found in `~/.agents/scratch/<slug>/` | Action |
|---|---|
| `context.md` with `stage: grilled` | Skip to step 5 |
| `context.md` with `stage: draft` | Skip to step 4 |
| `context.md` with `stage: grilled` AND `tickets/<other side>/` exists but `tickets/<this side>/` does not | This is the second repo of a two-repo task: spawn Explore for this side only, append its synthesis to `## Codebase findings` under `### <this side>`, then jump to step 5 to cut this side's tickets — no second grilling unless the findings contradict a settled decision |
| no `context.md` | Continue with step 3 |

## 3. Explore the codebase and draft context.md

Scope the exploration to what existing context does NOT already cover: for a subtask whose story has a grilled `context.md` in `~/.agents/scratch/<parent-slug>/`, the Explore subagent verifies that map still holds and extends it for this subtask's specific area, instead of re-exploring from scratch. Spawn the Explore subagent with the task digest, `model: sonnet` (exploration is retrieval — the judgement stays here); it should return a synthesis — relevant modules, existing patterns and seams, constraints, prior art — not file dumps.

Write `~/.agents/scratch/<slug>/context.md`:

```markdown
---
stage: draft
issue: <Linear ID / URL>
branch: <full branchName>
mode: local            # local | story — set in step 5; story rules: ~/.agents/skills/work/STORY.md
base: <base branch>    # the configured WT_BASE_BRANCH, or in story mode the epic's branch (STORY.md §2)
---

## Task
<user's stated intent + Linear digest>

## Story context   <!-- subtasks only -->
<parent story summary, sibling subtasks, findings from ~/.agents/scratch/<parent-slug>/>

## Codebase findings
<synthesis from exploration>

## Open questions
<everything unsettled — grist for the grilling>
```

## 4. Grill it — always, proportionally

Run a `/grilling` session on `~/.agents/scratch/<slug>/context.md`, using the `/domain-modeling` skill to maintain the glossary and ADRs as terms and decisions settle. (Invoke those two directly — they are model-invoked and reachable; the `/grill-with-docs` wrapper is user-invoked and out of a skill's reach.)

Scale the interview to what is actually unsettled: a meaty "Open questions" section gets the full grill; an empty or thin one (typical for a narrow subtask under an already-grilled story) gets a short confirmation round — put the few remaining decisions to the user and stop. Always at least one round: the user confirms the scope before anything downstream is generated.

**Rollback question.** When the task touches DB schema/migrations, an API contract, validation or limits applied to existing data, auth/permissions, or deletes behaviour, ask one question in the grilling: how do we back this out, and what happens to existing data/clients? Record the answer in `context.md` under `## Rollback` (2–4 lines). Skip it for pure UI/copy changes.

When the interview is done, **overwrite** `context.md` with everything settled. Keep the frontmatter and set `stage: grilled`.

### Commit glossary/ADR entries

If grilling created or modified glossary or ADR files inside the repo (outside `~/.agents/scratch/`): stage exactly those paths — never `git add -A` — and commit them separately with a generated conventional message, e.g. `docs: add glossary entries for <topic>`. Do not add any Claude or session trailers (attribution is disabled globally; leave it that way).

## 5. Branch by task type

**Subtask** — no spec. Ask the user whether to create local tickets now. If yes, load and follow `~/.agents/skills/to-tickets/SKILL.md` (user-invoked — read the file, don't call the Skill tool) with: source = `~/.agents/scratch/<slug>/context.md`; publish as LOCAL files only, one file per ticket, to `~/.agents/scratch/<slug>/tickets/<side>/<NN>-<slug>.md`; leave the tracker and the parent issue untouched.

State this to /to-tickets as a caller requirement: "Slice for parallel execution.
Every ticket carries a `**Touches:**` line — the modules or paths it will change
(3–8 entries, directories preferred over files) — and one or more `**Verify by:**`
lines using three kinds: `ui <route> [as <user>] — <expectation>` (a UI ticket must
have at least one; the expectation is text a human can read on the page),
`cmd <command>`, `test <path>`. Tickets that are unblocked at the same time should
touch disjoint areas so separate workers can build them in one wave in separate
worktrees; when two tickets must change the same area, give the later one a
blocking edge on the earlier one. Prefactoring tickets go first and block what
they enable. Keep each ticket buildable by one worker in one fresh context, with
its own tests. Every ticket declares `**Repo:** fe | be` and is written under `tickets/<that side>/`. A blocking edge to the other side's ticket is written as `be/02` or `fe/03`. When the task spans both repos, cut both sides' tickets in this one run; the other repo's /kickoff will only add its codebase findings."

**Regular task** (a story included) — ask the user (one AskUserQuestion call, two questions):

1. Run `/to-spec` first? If so, local only (`~/.agents/scratch/<slug>/spec.md`) or also publish to Linear as the issue's description?
2. Tickets: local files only (`mode: local` — one PR per repo, as today), or ALSO created as Linear sub-issues under the pasted task (`mode: story` — one PR per ticket, stacked only on real chains)? Recommend Linear when the issue has the story label, local otherwise; the user decides.

Then load and follow `~/.agents/skills/to-spec/SKILL.md` (if chosen) and `~/.agents/skills/to-tickets/SKILL.md` (both user-invoked — read the files), applying the answers — these skills take their target from the caller, so state it explicitly while following them.

State this to /to-tickets as a caller requirement: "Slice for parallel execution.
Every ticket carries a `**Touches:**` line — the modules or paths it will change
(3–8 entries, directories preferred over files) — and one or more `**Verify by:**`
lines using three kinds: `ui <route> [as <user>] — <expectation>` (a UI ticket must
have at least one; the expectation is text a human can read on the page),
`cmd <command>`, `test <path>`. Tickets that are unblocked at the same time should
touch disjoint areas so separate workers can build them in one wave in separate
worktrees; when two tickets must change the same area, give the later one a
blocking edge on the earlier one. Prefactoring tickets go first and block what
they enable. Keep each ticket buildable by one worker in one fresh context, with
its own tests. Every ticket declares `**Repo:** fe | be` and is written under `tickets/<that side>/`. A blocking edge to the other side's ticket is written as `be/02` or `fe/03`. When the task spans both repos, cut both sides' tickets in this one run; the other repo's /kickoff will only add its codebase findings."

Story mode only, add to it: "Each ticket has at most ONE blocker in its own repo — linearise per `~/.agents/skills/work/STORY.md` §2 and show the linearised edges in the quiz; cross-repo edges don't count."

Once the breakdown is approved and before publishing, print one line per repo — `fe: 5 tickets, ~1400 lines (Touches + findings) → story` — a hint only, then write `mode:` (and `base:` per STORY.md §2) into context.md's frontmatter; the user may still switch here (switching to story re-runs the linearisation).

**Story mode publication** — one `save_issue` per ticket, in dependency order: parent = the story; title `[<fe label>] …` / `[<be label>] …` (the `fe=` / `be=` labels of `WT_TRACKER_LABELS`) with no conventional-commit prefix; description `## Parent` · `## What to build` · `## Acceptance criteria` · `## Blocked by` — no scratch paths, no AFK/HITL; native blocking relations only for the linearised edges; the `fe=` or `be=` label of `WT_TRACKER_LABELS` and nothing else. Right after each call, write back into that ticket's file, under `**Repo:**`, the STORY.md §3 block — `**Linear:**` the identifier, `**Branch:**` its `gitBranchName`, `**Base:** story|<NN>`, `**Base tip:** —`, `**PR:** —`, `**PR status:** —` — before the next call; a re-run skips tickets that already carry `**Linear:**`. Never set statuses.

For Linear publication use the linear MCP tools (`save_issue` with the parent set for sub-issues; issue description update for the spec). Local tickets always land in `~/.agents/scratch/<slug>/tickets/<side>/` — the side each ticket declares.

## 6. Wrap up

Report: the workdir path, artifacts produced, any commits made, and the suggested next step (new branch, implement the first unblocked ticket). Print two launch lines: `In this session: /work` (only when this session already runs in the task's worktree) and `New session: wt <full-branch> <fe|be> /work` (story mode with an epic base: `wt <full-branch> <fe|be> --base <epic branch> /work`) (opens Claude as `<slug>-<side>` in the task's worktree). `/work` with no argument takes `tickets/<side>/`; single-ticket alternative: `/implement`. If the conversation gets heavy mid-run, tell the user to `/handoff`, then `/clear`, then re-run `/kickoff <same link>` — step 2 resumes from the artifacts on disk.
