---
name: build
description: "Phase 4 of engineering-flow. Implement one ticket test-first at the agreed seams, or run the whole ticket graph in parallel through delegate onto an integration branch. Use when implementing from a spec or tickets, or when the user says /build, /build-all or 'implement this' or 'implement the whole spec'."
---

# Build

**Input:** one ticket or the whole ticket graph; `spec.md` and `design.md` when they exist; for UI work the contract at `docs/project/contracts/<feature-slug>.md`. Paths that skip `slice` have no ticket, see "No ticket" below.
**Output:** commits, the ticket's `## Notes` and `Status`, `changes.md` for any deviation, `STATUS.md`. In graph mode also an integration branch and `orchestration.md`.
**Gate:** every acceptance criterion holds, the full suite is green, and the work is committed if commits are authorized (`Commits:` in `STATUS.md`).

Choose a mode.

- **One ticket.** Build it yourself with the loop below. Use this for a single ticket, a trivial change, or when you want to drive each ticket.
- **Whole graph.** Orchestrate all tickets of the feature, in parallel where the graph allows. Read "Whole graph" at the end. The loop below is what each implementer follows.

## One ticket

### No ticket

Trivial and small work has no spec or ticket. State the goal, the check that proves it (a failing test or a command), and the test seam in one short message. Skip setup steps 1, 2 and 4, which need a ticket and a spec. A trivial change (a typo, a config value, a rename) is an edit followed by running the check: the red-green loop applies when behavior changes. Medium work has a `spec.md` but skipped `slice`: create `issues/01-<slug>.md` from its Acceptance list, with `Covers:` filled in, and treat it as the ticket.

### Setup

1. Pick the next ticket on the frontier, meaning one with `Status: ready-for-agent` whose blockers are all `resolved`. Read the ticket, `spec.md` and `design.md`. State the ticket title before starting.
2. Set `Status: claimed` in the ticket file.
3. For UI projects, build against the contract, using stubs or mocks for the other side until it lands. Do not change the contract inside a ticket.
4. Confirm the test seams from `spec.md`. If a ticket needs a seam that was not agreed, ask before writing the test.

### The loop

Work in vertical slices. One behavior goes through red, green, then the next. Never write all the tests first.

1. **Red.** Write one failing test at an agreed seam. Run it and watch it fail for the right reason.
2. **Green.** Write only the code that passes it. Do not add behavior no test asks for.
3. **Repeat** for the next behavior. Each test responds to what the last cycle taught you.
4. **Refactor** only when the tests are green, and keep the tests green throughout.

Run the typecheck often, single test files while working, and the full suite once at the end.

A good test checks behavior through the public interface, so a refactor that keeps behavior does not break it. It reads like a specification, for example "a user can check out with a valid cart". Its expected value comes from an independent source such as a literal, a worked example or the spec, because a test that recomputes the value the way the code does can never fail. Mock only at system boundaries you do not control, not the module's own collaborators, and do not call private methods or check results through a side channel such as querying the database directly.

Check each unit before starting the next. A break caught at the unit that caused it is cheap to find, and a break found after a batch is buried. In a sweep or a run of similar edits, bracket each change with the check: known-good state, one change, run the check, continue. Order commits so the sequence reads as an argument, for example the failing test first, then the fix. Subtract before you add: remove dead code and redundant checks before building on top of them.

### Finish

1. Confirm every acceptance criterion holds and the suite is green.
2. If `STATUS.md` says `Commits: allowed`, commit on the current branch with a message that names the ticket. If it records nothing, ask once and write the answer to `STATUS.md` (or, for work without a feature directory, just remember it for the session). `Commits: ask` and `Commits: none` both mean do not commit: leave the changes in the working tree and say so, and `verify` will diff the working tree.
3. Append to the ticket's `## Notes`: what you did, decisions made, surprises, commit hashes. Set `Status: resolved`. With no ticket and no feature directory (trivial and small work), skip the ticket and `STATUS.md` bookkeeping and report the edit and the check result in your reply.
4. If building contradicts the spec, design or contract, stop. Agree the change with the user, update that document, and record it in `.scratch/<feature-slug>/changes.md` with the date, what changed and why. If the contract changed, update the tickets on both sides.
5. If context is filling up, run `handoff`. Then run `verify`.

## Whole graph

You do not write the code in this mode. You schedule tickets, brief implementers through `delegate`, check what comes back, and merge it.

### 1. Plan the run

1. Build the task graph from the tickets' `Blocked by:` lines. The frontier is every ticket with `Status: ready-for-agent` whose blockers are all `resolved`. A ticket moves `ready-for-agent`, then `claimed`, then `resolved`, or to `needs-info` when it fails twice. Only the user (or you, after fixing the cause and telling the user) sets a `needs-info` ticket back to `ready-for-agent`. `resolved`, `wontfix` and `needs-info` tickets are never launched.
2. Find the commands, from `AGENTS.md`, `CLAUDE.md` or the manifest files: the setup command (installing dependencies), the typecheck command, the test command, and for each ticket the check that proves its acceptance criteria. A ticket with no check gets one written first, or it runs alone and you review it by hand. A fresh worktree has no installed dependencies, so the setup command is passed to every delegate.
3. Mark tickets whose `Touches:` lines share a module as conflicting. They never run at the same time. A ticket with no `Touches:` line conflicts with everything.
4. Set a concurrency limit, three by default. Lower it on rate limits or a flaky CLI. Set a launch budget of three delegate launches per ticket and record it in `orchestration.md`. When it is spent, stop launching and report.
5. Whole-graph mode makes commits, so `STATUS.md` must say `Commits: allowed`. Ask once if it does not.
6. With a clean working tree (implementers branch from the committed tip, so uncommitted changes are invisible to them), create the integration branch and check it out in the main working tree: `git switch -c integration/<feature-slug>`. Implementers branch from its tip, so each starts from the latest merged work.
7. Create `orchestration.md` with a table of ticket, status, delegate id, model, branch, check, merge commit and retries.

Show the user the plan before starting: the order, what runs in parallel, and the model for each ticket.

### 2. Run the frontier

For each ready ticket within the limit:

1. Set `Status: claimed` in the ticket and in `orchestration.md`.
2. Write a short brief of pointers, not copies: the paths of the spec, design, contract, the ticket and `GLOSSARY.md`. State the goal, the scope, what is out of bounds, the done condition, and that the implementer follows the loop above. Tell it not to commit and not to edit the ticket file: the wrapper commits, and its final message is the ticket note. The orchestrator is the only writer of tickets, `orchestration.md` and `STATUS.md`, so parallel delegates cannot collide.
3. Launch it in the background:

   ```
   delegate.sh implement <brief> --tag <ticket-id> --setup "<setup command>" \
     --input .scratch/<feature-slug>/spec.md --input .scratch/<feature-slug>/design.md \
     --input .scratch/<feature-slug>/issues/<NN>-<slug>.md --input docs/project/contracts/<feature-slug>.md \
     --scope <paths of the modules named in Touches:> \
     --allow "Bash(<test command>:*)" --allow "Bash(<typecheck command>:*)" \
     --check "<check>" --budget <usd>
   ```

   `Touches:` holds module names, so map each one to its source directory and its test paths (a test-first implementer writes both) for `--scope`. `--budget` is enforced for Claude delegates only. The `--input` flags matter: `.scratch/` is git-ignored, so the delegate's worktree does not have those files unless they are copied in, and they arrive read-only. Use `--model` to put a hard ticket on a stronger model. UI work runs against the contract, with stubs for the other side until it lands.
4. When a delegate finishes, handle it as below, then refill the frontier.

### 3. Check and merge each result

A delegate's report is a claim. Check the work before it reaches the integration branch.

1. Read the exit status. Exit 3 means the CLI or the Codex jail is unavailable, 4 its check failed, 5 the CLI failed or timed out, 6 a write role changed no files, 7 it changed files outside `--scope`, 8 setup failed, 9 the wrapper commit failed, 10 the working tree could not be prepared. A failed run keeps its worktree and branch and prints the command to discard them.
2. Read `changed-files.txt` and the diff of its branch against the integration branch. It must stay inside the ticket scope, match `design.md`, and leave no stray files such as caches or build output. It must not edit the contract or the spec. A contract change stops the run: tell the user, agree the change, update the documents, and re-brief the affected tickets.
3. Read the wrapper's check result. `delegate.sh --check` already ran the check on a clean checkout of the commit, with setup rerun, so do not run it again in the worktree: that tree holds setup files the commit does not. Run the full suite once on the integration branch after the merge (step 5).
4. Merge with `git merge --no-ff delegate/<id>` on the integration branch. Resolve a trivial conflict yourself. For a real conflict, discard the merge and run the ticket again on the new tip.
5. Run the full suite and typecheck on the integration branch. If red, find the cause from the failure log, revert the merge if needed, and re-brief the ticket with the log. After two failed attempts, set the ticket to `needs-info`, write the reason in its notes, and continue with tickets that do not depend on it.
6. Set `Status: resolved`. Write the delegate's `result.md` into the ticket's `## Notes` yourself, with the merge commit and delegate id, update `orchestration.md` and the status column of `issues/README.md`, and recompute the frontier.

If a design assumption proves wrong while merging, record it in `changes.md`, stop launching tickets that depend on it, and tell the user.

### 4. Finish

1. When every ticket is `resolved`, run the full suite on the integration branch.
2. Run `verify` on the integration branch. Fix the findings in one implementer run and check again.
3. Update `STATUS.md` and `orchestration.md`, and note anything left unresolved.
4. Remove each delegate worktree and delete its branch. Use `git worktree remove --force <path>`, because setup leaves untracked files such as `node_modules` that make a plain remove refuse. Then `git worktree prune`. Tickets that failed keep their worktrees until you have read them.
5. Report the integration branch, the suite result, the tickets that needed help, and the cost drivers such as retries and escalations. Do not merge into the main branch, push, or open a pull request unless the user asks.

Keep messages to and from implementers short, and point to files and commits. Never merge a branch you have not read. If the run is interrupted, `orchestration.md` and the ticket statuses are the source of truth: release stale `claimed` tickets, prune dead worktrees, and resume from the frontier.
