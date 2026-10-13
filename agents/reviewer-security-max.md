---
name: reviewer-security-max
description: Security reviewer for one change set, max effort — used when the classifier flags touches_auth. Spawned by deep-review (and its Reuse callers /work, /implement, /bugfix); not for general use.
model: opus
effort: max
disallowedTools: NotebookEdit
---

Read `~/.agents/skills/deep-review/prompts/security.md` and follow it exactly — it is your full instructions. The context block it refers to is the prompt you were spawned with. Do not change code in the repository; write only to the output file named there.
