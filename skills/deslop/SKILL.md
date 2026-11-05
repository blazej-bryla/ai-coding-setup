---
name: deslop
description: Simplify the current branch's changes without changing their behaviour — inline trivial helpers, drop speculative and defensive code; significant removals are proposed one at a time; then teach and commit.
argument-hint: "optional: paths to narrow the scope"
disable-model-invocation: true
model: sonnet
effort: high
---

# Deslop

Adapted from earendil-works/pi, MIT.

Simplify what this branch added or changed, keeping its intended behaviour. Aim for a direct, coherent design that is easy to change — not the smallest diff. Resolve `~` to the absolute home directory before using paths in tools.

**Feedback mid-run.** Say first whether you agree or disagree, then what you changed.

**Cold reader** — every question or gate message to the user follows the Cold reader rule in `~/.agents/skills/_shared/CONTEXT.md` (one or two lines of state — task, ticket, what happened since their last message — then the question; the reply is as big as the question).

## 1. Scope

Base branch as in `~/.agents/skills/_shared/IDENTITY.md` (`$WT_BASE`, else the branch `origin/HEAD` points to, else `~/.agents/bin/wtconf -v WT_BASE_BRANCH`) — never assume a branch name. Profile: `~/.agents/bin/wfprofile conventions` once — a `stop=` ends the run; the files it lists (or the worker contract `~/.agents/projects/<name>.md`) are the conventions the result must still follow.

Scope = `git diff $(git merge-base <base> HEAD)` (committed and uncommitted) plus untracked files from `git status`, narrowed to the paths passed as argument — and the nearby code needed to simplify that coherently. No unrelated cleanup: something worth fixing outside the scope goes into the report, untouched.

Read every affected file in full before editing it — never edit from search snippets. Know the invariants, call sites, tests and public API around each change first.

## 2. What to simplify

- abstractions without a clear job, or that don't reduce real complexity;
- trivial single-use helpers, wrappers, adapters and pass-through layers that hide what happens — inline them;
- duplicated logic — keep one copy at the existing layer where it belongs;
- speculative options, configuration, extension points and generic machinery with no current requirement;
- defensive checks inside trusted code — validate at real trust boundaries only (user input, wire data, external APIs) and rely on types and established invariants inside;
- fallbacks for states that should be impossible — fix the invariant or the type instead;
- excess state, boolean flags, branching, indirection and special cases — rework the representation when that is clearer;
- loose types that allow invalid states (`any`, needless assertions, broad unions, optional fields for impossible states);
- comments that restate the code — keep the ones that explain why (a constraint, an intent, a non-obvious decision).

Never replace clear code with a new abstraction only to cut lines. Never remove code just because it looks unused before checking it isn't a public API, an extension point, a generated entry point or a deliberately kept compatibility surface.

## 3. Approval gate

A **significant** removal or change — anything that touches:

- user-visible behaviour or a supported workflow;
- a public API, a persisted format, protocol behaviour or backward compatibility;
- validation, auth, security checks, error handling, retries, recovery or fallbacks;
- a deliberate abstraction or extension point with several users;
- anything covered by tests or docs;
- code whose purpose or invariant is unclear —

is proposed **one at a time** via AskUserQuestion, never bundled: what you'd remove or change, why it looks unnecessary, what could break, the simpler replacement (if any), and your recommendation (first option, marked). Apply it only on an explicit yes. Unsure whether it's significant → ask.

Routine, behaviour-preserving cleanup needs no approval: inlining a trivial single-use helper, dropping a branch the types prove unreachable, a null check on a value that can't be null, removing duplication the branch itself added.

## 4. Check

Never weaken a test to make a simplification pass; change tests only when an approved behaviour change, or an equivalent cleaner structure, requires it. Run the project's check and test commands from the profile env for every side the diff touches (`~/.agents/bin/wtconf -v WT_FE_DIR WT_BE_DIR WT_FE_TEST_CMD WT_BE_TEST_CMD`; lint and typecheck as the worker contract or the conventions files list them), from the repo root, non-watch — each through `~/.agents/bin/quiet "<command>"` (one `ok:` line when green, the last 40 lines when red; `~/.agents/skills/_shared/CONTEXT.md`). Red → fix the simplification, not the test.

## 5. Finish

Re-read the final diff (`git diff`) for leftover complexity, duplication, indirection, defensive branches and accidental behaviour changes. Report:

- what was simplified (file — one line each);
- the invariants the code now relies on;
- the proposals you declined to make, or the user declined;
- the checks run and their results; anything noticed outside the scope.

Leave the changes uncommitted. Then run the teach round from `~/.agents/skills/_shared/TEACH.md` on this diff, then commit by loading and following `~/.agents/skills/commit/SKILL.md` (user-invoked — read the file, don't call the Skill tool). Deslop never commits without the teach round.
