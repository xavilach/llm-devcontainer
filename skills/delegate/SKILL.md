---
name: delegate
description: "Hand a bounded task to another model through its CLI: Opus to decide, Sonnet to implement, Haiku to search, Codex to review, draft docs and propose UIs, Gemini to critique. Use when a task is cheaper or better done by a different model, or when the user says /delegate. Always try rg, fd and git yourself first."
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

Seven roles, set in `/etc/delegate-roles.conf` (source `images/delegate-roles.conf`). Adding one is a single line. The brief carries the task, so one role covers several jobs, and `--model` overrides the model for a single run.

| Role | CLI and model | Mode | Use for |
| --- | --- | --- | --- |
| `decide` | Claude Opus | read | A hard choice, a design sketch, a blast-radius or security read. It advises, you decide. |
| `implement` | Claude Sonnet | write | A ticket with a check that can run. Also tests, a bug repro loop, and mechanical edits (renames, codemods, migrations: add `--model claude-haiku-5-5` and always pass `--check`). |
| `search` | Claude Haiku | read | Reading many files, logs, diffs or threads and reporting what matters, with `file:line`. |
| `review` | Codex | read | An independent review of a diff against the spec. `verify` uses it. |
| `critique` | Gemini | read | An adversarial read of a spec, design or plan. Also huge inputs (a whole repo or a long log), because Gemini has a large context window. |
| `docs` | Codex | write | Drafts of README, API and how-to text, PR descriptions and changelog entries, written to files. |
| `ui-proposals` | Codex | write | One distinct UI direction as a static HTML mockup with notes. `design` runs several in parallel. |

Rules of thumb:

- Escalate up for judgment, down for volume. Match the work to the lowest model that can do it, then check the result.
- Take a second opinion from a vendor other than the one that wrote the work: `review` or `critique` on Claude's work, a Claude role on Codex's or Gemini's. If you already run on Opus, do `decide` yourself.
- Do not delegate approvals, specs that need the user's answers, irreversible actions, or anything where writing the brief takes longer than the task.
- Independent tasks can run in parallel. Each write task gets its own worktree, so they do not collide.

## 3. Write the brief

The delegate sees only the brief and the files it is given. Make it standalone, in a file under `.scratch/`, such as `.scratch/briefs/<name>.md`. Never use `/tmp`, which is lost on restart. Name the input files in the brief with the same relative paths you pass to `--input`.

```
Goal: <one sentence>
Context: <what it needs to know, with paths to the spec, design, contract and ticket>
Scope: <files or directories it may read or change>
Do not: <what is out of bounds>
Done when: <observable condition>
Output: <the shape of the final message, for example a list of file:line with one sentence each>
```

## 4. Run it

```
delegate.sh <role> .scratch/briefs/<name>.md [options]
```

| Option | Meaning |
| --- | --- |
| `--input <path>` | Copy a file or directory into the delegate's working tree at the same relative path (repeatable). **Required for anything under `.scratch/`**, which git ignores, and for any file with uncommitted changes. Copies are read-only references and are never part of the delegate's commit, even when the path is tracked. |
| `--setup "<cmd>"` | Run before the CLI starts, for example `npm ci`. A fresh worktree has no installed dependencies. Files setup creates are kept out of the delegate's commit unless the delegate changed them. |
| `--check "<cmd>"` | Run on the finished work. Exit 4 if it fails. For a write role it runs in a fresh checkout of the committed result, with `--setup` run there again, so it validates exactly what would be merged. |
| `--allow "<tool>"` | Extra tool for a Claude delegate (repeatable), for example `"Bash(npm test:*)"`. Headless runs cannot ask, so anything not allowed is denied. Allow the narrowest command that works. Ignored, with a warning, for other CLIs. |
| `--scope <pathspec>` | A write role may only change matching paths (repeatable). Exit 7 if it touches others. |
| `--tag <name>` | Name added to the run ID, such as a ticket ID. Parallel runs are safe: each has its own worktree and branch. |
| `--model <id>` | Override the model in the roles file. |
| `--budget <usd>` | Spend cap. Claude only; other CLIs have none, so the script exits 2 rather than pretend. |
| `--timeout <s>`, `--check-timeout <s>` | Limit for the CLI (default 900, killed 30 s later) and for setup and check (default 600). |

- Run it from inside the git repo. In `.scratch/delegations/<id>/` the brief, `result.md`, logs and `changed-files.txt` belong to the wrapper. Everything the delegate can write is under `<id>/jail/`: the worktree on branch `delegate/<id>`, the snapshot, the check checkout and a scratch HOME. A delegate can therefore never plant a link where the wrapper writes.
- A write role works from the `HEAD` that was current when the run started, resolved once, so a merge during the run cannot skew the diffs. Uncommitted changes in your working tree are not in its worktree. A Codex read role works on a copy of the project as it is now, uncommitted and untracked files included.
- The wrapper commits a write role's result on the delegate branch, without running project hooks. Tell the delegate not to commit.
- Exit codes: 3 the CLI is not installed or Codex cannot be confined, 4 check failed, 5 the CLI failed or timed out, 6 a write role changed no files, 7 changes outside `--scope`, 8 setup failed, 9 commit failed or the worktree was tampered with, 10 the working tree could not be prepared. On 3 or 5 do the task yourself or retry. Do not block on a delegate. A failed write run keeps its worktree and branch and prints the command to discard them.

## 5. Review before using

A delegate's report is a claim, not evidence.

- For read roles, spot-check the findings. Open two or three of the cited `file:line` references with `rg` or `bat`.
- For `implement`, read the diff with `git diff HEAD...delegate/<id>`, run the real checks, then merge or cherry-pick.
- For `docs`, run every command and snippet it wrote, check each claim against the code, then run `unslop`. A model drafting docs only knows what it read.
- Look at the diff stat for stray files such as caches or build output.
- Clean up one run by hand: `git worktree remove --force <path>` (setup leaves untracked files such as `node_modules` that make a plain remove refuse), `git branch -D delegate/<id>`, then `git worktree prune`.
- Then continue with `verify` as usual. Delegation does not replace it.

## 6. Clean up old runs

Runs pile up in `.scratch/delegations/`: read runs keep their brief and result, write runs keep a worktree and a `delegate/<id>` branch. Remove the old ones with:

```
delegate.sh --gc                                   # report only, deletes nothing
delegate.sh --gc --older-than 14 --apply           # delete the safe runs older than 14 days
delegate.sh --gc --apply --include-unmerged        # also discard runs with unmerged work
```

A run is removable when it is older than the limit (7 days by default, and never under one hour) and nothing in it would be lost:

- its branch, if it has one, is merged into `HEAD`, was never committed, or its commits change nothing;
- every worktree under the run is on a merged or empty commit, so a worktree you detached and committed in is protected;
- a run that never finished (no `changed-files.txt`, for example after a timeout) has no uncommitted work left in its worktree.

Everything else is protected and only listed. A run whose `delegate.sh` process is still alive is skipped. Just before removing a run the command checks it again, and deletes the branch only if it still points at the commit it judged, so work committed during the scan is not lost.

- Squash-merged and rebase-merged branches look unmerged, so they stay protected. Check the merge, then use `--include-unmerged`.
- Only valid run directories in this repo's `.scratch/delegations/` are touched. A symlinked `.scratch` or `delegations`, or a symlinked run entry, is refused or ignored.
- Use `--include-unmerged` only when you have decided to throw that work away.

## Limits

- **The jail.** Whenever bubblewrap works, Codex runs in a jail, and so do the `--setup` and `--check` commands of every CLI, because they run code the delegate may have written. The root is read-only. `$HOME`, `/tmp`, `/run`, the shell history, and the `.scratch/` of the project and of every ancestor (other delegations and their copied logins) are replaced by empty directories, which hides every CLI's credentials and forwarded agent sockets. Only the run's `jail/` directory is writable. The project root may not contain `$HOME`.
- **What the jail does not do.** The network stays open, because the CLIs need their APIs (the container firewall still applies), so a delegate can send anything it can read to an allowed host. The whole repository is readable, including `.env` files and any remote URL with a token in `.git/config`: keep secrets out of the repo.
- **Without bubblewrap**, setup and check still run with a scrubbed environment and a scratch HOME, but unconfined, and Codex is refused (exit 3) unless `DELEGATE_ALLOW_UNSANDBOXED=1`, which lets it reach anything the `node` user can.
- **Codex** runs with a scrubbed environment (no `GH_*`, no git credential helper), a throwaway `CODEX_HOME` holding only its own login (never `config.toml`, which can carry MCP servers or hooks), and its own sandbox off, because the jail confines it.
- **Claude** has Bash disallowed in every role unless `--allow` adds a Bash rule. Claude Code auto-allows some read-only commands and `acceptEdits` auto-approves file commands such as `mv` and `rm`. Read roles get Read, Grep and Glob; write roles add Edit and Write. Whatever `--allow` adds, such as the test suite, runs with the full permissions of the `node` user and can edit and run project scripts, so keep it narrow and review the diff.
- **Credentials for Claude and Gemini** are masked against accidents: no token variables, an empty global git config and an empty `gh` config directory, so a stray push has no credentials. A command that reads the credential files by path is not stopped. Gemini write roles auto-approve edits.
- **The wrapper's git** uses a pinned git directory, no hooks or fsmonitor, literal pathspecs and no global or system config, and it refuses to commit if the worktree's `.git` file changed. Filters defined in the repository's own `.git/config` are still honoured.
- **Gemini** needs headless authentication and a trusted folder. Put the key in `~/.gemini/.env` as `GEMINI_API_KEY`. `/workspace` is trusted; elsewhere, such as `/tmp`, the key is not loaded and the role exits 5 with "must specify the GEMINI_API_KEY". The role uses `gemini-3-flash-preview`: the CLI default was overloaded (503), the 2.5 models returned 404 and the Pro models need a paid key. Until it works, use a fresh Claude Opus run in place of `critique`.
- Model names go stale. If a call fails on an unknown model, update the roles file or pass `--model`. After a rebuild, run `images/delegate-smoke.sh` to catch renamed flags.
- Delegates start with no memory of this session. Anything you do not put in the brief does not exist for them.
