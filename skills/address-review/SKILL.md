---
name: address-review
description: Close the PR feedback loop — unresolved review threads worked one by one, then teach, commit, replies.
argument-hint: "optional: PR number/URL (defaults to the current branch's PR)"
disable-model-invocation: true
model: sonnet[1m]
effort: high
---

# Address review

Turn open review feedback on a PR into fixes, replies, and resolved threads. Code changes happen in the main conversation (the user reviews each edit); fetching and digesting the threads goes to a subagent.

## 1. Locate the PR

Use the passed PR number/URL, otherwise `gh pr view` for the current branch. No PR → say so and stop. Make sure the local branch matches the PR head; if it's behind, tell the user before touching anything.

## 2. Digest the feedback (subagent)

Spawn one `context-gatherer` subagent (retrieval on `sonnet` — pin it, don't inherit) to fetch and summarize, via `gh api graphql` (`reviewThreads` with `isResolved: false`) plus `gh pr view --json reviews`:

- every unresolved thread: thread id, file and line, reviewer, what they are actually asking for, the code excerpt in question, and any replies already made;
- the overall review states (who requested changes, who approved) and CI status.

It returns a compact numbered digest — not raw JSON.

## 3. Work the threads one at a time

For each thread show: reviewer, `file:line`, their ask, the relevant code. Then ask (AskUserQuestion):

- **Fix it** → make the change here in the main conversation, honouring the reviewer's intent (if their suggestion is right in spirit but wrong in detail, fix the spirit and say so in the reply later).
- **Explain deeper** → unpack what the reviewer means and what the change would involve, then re-ask this thread.
- **Reply only** → no code change; draft a grounded reply (agreeing to defer, or respectfully disagreeing with evidence) and show it for approval before it's queued.
- **Skip** → leave the thread untouched.

## 4. Teach — before the commit

Same adaptive mechanism as `/implement`, scaled to the changes: 1–2 questions for trivial fixes, 2–4 otherwise — concrete, about what changed and why, one per addressed concern, each with a "Skip teach — commit now" escape; levels 1→3, each wrong answer simplifies the explanation. Frame it around the reviewers' concerns — after this round the user should be able to defend every fix in the PR discussion themselves.

## 5. Commit and push

Commit by loading and following `~/.agents/skills/commit/SKILL.md` (user-invoked — read the file, don't call the Skill tool), scoped to the changed paths; split into separate commits if fixes are genuinely unrelated. Then ask before pushing — replies referencing commits only make sense once they're on the remote.

## 6. Close the loop on GitHub

- Reply in every addressed thread: one or two sentences on what changed, referencing the commit hash. Post the approved reply-only drafts.
- Ask once (AskUserQuestion) whether to also mark the addressed threads as resolved (`resolveReviewThread` mutation) — teams differ on whether author or reviewer resolves.
- Offer to re-request review from whoever requested changes.

## 7. Report

Summarize: threads fixed / replied / skipped, commits made, push status, and anything still open. If new feedback lands later, re-running `/address-review` picks up only the still-unresolved threads.

If any addressed thread touched UI, run `/pr comment` afterwards: it re-takes the AFTER shots for the affected routes and posts them as one comment, so reviewers see the fix instead of re-pulling the branch.
