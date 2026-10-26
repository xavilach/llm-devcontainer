---
name: delegate
description: "Hand a bounded task to another model through its CLI: Opus for decisions and design, Sonnet for implementation, Haiku for reading and searching, Codex for documentation. Use when a task is cheaper or better done by a different model, or when the user says /delegate. Always try rg, fd and git yourself first."
---

# Delegate

Route work to the model that fits it. A cheaper model saves cost on bulk reading and mechanical edits. A stronger model is worth the cost on decisions. A second vendor gives a different view. Delegation has its own cost, because the other model starts with nothing but your brief.

## 1. Try the tools first

Most "search" tasks need a command, not a model. Do these yourself and delegate only when the answer needs reading and judging many results.

- `rg -n 'pattern'` finds content. `rg -l` lists matching files, `rg -c` counts, `rg -g '*.ts'` filters by glob, `rg -w` matches whole words, `rg -U` matches across lines.
- `rg --files | rg name` or `fd name` finds files by name. `tree -L 2 -d` shows structure.
- `git log -S'symbol' --oneline` finds when a symbol appeared. `git blame -L a,b file` finds who changed a line and why.
- `jq` queries JSON. `bat` shows a file with line numbers.
- In scripts and tool calls, call `rg`, `fd` and `bat` by name. The `grep`, `find` and `cat` aliases only exist in interactive shells and take different flags.

## 2. Pick the role

Roles and models are set in `/etc/delegate-roles.conf` (source `images/delegate-roles.conf`). Adding a role is one line. Read roles never edit files. Write roles work in a git worktree on their own branch.

**Judgment** (strongest model, advises only)

| Role | Model | Use for |
| --- | --- | --- |
| `decide` | Claude Opus | A hard choice between options, with trade-offs and a recommendation. |
| `design` | Claude Opus | Type and module sketches, boundary questions, blast-radius analysis. |
| `security` | Claude Opus | A security read of a diff or design: trust boundaries, input handling, secrets, permissions. |

**Second opinion** (a different vendor from the one that wrote the work)

| Role | Model | Use for |
| --- | --- | --- |
| `review` | Codex | Independent code review of a diff against the spec. This is `verify` step 3. |
| `critique` | Gemini | Adversarial reading of a spec, design or plan: gaps, hidden assumptions, missing cases. |

**Building**

| Role | Model | Mode | Use for |
| --- | --- | --- | --- |
| `implement` | Claude Sonnet | write | A ticket with clear acceptance criteria and a check that can run. |
| `tests` | Claude Sonnet | write | Tests for existing behavior at an agreed seam, or a regression test for a known bug. |
| `diagnose` | Claude Sonnet | write | Building the repro and feedback loop for a bug, so you can reason about the cause. |
| `mechanical` | Claude Haiku | write | Renames, codemods, format or API migrations, repeated edits. Always pass `--check`. |

**Reading and summarizing**

| Role | Model | Use for |
| --- | --- | --- |
| `search` | Claude Haiku | Reading many files and reporting what matters, with `file:line`. |
| `summarize` | Claude Haiku | Logs, long documents, PR threads, diffs, session transcripts. |
| `longctx` | Gemini | Input too big for the others, such as a whole repo or a huge log. Gemini's strength is a large context window. |

**UI design**

| Role | Model | Use for |
| --- | --- | --- |
| `ui-proposals` | Codex (OpenAI) | One distinct UI direction as a static HTML mockup with notes (write). `design` runs several in parallel and the user chooses. |

**Writing for people**

| Role | Model | Use for |
| --- | --- | --- |
| `docs` | Codex | A draft of README, API or how-to text for code that already exists (write). |
| `writeup` | Claude Haiku | PR descriptions, commit messages, changelog and release notes from a diff. |

Rules of thumb:

- Escalate up for judgment, down for volume. Match the work to the lowest model that can do it, then check the result.
- Pick a second-opinion role from a vendor other than the one that wrote the work. Use `review` or `critique` on Claude's work, and a Claude role on Codex's or Gemini's. If you already run on Opus, do `decide` and `design` yourself.
- The delegate advises on `decide` and `design`. You and the user make the decision.
- Do not delegate approvals, specs that need the user's answers, irreversible actions, or anything where writing the brief takes longer than the task.
- Independent tasks can run in parallel. Each write task gets its own worktree, so they do not collide.

## 3. Write the brief

The delegate sees only the brief and the repo. Make it standalone, in a file under `.scratch/`, such as `.scratch/briefs/<name>.md`. Never use `/tmp`, which is lost on restart.

```
Goal: <one sentence>
Context: <what it needs to know, with paths to the spec, design and ticket>
Scope: <files or directories it may read or change>
Do not: <what is out of bounds>
Done when: <observable condition>
Output: <the shape of the final message, for example a list of file:line with one sentence each>
```

## 4. Run it

```
delegate.sh <role> .scratch/briefs/<name>.md [--check "<command>"] [--allow "<tool>"]... [--tag <name>] [--model <id>] [--timeout <seconds>]
```

- Run it from inside the git repo. Output goes to `.scratch/delegations/<id>/`: the brief, `result.md`, logs, and for write roles a worktree on the branch `delegate/<id>`.
- `--check` runs a command in the worktree after the delegate finishes. The script exits 4 if it fails.
- `--tag` adds a name, such as a ticket ID, to the run ID so parallel runs are easy to tell apart. Parallel runs are safe because each has its own worktree and branch. `build` uses this in whole-graph mode.
- `--allow` gives a Claude delegate a tool it would otherwise be denied, because headless runs cannot ask. A write delegate that must run tests needs one, for example `--allow "Bash(npm test:*)"`. Allow the narrowest command that works. Codex runs commands in its own sandbox. Gemini needs no flag for edits but cannot run shell commands unprompted.
- Exit 3 means that CLI is not installed, and 5 means it failed or timed out. In both cases do the task yourself or retry. Do not block on a delegate.

## 5. Review before using

A delegate's report is a claim, not evidence.

- For read roles, spot-check the findings. Open two or three of the cited `file:line` references with `rg` or `bat`.
- For `implement`, read the diff with `git diff HEAD...delegate/<id>`, run the real checks, then merge or cherry-pick. The branch commit is the delegate's, so the diff against `HEAD` is the full change.
- For `docs`, run every command and snippet it wrote, check each claim against the code, then run `unslop`. A model drafting docs only knows what it read.
- Look at the diff stat for stray files. A delegate that ran a program may have left caches or build output on its branch.
- Clean up when done: `git worktree remove <path>` and `git branch -D delegate/<id>`.
- Then continue with `verify` as usual. Delegation does not replace it.

## Limits

- Write mode isolates by working directory and branch, not by a sandbox. Codex runs with its own sandbox off, because the sandbox cannot start in this container. The container is the boundary, and Codex read roles run in a throwaway worktree that is discarded. Claude and Gemini rely on their own permission modes. Write briefs that name the scope.
- Gemini needs headless authentication and a trusted folder. Put the key in `~/.gemini/.env` as `GEMINI_API_KEY`. `/workspace` is trusted; in an untrusted directory such as `/tmp` the key is not loaded and the role exits 5 with "must specify the GEMINI_API_KEY". The roles use `gemini-3-flash-preview`: the CLI default was overloaded (503), the 2.5 models returned 404, and the Pro models need a paid key. Retry later or change the model in the conf file if a call fails. Until then use a Claude or Codex role for the same job: `critique` becomes a fresh Claude Opus run, and `longctx` becomes a `search` split into parts.
- Model names go stale. If a call fails on an unknown model, update the conf file or pass `--model`.
- Delegates start with no memory of this session. Anything you do not put in the brief does not exist for them.
