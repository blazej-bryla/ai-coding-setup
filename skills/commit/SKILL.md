---
name: commit
description: One clean commit — explicit paths, terse 2–4 line message from a haiku subagent, no attribution.
argument-hint: "optional: paths or a scope hint"
disable-model-invocation: true
effort: low
---

# Commit

Make one clean commit of the work at hand. Deliberately no `model:` pin in this skill — a pin would switch the calling conversation's model for the rest of the turn; the cheap model lives in a subagent instead.

## 1. Stage deliberately

Run `git status` first. Stage explicit paths — the files belonging to the current piece of work (or the paths passed as args). Never blind `git add -A`: leave out unrelated edits, generated artifacts, and `~/.agents/scratch/` (it should be gitignored anyway). If staged-vs-unstaged looks ambiguous, show the user what you intend to include and confirm. If the index already holds a squash-merge (the caller — /work or /bugfix — merged a worker branch), keep that staging as-is: confirm with `git status` that only the expected paths are staged, and do not re-stage or unstage anything.

## 2. Generate the message (haiku subagent)

If the staged diff is tiny (roughly ≤ 20 lines) and you already know it from this conversation, write the message yourself to the same standard and skip the subagent — the spawn costs more than it saves. Otherwise spawn a subagent with `model: haiku` that runs `git diff --staged --stat`, `git diff --staged`, and `git log --oneline -10` (to match the repo's message style), then returns ONLY the commit message:

- Subject line: imperative, ≤72 chars, says what the change does.
- Then 1–3 short body lines: what changed and why — only what the diff can't say itself.
- 2–4 lines total, every line carrying information a reader of `git log` needs. No Claude/session/tool mentions of any kind.

## 3. Sanity-check and commit

Read the message against the staged diff yourself — if it's inaccurate or padded, fix it directly rather than re-spawning. Commit with no extra trailers (attribution is disabled globally; keep it that way). Report the short hash and the message. Amending — only an unpushed commit (`git branch -r --contains HEAD` empty), because the caller asked or the change belongs to that commit — is said explicitly in the report: `amended <old-hash> → <new-hash>`. Never amend a pushed commit. Do not push unless asked.
