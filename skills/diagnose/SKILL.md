---
name: diagnose
description: "Disciplined debugging for hard bugs and performance regressions: build a fast feedback loop first, reproduce, find the root cause, fix it with a regression test. Use when the user says /diagnose, 'debug this', or reports something broken or slow."
---

# Diagnose

Fix the fault, not the place it surfaced. The symptom is where a wrong state became visible. The root cause is the first place the system did something it should not, or failed to handle a state it should handle.

Redact secrets, tokens and personal data from anything you save or paste.

Outputs: `.scratch/<feature-slug>/diagnose.md` (or `.scratch/diagnose/<date>-<slug>.md` outside a feature) holding the symptom, the feedback loop command, the minimized repro, the hypotheses and what ruled each out, the root cause, and the fix. Also a regression test and an updated `STATUS.md` if one exists. Write each part as you learn it.

## 1. Build a feedback loop

Nothing else matters until you have a fast, deterministic, agent-runnable signal that shows the bug. Try these in roughly this order and use the first that works.

1. A failing test at whatever seam reaches the bug.
2. A script that hits a running server, or a CLI run on a fixture whose output you diff against a known-good one.
3. A headless browser script that drives the UI and asserts on DOM, console or network.
4. A captured request, payload or event log replayed through the code path alone.
5. A throwaway harness that runs one function with mocked dependencies.
6. For "sometimes wrong output", a loop of many random inputs.
7. For a bug that appeared between two known states, an automated bisect.
8. A diff of old-version and new-version output on the same input.
9. A script that drives a human through the steps. Last resort.

Then make the loop tighter. Make it faster, narrow it to the failing case, and for a non-deterministic bug raise the failure rate by looping, adding stress or pinning the clock and seed. If you truly cannot build a loop, say so and ask the user for what you need (a capture, access, or a way to run the code).

Stop here until the loop goes red on the bug the user described, not a nearby one.

## 2. Reproduce and minimize

Confirm the loop shows the user's symptom. Shrink the input, the config and the code path until removing anything more makes the bug vanish. The smaller the repro, the fewer hypotheses fit.

## 3. Hypothesize

List several concrete hypotheses before testing any. Each states what is wrong and what you would observe if it were true. Rank them. When something fails only after a restart, suspect persisted state first: config files, caches, lock files, serialized state.

## 4. Instrument

Test the hypotheses one at a time. One debugger breakpoint beats ten logs. Put targeted logs at the boundaries that tell hypotheses apart. Never log everything and grep. Read the actual error and the actual state, and do not guess.

## 5. Fix at the root

Ask whether the state that triggered the symptom is legitimate. If the system can be in that state, the code that broke on it is the root cause, and handling the state there is the fix. If the state should never exist, a check where it broke only hides the bug, so find what produced it. Guards, retries, swallowed errors and clamped values are the usual ways to hide a bug. If a workaround needs a paragraph of comment to justify it, fix the code.

1. Turn the minimized repro into a failing test at the right seam.
2. Watch it fail. If you forced the failure by mutating code or a fixture, diff against a clean copy to prove the mutation landed.
3. Apply the fix and watch it pass.
4. Re-run the original, unminimized loop from step 1.
5. Look for the same fault pattern elsewhere and fix every instance.

## 6. Clean up

Remove temporary logs, harnesses and scripts, or keep the useful ones as tests. State the root cause in the commit message. If finding it took a deep dig, propose the cheap, always-on signal (a log line, an assertion, a metric) that would have shown it at first look. Then run `verify`.
