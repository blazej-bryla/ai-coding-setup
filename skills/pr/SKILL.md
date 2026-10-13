---
name: pr
description: Open or update the pull request for this branch — the project's own /create-pr decides the PR's shape (template, title, labels, reviewers); this skill supplies the content: what and why from the planning artifacts, "how to test" from the tickets, test evidence, before/after screenshots (plus a pixel diff when the deployed baseline is the BEFORE) taken with the agent-browser CLI, and an optional architecture-delta/sequence diagram from the diagram-design plugin, all attached with gh --attach.
argument-hint: "optional: update [summary] (refresh workflow sections + shots on the existing PR; summary also re-runs the change summary) | comment (post refreshed AFTER shots as a comment, e.g. after /address-review) | ticket <NN> (story mode: one ticket's PR) | story [update] (story mode: the story PR); any mode but comment also takes diagram (force one) | nodiagram (skip it; with update, remove it)"
disable-model-invocation: true
model: sonnet[1m]
effort: medium
---

# PR

Two owners, one PR. The **project** owns the shape — its `/create-pr` skill knows the template, the title format, labels, reviewers, checklists, whether it pushes. The **workflow** owns the content — `~/.agents/scratch/<slug>/` (context.md, spec.md, tickets), the tickets' `Verify by:` lines, test evidence, and the before/after screenshots. This skill gathers the content, then loads and follows the project's skill, handing it the content as explicit inputs — the same way `/kickoff` drives `/to-spec` and `/to-tickets`. Resolve `~` to the absolute home directory before using paths in tools.

## 0. Prerequisites — fail loudly, don't improvise

- `gh --version` ≥ 2.99 (`--attach`). Older → stop and say so.
- `agent-browser --version` answers. Missing → stop, unless no ticket has a `ui` line.
- Two dev servers when there are `ui` lines. **BE**: BEFORE_URL = the main checkout's server (`PORT` from the main checkout's `.env`), AFTER_URL = this worktree's PORT (.env.local, else .env: `grep -h '^PORT=' .env.local .env | head -1`). **FE** — mode by the same rule `wts` uses (`$WT_ROOT/<slug>-be` exists → local, else remote):
  - **local** (a BE sibling exists): BEFORE_URL = the main checkout on the configured remote-API FE port R (`~/.agents/bin/wtconf -v WT_REMOTE_FE_PORT`), AFTER_URL = this worktree's PORT, as above.
  - **remote-API** (no BE sibling; this worktree's FE runs on R because the remote API may accept only that origin, so both can't sit on R at once): if a baseline FE is configured (`~/.agents/bin/wtconf -v WT_BASELINE_FE_URL` — the deployed base branch), BEFORE_URL = that URL and AFTER_URL = `http://localhost:R`, and each pair also gets a diff image (step 2). Otherwise take the shots sequentially on R: ask the user (AskUserQuestion) to start the main checkout with the configured remote-API dev command (`~/.agents/bin/wtconf -v WT_FE_REMOTE_DEV_CMD`), take every BEFORE shot; then ask them to stop it and start the worktree (`wts <slug> fe`), take every AFTER shot.

  **FE AFTER_URL** = the contents of this worktree's `.shots/.fe-url` if present (`wts` writes it on start, removes it on exit); else the `wts` rule — this task's BE worktree exists → this worktree's PORT (.env.local, else .env), otherwise `http://localhost:<R>` (R = the configured remote-API FE port, `~/.agents/bin/wtconf -v WT_REMOTE_FE_PORT`). BE AFTER_URL = this worktree's PORT (.env.local, else .env).

  `curl -sI` each server before its shots. **Servers are the user's.** Never start a dev server yourself (whatever the project's dev command is — `~/.agents/bin/wtconf WT_FE_DEV_CMD WT_BE_DEV_CMD`), never kill anything, and never pick another port. If nothing answers at the URL, or `wtwho` shows port R held by another worktree, tell the user in one line — "port R is held by <slug> — run `wts <slug> fe --take` when you can" (or "run `wts <slug> fe`" when it is free) — and wait (AskUserQuestion).
- Project skill: the configured `WT_PR_SKILL` path (`~/.agents/bin/wtconf -v WT_PR_SKILL`; default `.claude/skills/create-pr/SKILL.md`) in this checkout (worktrees have it — it's tracked). Present → it drives step 4. Absent → the built-in template in step 4b.
- Existing PR? `gh pr view --json number,url,body` → `update` mode unless told otherwise; `comment` only when asked.
- Diagram (step 2b), only when step 2b's rule says to draw one: `~/.agents/bin/pr-diagram-check` prints the diagram-design plugin's path (exit 0) or one line `no diagram: <why>` (exit 1). Exit 1 → no diagram; carry that line into the report and the body preview, and run everything else unchanged. Never install the plugin or playwright, and never fail the PR over the diagram.

## 1. Collect the content

- slug, side and base branch per section 0 of `~/.agents/skills/implement/SKILL.md` → workdir `~/.agents/scratch/<slug>/`, tickets `tickets/<side>/`.
- Done tickets: titles, `Verify by:` lines (all kinds), test evidence noted in them; `context.md` settled decisions; `spec.md` problem/solution when present; Linear issue title for the PR title.
- Bug case (no tickets, `bug.md` present — a `/bugfix` branch): "How to test" is `bug.md`'s `Verify by:` line; a `ui` line there is also the screenshot route (step 2), and `.shots/fix-before.png` / `fix-after.png` from `/bugfix` may be reused instead of re-taking them when the fix commit hasn't changed since.
- `git log <base>..HEAD --oneline` (base = the base branch per section 0 of /implement). Pass the same base to `gh pr create --base` unless the project skill sets it.

## 2. Screenshots — only for `Verify by: ui …` lines

Grammar: `Verify by: ui <route> [as <user-hint>] — <what should be visible>`, one line per route.

Same procedure on BEFORE_URL, then AFTER_URL, in this task's agent-browser session `<S>` = `<slug>-<side>`; every call is `agent-browser --session <S> --state ~/.agent-browser/auth-base.json --restore …`. If a page shows the login screen (`~/.agents/bin/wtconf -v WT_LOGIN_SCREEN_HINT`), do not type credentials: `agent-browser --session <S> close`, tell the user in one line "login screen — run `ablogin` and let me know", wait (AskUserQuestion), then run the batch again. Screenshots go to this worktree's `.shots/` (`<WT>` = `$(git rev-parse --show-toplevel)`, absolute) — the worktree hook keeps `.shots/` out of git via `.git/info/exclude`.

Per route and base URL, ONE batch (JSON on stdin, so the expectation and the script need no shell quoting):

```
agent-browser --session <S> --state ~/.agent-browser/auth-base.json --restore batch <<'JSON'
[["set","viewport","1440","900"],
 ["open","<base-url><route>"],
 ["wait","--text","<expectation>"],
 ["eval","document.head.insertAdjacentHTML('beforeend','<style>*{animation:none!important;transition:none!important;caret-color:transparent!important}::-webkit-scrollbar{display:none}nextjs-portal{display:none!important}</style>');document.activeElement?.blur()"],
 ["screenshot","<WT>/.shots/<NN>-before.png"]]
JSON
```

- No expectation given → `["wait","--load","networkidle"]` instead. Viewport by default; `["screenshot","--full",…]` only when the expectation sits below the fold (then for both shots of the pair). Never a screenshot without a path.
- AFTER: the same batch with `<NN>-after.png`, plus `["snapshot","-i","-c"]`, `["console"]`, `["errors"]`, `["network","requests","--status","400-599"]` after the wait — confirm the expectation is in the snapshot; console errors, page errors or listed requests → "Known issues", never swallowed, never fixed here.
- Baseline as BEFORE (`WT_BASELINE_FE_URL` set, remote-API mode) → the AFTER batch ends with `["diff","screenshot","--baseline","<WT>/.shots/<NN>-before.png","-o","<WT>/.shots/<NN>-diff.png"]` (same 1440×900 viewport on both shots, or the diff is meaningless); note the reported % of changed pixels for the caption. Above ~40% look at both shots before trusting it: a modal, toast or banner on one side only (app state, not this change) dims or shifts the whole page — say so in the caption ("diff: modal X only in after") instead of the bare %; don't dismiss the app's modals to make the diff clean. Sequential flow (no baseline URL) → no diff.
- Step done → `agent-browser --session <S> close`; never `close --all` (other tasks' sessions).

A BEFORE that is a 404 or an empty state (new screen) is still a screenshot — caption "before: route did not exist". Cap at 6 pairs; beyond that, pick the routes the spec calls primary and list the rest as links under "How to test".

## 2b. Diagram — optional, one per PR

**When.** Decide first, and say the decision in one line ("diagram: architecture-delta — 3 modules + new endpoint" / "no diagram: pure UI change in 2 components").

- `nodiagram` given → none. `diagram` given → one, whatever the rule below says. `comment` mode → never.
- `story` mode → always.
- Default and `ticket <NN>` mode → only when the change spans **≥2 modules** OR touches an **API contract**, and is not a pure UI/copy change:
  - Files = the tickets' `**Touches:**` lines (bug case: `bug.md`) plus `git diff --stat <base>...HEAD`; the diff wins where they differ. Tests, docs, glossaries, lockfiles, fixtures and generated files don't count.
  - **Module** and **API contract**: the `PR diagram` section of the worker contract (`~/.agents/projects/<repo>.md`) defines both for this repo when it has one. Otherwise: **module** = the path down to the first directory under `src/` that isn't a grouping container (`src/todos/`, `src/notes/`; in `src/modules/Todo/` the `modules/` level is a container, so `Todo/` is the module). Two repos (a BE and an FE side in one PR's content) count as two modules.
  - **API contract** (default): a route handler or endpoint definition, a request/response or persisted-model type, the FE's API client, or types shared between FE and BE.
  - **Pure UI/copy** = every counted file is view layer — components, pages, route UI, styles, copy/i18n — with no API contract, no data-fetching hook/query change and no new route or module. Pure UI → no diagram even across ≥2 modules.

**Check.** `~/.agents/bin/pr-diagram-check` (step 0). `no diagram: …` → skip this step with that line; nothing else changes.

**What.** One type, stated in one line with the reason:
- **architecture-delta** — structural change: modules, endpoints, services, DTOs/data added, changed or removed.
- **sequence** — a new or changed request flow (who calls whom, in what order) is the point of the change.

Source of truth: `context.md`, `spec.md`, the tickets (or `bug.md`) and the actual diff (`git diff <base>...HEAD`). Draw only what the diff shows: every node and edge maps to a file or symbol in it, or to the unchanged neighbour it plugs into (`AuthGuard`, the existing service it calls). No invented components, no planned-but-unbuilt work. Dials: detail `balanced`, audience `engineer`, size `doc-wide`, at most ~12 nodes — and within the type's own budget, which is tighter (architecture-delta: 8 components, 10 relationships, 8 ledger entries; sequence: 5 lifelines, 12 messages). Over budget → draw the primary subsystem and name what's left out in the caption.

**How.** Invoke the `diagram-design:diagram-design` skill with these stated as settled caller inputs: type, the dials above, the nodes/edges/ledger (or lifelines/messages) you derived, output file `<WT>/.shots/diagram.html` (overwrite), and "the default skin is the user's choice for PR diagrams — skip the first-time style-guide gate, write no `.diagram-design` marker or profile in this repo". Then invoke `diagram-design:export-diagram` with `<WT>/.shots/diagram.html --png-only` → `<WT>/.shots/diagram.png`. Read the PNG back once (Read tool) to confirm it renders — labels legible, no black boxes. Export fails or the PNG is broken → no diagram, one line why.

Both files live in `.shots/` (kept out of git by `.git/info/exclude`); never `git add` them. `<WT>` = the checkout the PR is made from (`ticket <NN>`: that ticket's repo dir; `story`: the story branch's checkout).

Caption: one line, ≤ 100 chars, saying what changed — `Todos: new reminders module behind AuthGuard; TodoDto gains dueDate`.

## 3. Assemble the PR data block

Write `<workdir>/pr-data.md` — this is what the project skill receives. Every section is wrapped in ownership markers so later updates can replace it surgically:

```
title: <Linear issue title — the project skill applies its own format around it>

<!-- wf:what -->
<2–4 sentences from context.md/spec.md: the problem, the shape of the change, the one decision that mattered and why>
<!-- /wf -->

<!-- wf:diagram -->
![<one-line caption>](<WT>/.shots/diagram.png)
<one-line caption>
<!-- /wf -->

<!-- wf:how-to-test -->
- <one bullet per Verify by line, verbatim — ui, cmd and test alike>
<!-- /wf -->

<!-- wf:before-after -->
| Route | Before | After | Diff |
|---|---|---|---|
| `/todos` | ![before /todos](<WT>/.shots/01-before.png) | ![after /todos](<WT>/.shots/01-after.png) | ![diff /todos](<WT>/.shots/01-diff.png) |
<!-- /wf -->

<!-- wf:tests -->
<what ran and passed, one line, from the tickets>
<!-- /wf -->

<!-- wf:known-issues -->
<console errors, failed requests, spec's out-of-scope items — or "none">
<!-- /wf -->

attachments:
- <WT>/.shots/01-before.png
- <WT>/.shots/01-after.png
- <WT>/.shots/01-diff.png
- <WT>/.shots/diagram.png
```

The "Diff" column (and its attachment) exists only when the diffs were taken (baseline as BEFORE); otherwise the table has three columns. `wf:diagram` (and `diagram.png` under `attachments`) exists only when step 2b produced a diagram; otherwise leave the section out entirely — no empty markers.

Rules: image paths in the markdown must be the exact strings listed under `attachments` (absolute), because `gh --attach` rewrites references in place. Linear links the PR by branch name — no link. No process detail (which reviewers ran, tiers, counts): the reader is the reviewer.

## 4. Create — drive the project's /create-pr

Load the project skill (`WT_PR_SKILL`) and follow its text (user-invoked — read the file, don't call the Skill tool), with these instructions stated explicitly to it, the way a caller states a publication target:

- **Inputs are settled.** The description, testing steps, test evidence and known issues are in `<workdir>/pr-data.md`. Do not interview the user for them and do not derive them from commit messages; use the block.
- **Its shape wins.** Keep its template, title format, labels, reviewers, checklist, draft rules, push behaviour. Map the block's sections into the template by meaning: `wf:what` → the description/summary section, `wf:how-to-test` → the testing/verification section, `wf:tests` → wherever test results go, `wf:known-issues` → limitations/notes. Keep the ownership markers inside the template's sections.
- **No home for a section → append it.** Sections with no counterpart in the template (typically `wf:before-after` and `wf:diagram`; a diagram/architecture/visual section in the template is `wf:diagram`'s home) go in, markers included, after the template's last section, under a heading in the template's style.
- **Attachments ride the same command.** Whatever `gh pr create` invocation the project skill builds, add one `--attach <path>` per entry under `attachments` and keep the body via `--body-file`. If the project skill uses `--body` with an inline string, switch that one call to `--body-file` so paths survive intact.
- **Its checklist stays yours to answer.** Items the block can't answer (e.g. "migration reviewed by X") are left as the template leaves them; the user ticks them.

Show the user the resulting body once before the command runs, with one line under it: `diagram: <WT>/.shots/diagram.png (<type>, <n> nodes)` or step 2b's `no diagram: <why>`; run it; report the URL. Then step 4c.

### 4b. Fallback — no /create-pr in this repo

`gh pr create --title "<title>" --body-file <workdir>/pr-body.md --attach …`, where pr-body.md is the data block's sections under `## What`, `## Diagram` (when there is one), `## How to test`, `## Before / after`, `## Tests`, `## Known issues / out of scope`. Draft when not all tickets are done. Then step 4c.

### 4c. Change summary

If the configured change-summary skill (`~/.agents/bin/wtconf -v WT_CHANGE_SUMMARY_SKILL`; default `.claude/skills/change-summary/SKILL.md`) exists in this checkout, load it and follow its text the same way step 4 drives /create-pr (user-invoked — read the file, don't call the Skill tool), stating these explicitly to it:

- **The PR**: the number and URL just created, and the base branch.
- **Inputs are settled.** The what/why, testing and known issues are in `<workdir>/pr-data.md`; the commits are `git log <base>..HEAD --oneline`. Do not interview the user for what these already answer.
- **Its output stays its own.** Wherever the project skill posts or writes (Slack, Linear, changelog, copy-paste) is its decision, not this skill's.

Absent → skip silently.

## 5. Update and comment modes

- **update**: `gh pr view --json body` → replace only the text between each `<!-- wf:… -->` / `<!-- /wf -->` pair with the freshly assembled section; anything outside the markers (template text, human edits, reviewer notes) stays byte-for-byte. Then `gh pr edit <n> --body-file <updated> --attach …` for images referenced in the replaced sections. A PR created before this skill existed has no markers: append the workflow sections once, with markers, and say so. Step 4c re-runs only when the user asks for it (`/pr update summary`).
  - Diagram: step 2b runs again — regenerate `diagram.png` and replace only the `wf:diagram` section (attach the new PNG). No `wf:diagram` yet and step 2b draws one → insert the section right after `wf:what`'s `<!-- /wf -->`. Step 2b says no diagram but the PR has one → leave it as is. `/pr update nodiagram` → remove the `wf:diagram` section, markers included, and nothing else.
- **comment**: re-take the AFTER shots for the routes the latest commits touched (all `ui` routes if unsure), write `<workdir>/pr-comment.md` titled "After fixes" listing the addressed threads with the after-shot per route, then `gh pr comment <n> --body-file … --attach …`. The pattern after `/address-review`. Never runs step 4c or step 2b (no diagram).

## 6. Story mode — `ticket <NN>` and `story`

Rules of story mode live in `~/.agents/skills/work/STORY.md`; these two modes are the only PR logic it uses. Steps 0–4 apply with these changes, stated to the project's /create-pr as explicit caller inputs:

- **`ticket <NN>`** — the PR of one ticket from `tickets/<side>/<NN>-*.md`. Repo dir = that ticket's worktree (`git worktree list` → the one on its `**Branch:**`; none → `git worktree add $WT_ROOT/<slug>-<side>-<NN> <Branch>`, removed after); every git/gh command runs with `git -C <dir>` / `gh … --head <Branch>`. **Base** = the story branch for `Base: story`, else ticket `<Base>`'s `**Branch:**` — stated to /create-pr as settled, so its stacked-branch question doesn't run. **Draft** = STORY.md §6 (chain above its bottom PR → draft; otherwise ready) — stated as the author's decision, which /create-pr's draft rule defers to. Content = this ticket only: `wf:what` from its "What to build", `wf:how-to-test` from its `Verify by:` lines; shots reuse `/work`'s `.shots/<NN>-before.png` / `<NN>-after.png` when the ticket's commit hasn't changed since, else step 2 with BEFORE/AFTER on the user's server as STORY.md §5.2 describes. Title from the sub-issue (`**Linear:**`). Then step 4c (change summary) as usual. Write `**PR:**` and `**PR status:**` into the ticket file right after `gh pr create` returns; on a re-run with an open PR → `update` mode, plus the STORY.md §6 ready check.
- **`story`** — the story branch's PR to context.md's `base:`. No screenshots, no step 4c; always a diagram (step 2b, unless `nodiagram` or the check fails) of the whole story's diff `<base>...<story branch>`, its `wf:diagram` section placed after `## Changes`. Content: `gh pr view <PR> --json number,title,state` for every ticket of both sides' `tickets/` with a `**PR:**` (this repo only). /create-pr's template gets: `## Changes` = one bullet per sub-PR, `#<n> <title> — <issue key> — <one-line summary>`, open ones suffixed "(open)"; `## Review notes` = "Every change here was reviewed in its sub-PR (links above); review this PR for integration and conflicts only."; `## Visual` = "n/a — screenshots live in the sub-PRs". Draft while any sub-PR is unmerged (author's decision, as above). No label (STORY.md §9). `story update` rewrites only those sections (and `wf:diagram`, per step 5).

Report: PR URL, which sections were written or replaced, where the shots live, routes skipped and why, and the diagram (path, type, node count) or the one-line reason there is none.
