---
name: build
description: "Phase 4 of engineering-flow. Implement one ticket test-first at the agreed seams, or run the whole ticket graph in parallel through delegate onto an integration branch. Use when implementing from a spec or tickets, or when the user says /build, /build-all or 'implement this' or 'implement the whole spec'."
---

# Build

**Input:** one ticket (or the whole ticket graph), `spec.md`, `design.md`, `contract.md`.
**Output:** commits, the ticket's `## Notes` and `Status`, `changes.md` for any deviation, `STATUS.md`. In graph mode also an integration branch and `orchestration.md`.
**Gate:** every acceptance criterion holds, the full suite is green, the work is committed.

Choose a mode.

- **One ticket.** Build it yourself with the loop below. Use this for a single ticket, a trivial change, or when you want to drive each ticket.
- **Whole graph.** Orchestrate all tickets of the feature, in parallel where the graph allows. Read "Whole graph" at the end. The loop below is what each implementer follows.

## One ticket

### Setup

1. Pick the next ticket on the frontier, meaning one whose blockers are all `resolved`. Read the ticket, `spec.md` and `design.md`. State the ticket title before starting.
2. Set `Status: claimed` in the ticket file.
3. For UI projects, build against `contract.md`, using stubs or mocks for the other side until it lands. Do not change the contract inside a ticket.
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
2. Commit on the current branch with a message that names the ticket.
3. Append to the ticket's `## Notes`: what you did, decisions made, surprises, commit hashes. Set `Status: resolved`.
4. If building contradicts the spec, design or contract, stop. Agree the change with the user, update that document, and record it in `.scratch/<feature-slug>/changes.md` with the date, what changed and why. If the contract changed, update the tickets on both sides.
5. If context is filling up, run `handoff`. Then run `verify`.

## Whole graph

You do not write the code in this mode. You schedule tickets, brief implementers through `delegate`, check what comes back, and merge it.

### 1. Plan the run

1. Build the task graph from the tickets' `Blocked by:` lines. The frontier is every ticket whose blockers are all `resolved` and which is not `claimed`.
2. Find the check for each ticket, meaning the command that proves its acceptance criteria, from `AGENTS.md`, `CLAUDE.md` or the manifest files. A ticket with no check gets one written first, or it runs alone and you review it by hand.
3. Mark tickets that touch the same module or file (from the ticket scope and `design.md`) as conflicting. They never run at the same time.
4. Set a concurrency limit, three by default. Lower it on rate limits or a flaky CLI.
5. With a clean working tree, create the integration branch and check it out in the main working tree: `git switch -c integration/<feature-slug>`. Implementers branch from its tip, so each starts from the latest merged work.
6. Create `orchestration.md` with a table of ticket, status, delegate id, model, branch, check, merge commit and retries.

Show the user the plan before starting: the order, what runs in parallel, and the model for each ticket.

### 2. Run the frontier

For each ready ticket within the limit:

1. Set `Status: claimed` in the ticket and in `orchestration.md`.
2. Write a short brief of pointers, not copies: the paths of the spec, design, contract, the ticket, `GLOSSARY.md` and earlier commits it builds on. State the goal, the scope, what is out of bounds, the done condition, and that the implementer follows the loop above, commits, and appends to the ticket's `## Notes`.
3. Launch it in the background:

   ```
   delegate.sh implement <brief> --tag <ticket-id> --check "<check>" --allow "Bash(<test command>:*)"
   ```

   Use `--model` to put a hard ticket on a stronger model. UI work runs against `contract.md`, with stubs for the other side until it lands.
4. When a delegate finishes, handle it as below, then refill the frontier.

### 3. Check and merge each result

A delegate's report is a claim. Check the work before it reaches the integration branch.

1. Read the exit status. Exit 4 means its check failed, and 5 means the CLI failed or timed out.
2. Read the diff of its branch against the integration branch. It must stay inside the ticket scope, match `design.md`, and leave no stray files such as caches or build output. It must not edit `contract.md` or the spec. A contract change stops the run: tell the user, agree the change, update the documents, and re-brief the affected tickets.
3. Run the ticket's check yourself in its worktree.
4. Merge with `git merge --no-ff delegate/<id>` on the integration branch. Resolve a trivial conflict yourself. For a real conflict, discard the merge and run the ticket again on the new tip.
5. Run the full suite and typecheck on the integration branch. If red, find the cause from the failure log, revert the merge if needed, and re-brief the ticket with the log. After two failed attempts, set the ticket to `needs-info`, write the reason in its notes, and continue with tickets that do not depend on it.
6. Set `Status: resolved`, record the merge commit and delegate id in the ticket notes, update `orchestration.md` and the graph in `issues/README.md`, and recompute the frontier.

If a design assumption proves wrong while merging, record it in `changes.md`, stop launching tickets that depend on it, and tell the user.

### 4. Finish

1. When every ticket is `resolved`, run the full suite on the integration branch.
2. Run `verify` on the integration branch. Fix the findings in one implementer run and check again.
3. Update `STATUS.md` and `orchestration.md`, and note anything left unresolved.
4. Remove each delegate worktree (`git worktree remove`) and delete the merged `delegate/*` branches.
5. Report the integration branch, the suite result, the tickets that needed help, and the cost drivers such as retries and escalations. Do not merge into the main branch, push, or open a pull request unless the user asks.

Keep messages to and from implementers short, and point to files and commits. Never merge a branch you have not read. If the run is interrupted, `orchestration.md` and the ticket statuses are the source of truth: release stale `claimed` tickets, prune dead worktrees, and resume from the frontier.
