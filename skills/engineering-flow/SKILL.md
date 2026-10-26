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
| 1. Align | `align` | a roadmap feature or request | `spec.md`, `decisions.md`, journeys (UI) | user approves spec and test seams |
| 2. Design | `design` | spec, existing code | `design.md`, `ui.md`, `ui/round-NN/` proposals, the contract (UI work), ADRs | user agrees with the shape and accepts a UI proposal, clash check evidenced |
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
| `unslop` | you write human-facing markdown. See the rules. |

## Choose the path by size

State the size in one line, then follow the path. When unsure, take the larger one. Each path has defined inputs, so no step has to invent them.

| Size | Example | Path | What stands in for the skipped steps |
| --- | --- | --- | --- |
| Trivial | typo, one-line fix, config change | build, verify | One line in the reply: the goal and the check that proves it. No spec, no ticket. |
| Small | bug fix, small isolated change | diagnose if a bug, then build, verify | The goal, the check, and the test seam, stated in the reply. For a bug, `diagnose.md`. |
| Medium | one feature in one module | short align, design, build, verify | `spec.md` with an acceptance list. `build` turns that list into ticket `01`. No contract unless an API or UI is involved. |
| Large | several modules, migration, new subsystem | align, design, slice, build, verify | Everything. |
| New project, major initiative, or first feature with a UI | a new app, a rewrite | define first, then the Large path per feature | Everything. |

Add the base commit, the commit setting and the subagent setting (see below) to `STATUS.md` for any path that has one. Depth scales with size: the second design alternative, the proof ladder and a multi-proposal UI round are Large-path tools. Medium work gets the short version.

## Where outputs live

Every phase writes its outputs as it goes. A decision that only lives in the chat is lost.

Write every file under the workspace (the repo), never to `/tmp` or `$TMPDIR`. The workspace is a bind mount of the host folder, so it survives container restarts and rebuilds. `.scratch/` is kept out of git through the repo-local `.git/info/exclude`, so it stays on disk but is not committed.

- **Committed project knowledge:** `docs/project/` (project, requirements, journeys, roadmap, project decisions), `docs/adr/`, `GLOSSARY.md`, the contract at `docs/project/contracts/<feature-slug>.md`, and the accepted UI proposal at `docs/project/ui/<feature-slug>/`. The contract lives here because UI and backend both build against it and delegates and collaborators must be able to read it.
- **Local feature working files** under `.scratch/<feature-slug>/`: spec, `decisions.md`, design, tickets, evidence, handoffs, `STATUS.md`. Rejected UI proposals stay in `ui/`. Promote anything worth keeping to `docs/`.
- **Delegated work:** `.scratch/delegations/<id>/`.
- **Two decision logs, each with one job.** `docs/project/decisions.md` records project-level answers from `define`. `.scratch/<feature-slug>/decisions.md` records every feature-level question, answer and clash resolution. A decision that outlives the feature becomes an ADR.
- **`STATUS.md`** records the size, whether there is a UI, the base commit the feature started from, the commit setting, the current phase, the next step, and one row per passed gate with date and outputs. Update it at every gate. Read it first when resuming.
- **Requirement IDs** (`REQ-001`) live in `docs/project/requirements.md`. Stories, tickets and tests cite them, and `verify` checks that every ID is covered. Work without IDs (trivial, small) is checked against its stated goal.
- **ADRs** record decisions that outlive a feature. Number them, keep them short, and never edit an accepted one. Supersede it with a new one.
- **Tickets** are one file each, numbered from `01` in dependency order, starting with `Status:`, `Blocked by:`, `Covers:` (requirement IDs), `Touches:` (module names, used to detect conflicts) and, for UI projects, `Layer:`. Status is one of `needs-info`, `ready-for-agent`, `ready-for-human`, `claimed`, `resolved`, `wontfix`.

```
# Status: <feature>

Size: <trivial|small|medium|large>   UI: <yes|no>
Base commit: <sha>   Commits: <allowed|ask|none>   Subagents: <normal|minimal|none>
Current phase: <phase>   Next step: <one sentence>

| Phase | Gate | Date | Outputs |
| --- | --- | --- | --- |

## Open questions
## Risks
```

## Projects with a UI

When the work has a user interface, the UI and the rest are decided together. If the UI is designed after the backend, or the reverse, their requirements clash and one side is rebuilt.

1. `define` runs first and fixes users, journeys, scope, vocabulary and cross-cutting rules for both sides.
2. One requirements list covers UI, API, data and operations needs, each tagged with its layer. A UI need and the backend need it implies are written in the same pass. Every requirement traces to a journey, a system responsibility (a job, an integration, retention, an audit need) or an external consumer. A backend requirement does not need a screen.
3. Each feature adds or updates its journeys in `docs/project/journeys.md` during `align`, so later features have journeys too.
4. `design` derives screens and states from the journeys, drafts a contract skeleton from the requirements, then has Codex draft UI proposals whose mockups use data shaped like that skeleton. The user accepts one proposal, or picks one as the base for another round. The contract is then finished from the accepted screens, and the clash check runs with evidence, not assertions.
5. `slice` makes the contract ticket first. UI and backend tickets then run in parallel against stubs, and vertical slices join them.
6. `verify` runs contract tests on both sides and walks every journey cited in the spec through the real UI.

## Conventions

This devcontainer fixes the project setup. Skills never ask the user to configure any of it.

- **Commands.** Take setup, build, typecheck and test commands from the repo's `AGENTS.md` or `CLAUDE.md`, then from its manifest files. If neither says, ask once and write the answer to `STATUS.md`.
- **Tools.** Use `rg`, `fd`, `tree`, `jq` and `git` before reading files by hand or delegating a search. Stop a process by its id: `pkill -f` also matches the shell that runs it and ends your own command. If a download fails with `no route to host` for an allowed domain, run `sudo /usr/local/bin/init-firewall.sh` to re-resolve the allowlist.
- **Models.** Whether to spawn at all is decided by "Subagents and delegation" above. Route work with `delegate`: `decide` (Opus), `implement` (Sonnet), `search` (Haiku), `review` and `docs` and `ui-proposals` (Codex), `critique` (Gemini). The roles are in `delegate-roles.conf`.
- **Other CLIs.** Claude, Codex and Gemini are installed and logged in. Skills that want an independent opinion call a CLI other than the one you are running in.

## Subagents and delegation

A subagent starts cold, re-reads what you already know, and bills at the parent model's price unless you pick another. Spawn one only when it saves more than it costs. This section is the one policy. `align`, `build`, `verify` and `delegate` point here.

Two mechanisms exist. The in-session Agent tool (types `Explore`, `Plan`, `general-purpose`, with a `model` argument) is for reading and searching. `delegate.sh` is for other vendors, write roles in worktrees, and the whole-graph run.

**Do it inline** with `rg`, `fd`, `git` and direct reads when the target is findable in three searches or fewer, the task touches fewer than about five files, or the next step needs the full detail.

**Spawn** only when the work is large or noisy and only the conclusion matters, it is independent of what you do next, or a fresh or different-vendor context is the point (an independent review).

| Size | Subagents |
| --- | --- |
| Trivial, small | None, unless the user asks. |
| Medium | Inline by default. One `Explore` (Haiku) sweep if the code area is unfamiliar. One fresh-context reviewer in `verify` only for risky changes. |
| Large | Search sweeps on Haiku, two fresh-context reviewers in `verify`, whole-graph `build` when the graph has parallel tickets. |

Pick the cheapest type and model that can do the job.

| Job | Use |
| --- | --- |
| Find or read many files, report `file:line` | `Explore` with `model: haiku` |
| Sketch a design or plan | `Plan` |
| Implement a ticket with a runnable check | `delegate.sh implement` (Sonnet), or `general-purpose` with `model: sonnet` |
| Hard decision, security or blast-radius read | `decide` (Opus), only when judgment is the point |
| Independent review or critique | `delegate.sh review` or `critique` (other vendor) |

`general-purpose` on the parent model is the last resort and is never used for pure search.

How to run them:

- Write a full brief: goal, absolute paths, decisions already made, what not to touch, and the exact output wanted ("under 200 words, a list of `file:line`"). Ask for conclusions, not file dumps.
- Launch independent agents in one turn, at most three at once.
- Do not redo a subagent's work or spawn a second one for the same question. If its report is thin, read the one file it names. Continue a finished agent with SendMessage instead of starting a new one.
- Treat every report as a claim and spot-check two or three cited lines (see `delegate` section 5).
- When the user is short on usage, drop every optional spawn and say so. Record the setting in `STATUS.md` as `Subagents: normal|minimal|none`.

## Rules for every phase

- Do not claim a task is done without the evidence `verify` asks for. Report skipped steps as skipped.
- Decide reversible questions yourself, record the assumption in `decisions.md`, and keep going. Stop and ask only for irreversible, outward-facing or scope-changing decisions.
- Commits need authorization. Before the first commit of a feature, ask once whether commits are allowed on this branch, and record the answer as `Commits:` in `STATUS.md`. Without a yes, leave the work in the working tree and say so. Never push, publish or delete without being asked. The one exception is the `delegate/*` branches that `delegate.sh` creates for write roles (including UI proposals): the wrapper commits there, they are never your branch, and nothing from them reaches your branch until you merge it.
- Run `unslop` on markdown that people read or that is committed: specs, designs, the contract, ADRs, READMEs, skills, `AGENTS.md`, PR descriptions, handoffs. Tickets, `STATUS.md`, logs and briefs are working notes and need only be clear.
- If a later phase shows an earlier one was wrong, go back, fix that phase's output, and log the change in `changes.md`. Do not patch around it.
- Run the riskiest assumption as a small executable check before detailed design or slicing, not after. Prefer fast feedback over complete documents.
- Delegated work has a budget. A whole-graph run is capped at three delegate launches per ticket, and each launch has a time limit. When the cap is reached, stop and report. Do not keep retrying.
- Keep `define`, `align`, `design` and `slice` in one unbroken context so the decisions build on each other. Start each `build` ticket fresh, working from the ticket and the files. If a session gets long before `slice` ends, run `handoff` at a phase boundary.
- After a feature, or a session with a repeated mistake or a surprise, run `retro`.
