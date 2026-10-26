---
name: engineering-flow
description: "The default engineering process, a pipeline of Define, Align, Design, Slice, Build and Verify. Each phase takes defined inputs, runs one skill, writes outputs to files, and ends at a gate. Use for any non-trivial feature, refactor, migration or new project, when the user says /engineering-flow or 'let's do this properly', or asks what the process is."
---

# Engineering flow

One process for non-trivial work, built as a pipeline. Each phase takes inputs, runs a skill, writes outputs to files, and ends at a gate. Do not start the next phase until the gate is met and the outputs exist.

```
(idea) -> define -> align -> design -> slice -> build -> verify -> (shipped, verified work)
```

| Phase | Skill | Input | Output | Gate |
| --- | --- | --- | --- | --- |
| 0. Define | `define` | idea, existing docs and code | `docs/project/*`, `GLOSSARY.md`, ADRs | user approves project, requirements, roadmap |
| 1. Align | `align` | a roadmap feature or request | `spec.md`, `decisions.md` | user approves spec and test seams |
| 2. Design | `design` | spec, existing code | `design.md`, `ui.md`, `ui/round-NN/` proposals, `contract.md` (UI work), ADRs | user agrees with the shape and accepts a UI proposal, clash check clean |
| 3. Slice | `slice` | spec, design, contract | `issues/NN-*.md`, `issues/README.md` | user approves tickets, every requirement covered |
| 4. Build | `build` | a ticket, or the whole graph | commits, ticket notes, `changes.md`, `orchestration.md` | criteria hold, suite green |
| 5. Verify | `verify` | built change, spec, tickets | `verify.md`, `evidence/` | evidence recorded, findings fixed |

Each skill lists its input, output and gate in its header. This file is the overview and the shared rules.

Support skills sit beside the pipeline.

| Skill | Use it when |
| --- | --- |
| `diagnose` | something is broken or slow. Replaces align and design for a bug. |
| `delegate` | a bounded task suits a cheaper, stronger or different model. `build` uses it for parallel work. |
| `handoff` | you stop, the context is long, or you switch agents or CLIs. |
| `retro` | a feature is done or a mistake repeated. Turns it into checks and rules. |
| `unslop` | you write any markdown. Required, see the rules. |

## Choose the path by size

State the size in one line, then follow the path. When unsure, take the larger one.

| Size | Example | Path |
| --- | --- | --- |
| Trivial | typo, one-line fix, config change | build, verify (a note in the reply is enough) |
| Small | bug fix, small isolated change | diagnose if it is a bug, then build, verify |
| Medium | one feature in one module | short align, design, build, verify |
| Large | several modules, migration, new subsystem | align, design, slice, build, verify |
| New project, major initiative, or first feature with a UI | a new app, a rewrite | define first, then the Large path per feature |

## Where outputs live

Every phase writes its outputs as it goes. A decision that only lives in the chat is lost.

Write every file under the workspace (the repo), never to `/tmp` or `$TMPDIR`. The workspace is a bind mount of the host folder, so it survives container restarts and rebuilds. `.scratch/` is kept out of git through the repo-local `.git/info/exclude`, so it stays on disk but is not committed.

- **Project knowledge** is committed: `docs/project/`, `docs/adr/` and `GLOSSARY.md`.
- **The accepted UI proposal** is copied to `docs/project/ui/<feature-slug>/` and committed. The rejected ones stay in `.scratch/<feature-slug>/ui/`.
- **Feature working files** are local and not committed unless the user asks: `.scratch/<feature-slug>/` holds the spec, decisions, design, tickets, evidence, handoffs and `STATUS.md`. Promote anything worth keeping to `docs/`.
- **Delegated work** is under `.scratch/delegations/<id>/`.
- **`STATUS.md`** in each feature directory records the size, whether there is a UI, the current phase, the next step, and one row per passed gate with date and outputs. Update it at every gate. Read it first when resuming.
- **Requirement IDs** (`REQ-001`) live in `docs/project/requirements.md`. Stories, tickets and tests cite them, and `verify` checks that every ID is covered.
- **ADRs** record decisions that outlive a feature, such as a stack choice or a public contract. Number them, keep them short, and never edit an accepted one. Supersede it with a new one.
- **Tickets** are one file each, numbered from `01` in dependency order, starting with `Status:`, `Blocked by:`, `Covers:` (requirement IDs) and, for UI projects, `Layer:` (`ui`, `api`, `data`, `contract`, `slice`). Status is one of `needs-info`, `ready-for-agent`, `ready-for-human`, `claimed`, `resolved`, `wontfix`.

## Projects with a UI

When the work has a user interface, the UI and the rest are decided together. If the UI is designed after the backend, or the reverse, their requirements clash and one side is rebuilt.

1. `define` runs first and fixes users, journeys, scope, vocabulary and cross-cutting rules for both sides.
2. One requirements list covers UI, API, data and operations needs, each tagged with its layer. A UI need and the backend need it implies are written in the same pass.
3. `design` derives screens and their states from the journeys, then has Codex draft several distinct UI proposals as HTML mockups. The user accepts one, or picks one as the base for another round. The contract is derived from the accepted screens, then the clash check runs. A clash is fixed by changing the requirement, the UI or the API together, and the fix is logged in `decisions.md`.
4. `slice` makes the contract ticket first. UI and backend tickets then run in parallel against stubs, and vertical slices join them.
5. `verify` runs contract tests on both sides and walks every journey through the real UI.

## Conventions

This devcontainer fixes the project setup. Skills never ask the user to configure any of it.

- **Commands.** Take build, typecheck and test commands from the repo's `AGENTS.md` or `CLAUDE.md`, then from its manifest files. If neither says, ask once.
- **Tools.** Use `rg`, `fd`, `tree`, `jq` and `git` before reading files by hand or delegating a search.
- **Models.** Route work with `delegate`: Opus for decisions and design, Sonnet for implementation, Haiku for reading and searching, Codex and Gemini for second opinions and documentation. The roles are in `delegate-roles.conf`.
- **Other CLIs.** Claude, Codex and Gemini are all installed and logged in. Skills that want an independent opinion call a CLI other than the one you are running in.

## Rules for every phase

- Do not claim a task is done without the evidence `verify` asks for. Report skipped steps as skipped.
- Decide reversible questions and note them in `decisions.md`. Confirm before irreversible or outward-facing actions such as push, publish or delete.
- Run `unslop` on every markdown file you write, whether it is for humans or LLMs: specs, designs, tickets, READMEs, skills, `AGENTS.md`, PR descriptions. Do it before you show the file.
- If a later phase shows an earlier one was wrong, go back, fix that phase's output, and log the change in `changes.md`. Do not patch around it.
- Keep `define`, `align`, `design` and `slice` in one unbroken context so the decisions build on each other. Start each `build` ticket fresh, working from the ticket and the files. If a session gets long before `slice` ends, run `handoff` at a phase boundary.
- After a feature, or a session with a repeated mistake or a surprise, run `retro`.
