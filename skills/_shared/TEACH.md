## 5. Teach — always before any commit

Never commit without this step. It also applies to intermediate commits: each commit is preceded by a teach round covering the changes since the last commit.

Open with a **diff brief**: 3–6 lines, so the user sees the change before being quizzed on it. Write the brief as problem → a concrete example or short trace → the solution, and say which parts are necessary and which are optional. Then quiz until they can defend it:

- 2–4 questions (1–2 when the diff is trivial) via AskUserQuestion, one at a time — concrete, about THIS diff ("why did the new query go through X instead of Y?", "what happens now when <edge case>?"). Multiple-choice with plausible distractors; every question carries a **"Skip teach — commit now"** option, and stop/skip at any point ends teach immediately.
- Explanation level, starting at 1: **Level 1** terse, expert-to-expert; **Level 2** plain language, data flow step by step; **Level 3** first principles: analogies, a traced example with real values, no jargon.
- Correct → confirm briefly, next question. Wrong → level +1, re-explain at the new level, re-ask differently; stay at the raised level for the rest of the round.
- End with a 2–3 sentence recap at the level you finished on.

