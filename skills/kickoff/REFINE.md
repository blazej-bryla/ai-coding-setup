# Refine mode — the single place its rules live

`/kickoff refine <link> [<link>…]` prepares questions for a team refinement meeting instead of tickets. Plain `/kickoff <link>` is untouched, except when it meets an issue left at `stage: refining` (§1.8). Refine mode reuses kickoff steps 1–4 with the changes below and NEVER runs step 5: no tickets, no `mode:` / `base:` decisions, no Linear sub-issues, no Herdr start request.

## 1.1 When it applies

`/kickoff refine` followed by one or more Linear links (or IDs), all handled in one run. Each issue keeps its own slug, workdir and `context.md`; the meeting page covers all of them.

## 1.2 Fetch (kickoff step 1, per link)

- **Profile once for the run:** `~/.agents/bin/wfprofile plan.grill conventions` — a `stop=` ends the run; a `note=` is said once, as in step 1.
- **One link:** exactly kickoff step 1 (direct `get_issue`, story/subtask classification, the parent-story gatherer for a subtask).
- **Several links:** spawn ONE `wf-context-gatherer` (`model: sonnet`) with all links. It returns, per issue: title, description digest, comments digest, labels, `branchName` verbatim, parent + sibling titles/statuses for subtasks, and the matching `~/.agents/scratch/` folders (the issue's own slug and, for a subtask, the parent's).
- Slug and workdir per issue exactly as step 1 (task-key rule on `branchName`, `~/.agents/scratch/<slug>/`, created if missing).

## 1.3 Resume (per issue)

| `context.md` stage | Action |
|---|---|
| `grilled` | skip the issue, say so in one line |
| `refining` | continue: only questions not yet put to the user |
| `draft` | go to §1.5 |
| none | §1.4 |

A question counts as "put to the user" when it is under `## Refinement questions`, or its answer is already settled in `context.md`.

## 1.4 Explore and draft (kickoff step 3, per issue)

Spawn `wf-explore` (`model: sonnet`) per issue, in parallel when there are several (one message, several calls). Besides the usual synthesis, ask each for **facts that already answer likely questions**: one line per fact, each ending in `path:line`.

Draft `context.md` with kickoff's step 3 template, `stage: draft`, plus a section:

```markdown
## Known from code
- <fact> — `<path:line>`
```

Paths verbatim as returned. Known-from-code facts are listed, never asked.

## 1.5 Grill (kickoff step 4, with these overrides)

- **Source:** the same `plan.grill` source as step 4 (`mine` → the `/grilling` rules; `project` → its files; `none` → the confirmation round only). The overrides below win over that source.
- **Batches:** questions in batches of 3–5, numbered, one issue at a time, highest weight first. Rollback and premortem questions apply as in step 4, under the same triggers.
- **Each question shows:**
  - category — `scope`, `edge` (edge cases), `contract` (FE/BE contract), `data` (data & migrations), `auth` (permissions), `ux` (design/UX), `deps` (dependencies on other teams), `testing` (testing & acceptance), `rollback`;
  - who it is for — `po | design | be | fe | qa | other`;
  - weight — `blocker` (blocks starting) | `estimate` (changes the estimate) | `detail`;
  - a proposed answer when a sensible default exists.
- **Answers per number, three outcomes.** The user answers in their own language; treat "don't know" / `?` as → refinement list and "skip" as → dropped, in any language:
  - an answer → settled into `context.md`;
  - "don't know" / `?` → goes to the refinement list;
  - "skip" → dropped (not asked again, not on the page).
- **Refinement-list questions are rewritten meeting-ready:** one decision per question, short, in Polish AND English, a one-line "why it matters" (PL + EN), the proposed answer (PL + EN) if any.

## 1.6 Output

Meeting data schema (`refinement.json`):

```json
{
  "meeting": {"date": "YYYY-MM-DD", "title": {"pl": "...", "en": "..."}},
  "issues": [{
    "id": "ABC-12", "url": "https://...", "title": "...",
    "summary": {"pl": "...", "en": "..."},
    "known": [{"pl": "...", "en": "...", "source": "path:line"}],
    "questions": [{
      "id": "ABC-12-q1",
      "category": "scope|edge|contract|data|auth|ux|deps|testing|rollback",
      "for": "po|design|be|fe|qa|other",
      "weight": "blocker|estimate|detail",
      "text": {"pl": "...", "en": "..."},
      "why": {"pl": "...", "en": "..."},
      "proposal": {"pl": "...", "en": "..."}
    }]
  }]
}
```

`proposal` may be `null`; `known` may be empty.

- **Each issue's `context.md`:** overwrite with what settled, keep the frontmatter, set `stage: refining`, add:

  ```markdown
  ## Refinement questions
  - `<ISSUE-ID>-q<n>` · for: <who> · weight: <weight> — <Polish text>
  ```

- **Meeting data:** `~/.agents/scratch/_refinement/<YYYY-MM-DD>/refinement.json` (all issues of this run, schema above). Then:

  ```bash
  ~/.agents/bin/refine-html ~/.agents/scratch/_refinement/<date>/refinement.json ~/.agents/scratch/_refinement/<date>/refinement.html
  ```

  It prints `ok: <out.html> (<n> issues, <m> questions, ui: en,pl)` (or `ui: en`); anything else → fix the JSON and re-run. Never write either file inside a repo.

- **UI strings:** the page's own labels (buttons, filters, badges, section titles, empty states, confirm texts) are not in the template. They live in `skills/kickoff/refine/ui-en.json` (required) and `ui-pl.json` (optional, private — not exported), flat `{"key": "text"}` with identical keys; `refine-html` checks the keys match and inlines them. Both files → PL | EN switch, Polish by default, content from the data's `pl` / `en`; only `ui-en.json` → no switch, English UI and the data's `en` texts.

## 1.7 Wrap up

- Report per issue: answered / for refinement / known from code / dropped (counts), then the HTML path, then one line: "To share on claude.ai: upload refinement.html there and ask to publish it as an artifact."
- Then ONE question: ask the user, in their language, whether they want to post these questions anywhere before the meeting (e.g. a Linear comment); default no. No / no answer → done. Yes → show the exact text per issue and the target; post only after a second explicit yes. No other writes to Linear, ever.

## 1.8 After the meeting

Plain `/kickoff <link>` on an issue with `stage: refining`: ask the user to paste the page's **Copy answers** markdown (or `none`). Its format:

```
# Refinement answers <date>
## <ISSUE-ID>
- [<question id>] answered: <answer>
- [<question id>] open
- [<question id>] skipped
```

Fold `answered` items into `context.md`, move `open` ones into `## Open questions`, drop `skipped` ones, remove `## Refinement questions`; then continue with kickoff step 4 (at least the confirmation round) → `stage: grilled` → step 5 as usual.
