---
name: deep-review
description: Code review sized to the diff — one light reviewer for small diffs, four parallel specialists otherwise; deduped findings, interactive triage, one GitHub review.
argument-hint: "optional: PR number/URL, or a base ref to diff against"
disable-model-invocation: true
model: opus[1m]
effort: high
---

# Deep review

A review pass sized to the diff — one generalist reviewer for small diffs, four specialised reviewers in parallel otherwise — then one deduped findings list, an interactive triage, one GitHub review. The reviewer prompts live in this skill's `prompts/` directory (`light.md`, `security.md`, `codebase.md`, `tests.md`, `qa.md`); the `reviewer-*` agents in `~/.claude/agents/` load them — `/work`, `/implement` and `/bugfix` reuse those agents (see the last section).

## 1. Scope the diff

- A PR number/URL was passed, or `gh pr view` finds a PR for the current branch → review the PR: diff via `gh pr diff`, remember the head SHA for comment anchoring.
- Otherwise → diff against the merge-base with the base branch (`$WT_BASE` if set, else the branch `origin/HEAD` points to) (plus uncommitted changes if present). No PR means no GitHub publication; the triage still runs and `findings.md` is the deliverable.

Workdir: `~/.agents/scratch/<slug>/review/` (resolve `~` to the absolute home directory in tool calls) where slug = the task key in the current branch (first match of `[a-z]+-[0-9]+(-[0-9]+)?`, lowercased; no key → branch minus the username prefix). Create it; overwrite any per-dimension files from previous runs.

Also collect the **requirements sources** for the QA reviewer: `~/.agents/scratch/<slug>/` contents (`context.md`, `spec.md`, `tickets/<side>/` — side = `fe` in the configured `FE_REPO`, `be` in `BE_REPO` (`~/.agents/bin/wtconf FE_REPO BE_REPO`)), the Linear issue if identifiable (from the branch name or PR description), and the PR description itself. List whatever exists; "none found" is a valid answer and the QA reviewer will say so rather than guess.

## 2. Pick the reviewers by risk, then fan out

### Classifier

A replaceable step with a fixed contract — **input**: the diff; **output**: exactly this JSON. Anything that honours the contract can replace it without touching the rules below.

Spawn ONE subagent with `model: haiku`. Its prompt: read `<diff command> --stat` and the diff itself (ignore generated files — lockfiles, snapshots, codegen output), and return ONLY:

```
{"ui_only": bool, "touches_auth": bool, "touches_data_flow": bool, "logic_changed": bool, "tests_changed": bool, "reason": "<one line>"}
```

Definitions to give it: `ui_only` = only presentational changes (JSX structure, classNames, styles, copy, icons, design-system component swaps); `touches_auth` = auth, permissions, sessions, cookies, env/config, route handlers, server actions, middleware; `touches_data_flow` = fetch/API calls, data-layer hooks, store/state, cache, forms/validation, input parsing; `logic_changed` = non-presentational behaviour in hooks, store, utils, services — including code moved or restructured there in a way that can change runtime behaviour (evaluation/initialization order, imports that change what runs), and any bug fix; `tests_changed` = test files added or changed.

### Rules

Count changed lines from `--stat` (generated files excluded), then select dimensions:

- **security** ← `touches_auth` OR `touches_data_flow` OR the diff contains `dangerouslySetInnerHTML` / `eval` / `innerHTML` (grep the diff yourself — don't trust the classifier for this); `touches_auth` → the max-effort agent (see Fan out)
- **tests** ← `logic_changed` OR `tests_changed`
- **codebase** ← always, unless the diff is under ~20 lines
- **qa** ← always when requirements sources exist (step 1)

Exactly one dimension selected and the diff under ~80 lines → run `reviewer-light` instead of that one dimension's agent — unless that dimension is security with `touches_auth`, which keeps `reviewer-security-max`. Nothing selected → no reviewer; say so and stop here.

**Overrides win over the classifier**: the user saying `light`, `full` (all four), or naming dimensions ("only codebase and qa") — in args or conversation. State the selection and the classifier's `reason` in one line, e.g. `review: codebase + qa (classifier: ui_only — JSX/styles in 3 files)`.

### Fan out

Every reviewer is a named agent in `~/.claude/agents/` that pins its own model and effort and reads its prompt from `prompts/` — spawn it by `subagent_type`, never as `general-purpose` with a `model:` (an inline spawn inherits the caller's effort):

| Dimension / phase | Agent | Model · effort |
|---|---|---|
| light | `reviewer-light` | opus · high |
| security | `reviewer-security`; **`reviewer-security-max` when `touches_auth`** | opus · xhigh / max |
| qa | `reviewer-qa` | opus · high |
| codebase | `reviewer-codebase` | opus · high |
| tests | `reviewer-tests` | sonnet · high |
| refute (workflow phase 2) | `reviewer-refute` | sonnet · high |
| merge (workflow phase 3) | `reviewer-merge` | sonnet · low |
| classifier | inline, `model: haiku` | inherits (mechanical) |

- **light** → ONE `reviewer-light` — a single generalist pass (correctness, requirements, red flags).
- **Selected dimensions** → prefer a dynamic workflow when the Workflow tool is available (Pro: enable it once in /config) and two or more dimensions are selected: ask for a workflow (`ultracode`) with three phases — (1) the selected dimensions' agents run in parallel, each with the same context block, each writing its own file under `.../review/`; (2) a refute phase: for each dimension a fresh `reviewer-refute` tries to disprove that file's findings against the actual code and marks each finding `holds` / `disproved` / `downgrade` with one line of evidence; (3) one `reviewer-merge` merges the surviving findings into `findings.md` per step 3's rules. Without the Workflow tool (or with one dimension), one agent per selected dimension, all spawned in a single message so they run concurrently.

Either way, a reviewer's spawn prompt = only the context block you write (the agent already knows which prompt file to follow):

```
--- CONTEXT ---
Repo root: <path>
Diff command: <exact command, e.g. `gh pr diff 123` or `git diff <merge-base>...HEAD`>
Base / head: <refs or SHAs>
Output file: ~/.agents/scratch/<slug>/review/<dimension>.md  (create it; append findings)
Requirements sources: <paths to tickets/spec/context, Linear issue ID/URL, PR description — or "none found">
Dev server: <URL of a running dev server for this change, or "none">
```

Do not review inline yourself while the reviewers work — your job is orchestration and judgment on their output.

## 3. Deduplicate and rank

When all reviewers are done, read the per-dimension files and build `review/findings.md`:

- Merge duplicates: same root cause reported by ≥2 reviewers becomes ONE finding — keep the strongest evidence, note the corroboration (corroborated findings rank higher).
- Verify before keeping: drop anything the actual code disproves, and downgrade severity inflation (a nitpick dressed as an issue).
- Rank: blocking issues → issues → suggestions/questions → nitpicks/thoughts → praise. Number findings stably (`#1`, `#2`, …).

### 3b. Findings log — repeats become rule proposals

Runs every time step 3 runs (standalone and in the Reuse pass). Repo = the directory name of the configured `FE_REPO` (FE) or `BE_REPO` (BE); ticket = the ticket id in `/work`/`/implement` (e.g. `fe/03`), `bug` in `/bugfix`, the PR number or `review` standalone.

1. **Compare first.** Read `~/.agents/rules/findings-log.jsonl` (missing = empty). For each kept finding from the **codebase** and **light** reviewers (not praise, not disproved), look for a logged finding of the same KIND of problem — judge by meaning, not wording (e.g. "date formatted inline instead of the shared formatDate helper" = "`toLocaleDateString()` called in a component") — with a different `slug` or `ticket`. Found → it's a **repeat**.
2. **Then append** one line per such kept finding (compact JSON, `>>`):
   `{"date":"YYYY-MM-DD","repo":"<repo>","slug":"<slug>","ticket":"<ticket>","reviewer":"codebase|light","title":"…","file":"<path>","summary":"…","fix":"…"}`
3. **For each repeat, draft a proposal:**
   - Expressible as an ERE on ADDED code (a token that appears in the bad code and not in the fix) → draft a rule in the `~/.agents/rules/<repo>.json` shape: `id`, `pattern` (grep -E), `paths`, `exclude` (specs, tests, stories, and the file where the pattern legitimately lives, e.g. `src/styles/**`), `message` from the finding's fix (one or two sentences, name the project's alternative by path), `"source": "finding:<slug>/<ticket>"`, `added` = today. **Test it** before proposing: write the offending hunk (the added lines as they are in the diff) and the suggested fix to two files in `~/.agents/scratch/<slug>/review/`, the rule to a third, and run `~/.agents/hooks/rules-check.sh --try <rule.json> <bad> <fix> <repo-relative file>` — it must print `rule ok` (bad matches, fix doesn't, path covered). Fails → rework the pattern; still failing after two tries → treat as not expressible.
   - Not expressible (judgement, structure, naming, missing test) → draft ONE line for the `Conventions` section of `~/.agents/projects/<repo>.md` instead (the bullets under "Conventions enforced by the `codebase.md` reviewer").
4. **Ask** (AskUserQuestion, one question per proposal, showing the pattern or the line, the two findings it came from, and the `--try` output): **add as block** / **add as warn** / **skip** (for a Conventions line: **add** / **skip**). Never add a rule or a line without the answer. On add → append the rule to the JSON array (keep it valid: `jq . <file>` after writing) or the line to the project file; tell the user the file changed in `~/.agents` and is theirs to commit.

Standalone, this question comes right after the findings table, before the triage walk. In `/work` it belongs to the **landing step** of that ticket, asked together with the ticket's other debatable findings — never a separate stop that holds the loop; `/implement` and `/bugfix` ask it with their debatable findings.

## 4. Triage

**≤ 5 findings** → walk them one at a time (below). **More** → batch first: show the whole ranked list as a table (`#`, label, blocking, `file:line`, one-line summary), then ask the user to assign the numbers in bulk — **queue**, **skip**, or **discuss**; only the "discuss" ones get the one-at-a-time walk.

The one-at-a-time walk goes through `findings.md` in rank order. For each finding, show:

> **Finding N of X — `label (blocking|non-blocking)`** `file:line`
> summary + suggested fix (if any)

Then ask (AskUserQuestion):

- **Explain deeper** → walk the code path, the evidence, and the consequence in full; then re-ask this same finding.
- **Add to GitHub review** → queue it as a review comment anchored at the exact file/line, body in Conventional Comments format: `**label (blocking|non-blocking):** <summary>` + short rationale + suggested fix. Use GitHub suggestion blocks (```suggestion) when the fix is a small in-place replacement.
- **Skip** → drop it from the queue (it stays in findings.md for the record).

The user can stop the triage at any point; queued comments still get submitted.

## 5. Submit one review

Publish everything queued as a SINGLE review via `gh api repos/{owner}/{repo}/pulls/{n}/reviews` (comments array with `path`, `line`, `side: RIGHT`, anchored to the head SHA) — never one-off spammy single comments. Queued findings without a line anchor (`file: (none)` — typically unmet requirements from the QA reviewer) go into the review's top-level body text instead of inline comments.

### The review body — keep it short

The body is written for the PR author, not for you. **Max 3–4 sentences.** Open by naming something the author genuinely did well (specific, not flattery), then touch lightly on the theme of what came up, then — if there is a blocking finding — one sentence saying what blocks and where. The inline comments carry the detail; the body does not repeat them.

Never put in the body:

- how many reviewers ran, which dimensions, or that this was a "deep review" — process detail, invisible value to the author
- finding counts, raw-vs-deduped numbers, severity tallies
- a list of findings that were skipped during triage (that record lives in `findings.md`)
- test-run output, `grep` transcripts, per-acceptance-criterion walkthroughs, or reviewer disagreement
- headings, or a section per finding

Unanchored queued findings go in the body as short bullets after those sentences — one line each, no rationale essays.

Verdict:

- Any blocking finding survived triage (queued, or confirmed real even if not queued) → submit as **REQUEST_CHANGES** automatically and tell the user why.
- Otherwise → ask the user (AskUserQuestion): **COMMENT** or **APPROVE**.

No PR context → skip submission; report the findings.md path and a summary table instead.

## 6. Wrap up

Report **to the user in the terminal** — this is where the process detail belongs, and the only place it belongs: reviewer count and tier, findings by label, raw-vs-deduped counts, what was queued/skipped/submitted, the verdict, and the findings.md path. Be as thorough here as useful; none of it goes to GitHub.

## Reuse — the embedded reviewer pass

`/work`, `/implement` and `/bugfix` run ONLY steps 2–3 (with 3b) of this skill — **including the classifier and the selection rules**: a ui-only ticket gets codebase + qa (or `light.md`), not the four-way fan-out; callers may add dimensions the flags missed, never drop selected ones. Findings are written under `~/.agents/scratch/<slug>/review/`, then deduped and verified. Real issues get FIXED as part of the work rather than triaged or published; debatable ones go to the user; anything the code disproves is dropped. No GitHub, no interactive loop. The caller supplies two things in the context block: the diff command (its uncommitted changes) and the requirements sources for the QA/light reviewer.
