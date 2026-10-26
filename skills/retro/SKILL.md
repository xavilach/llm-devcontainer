---
name: retro
description: "Retrospective on a coding session. Finds what slowed the agent down or let mistakes through, and proposes changes to the environment (checks, docs, steering files) so the next run goes better. Use after a feature, a long session or a repeated mistake, or when the user says /retro."
---

# Retro

Improve the agent's environment, not the code from this session. The goal is that the next run, by any agent, finds things faster and makes fewer mistakes.

## 1. Read the evidence

Use primary sources for the session the user names, or the current one if none is named.

- The conversation itself, the commits and `git diff` for the session range, and the `.scratch/<feature-slug>/` artifacts.
- Session logs on this machine if you need them: Claude under `$CLAUDE_CONFIG_DIR/projects`, Codex under `$CODEX_HOME/sessions`, Gemini under `~/.gemini`.
- Find the moments that cost time or tokens: repeated searches, wrong guesses, reverted edits, failed commands, corrections from the user, review findings that should have been caught earlier.

Quote or point to the moment for every finding. Do not report a problem you cannot point to.

## 2. Look for candidates

| Category | Look for | Typical fix |
| --- | --- | --- |
| Navigation | The agent took long to find the right file, or missed a hidden dependency between files. | A pointer in `AGENTS.md` to a doc, or a short doc in `docs/`. |
| Automated checks | A mistake a linter, type check, test or filesystem check could have caught. Also a repo with no pre-commit hook and no CI job running lint, typecheck and tests. | Wire an existing check, or add one. Read the repo's own scripts and CI first, since the check may already exist but be unwired or broken. |
| Standards | A rule the reviewer in `verify` failed to enforce, or one that is wrong or unclear. | Mechanical violations (a banned API, an import shape, a file location) get a deterministic check, not a written rule. Keep written standards for judgment calls. |
| Steering files | `AGENTS.md` or `CLAUDE.md` is long, or holds instructions that belong in a check or a standard. | Move them out. Keep these files mostly as pointers. |
| No-ops | Instructions that do not change what the agent does. | Delete them. |
| Tool economy | Expensive or noisy tool calls that could be cheaper. | A narrower command, a wrapper script, output filtering. |
| Information access | A needed fact was not available, such as dev server logs or read-only access to a service. | Tee the logs to a file, add a read-only path, document where the fact lives. |
| Flow | A phase of `engineering-flow` was skipped, too heavy or too light for the size of the work. | Adjust the size rule or the gate in the skill. |

Implementation is under the most context pressure, since it explores, writes and debugs. Review has the least, since it only receives a diff. Put standards where review enforces them, not in the implementer's context.

## 3. Report

Write `.scratch/<feature-slug>/retro.md`, or `.scratch/retro/<date>.md` outside a feature. Add it to `STATUS.md`. Include a section on whether each phase produced its outputs on time, and which outputs were thin, late or never read. List the candidates in order of severity. For each one give:

- the evidence (a quote or a commit)
- the category
- the proposed change, as a concrete edit, and where it goes
- the cost of adding it, because every new instruction in a steering file is paid for on every future run

Keep the list short. Three well-evidenced changes beat fifteen guesses. Say what went well too, so the user knows what not to change.

## 4. Apply what the user approves

Make only the approved changes. Run `unslop` on every markdown file you edit or create. Commit the changes separately from feature work, with a message that starts with `retro:`.
