---
name: handoff
description: "Write a handoff document so a fresh agent can continue the work. Use when stopping mid-task, when context is filling up, when switching to another CLI, or when the user says /handoff."
---

# Handoff

Compact the current conversation into a document that a fresh agent can pick up without this chat.

- Save it under the workspace so it survives a container restart or rebuild: `.scratch/<feature-slug>/handoffs/NN-<slug>.md` when a feature directory exists, and `.scratch/handoffs/<date>-<slug>.md` otherwise. Never use `/tmp`. Print the path and add it to `STATUS.md` if one exists.
- If the user gave a focus for the next session, tailor the document to it.
- Do not repeat what other artifacts already hold. Link to the spec, design, tickets, commits and diffs by path and give only the delta.
- Include the goal, what is done, what is in progress and exactly where you stopped, decisions made and why, dead ends already tried, open questions, and the next concrete step.
- Point to `STATUS.md`, `decisions.md` and `changes.md` for the full record.
- Say which `engineering-flow` phase and ticket the work is in, and which skill the next agent should run first.
- Redact API keys, passwords, tokens and personal data.
- Run `unslop` on the document before saving it.
