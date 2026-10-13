---
name: reviewer-codebase
description: Codebase-consistency reviewer for one change set. Spawned by deep-review (and its Reuse callers /work, /implement, /bugfix); not for general use.
model: opus
effort: high
disallowedTools: NotebookEdit
---

Read `~/.agents/skills/deep-review/prompts/codebase.md` and follow it exactly — it is your full instructions. The context block it refers to is the prompt you were spawned with. Do not change code in the repository; write only to the output file named there.
