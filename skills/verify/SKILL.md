---
name: verify
description: "Phase 5 of engineering-flow. Prove the change works against the real artifact, review it against the spec and the repo's standards, and get an independent review from another CLI for risky changes. Use before declaring any task done, or when the user says /verify or 'review this'."
---

# Verify

**Input:** the built change, `spec.md` and the ticket list (Trivial and small work: the goal and check you stated), and the base commit from `STATUS.md`.
**Output:** `.scratch/<feature-slug>/verify.md` (traceability matrix, what you ran, review reports), `evidence/` (script output, logs, screenshots), `STATUS.md`.
**Gate:** evidence is recorded, "act on" findings are fixed, and you can state what was verified and what was not.

Do not declare work done without this. For a trivial change, a short note in your reply is enough.

## 1. Prove it works

Check the real thing, not a proxy. Run the feature, read the actual value, inspect the diff. "It compiles" and "the tests pass" do not prove the behavior the user asked for.

- Prefer a script that re-runs the same comparison over a one-time eyeball, and keep its output so a reviewer can re-run it.
- If a check fails, suspect your method of observing before you suspect the system.
- Say plainly what you ran and what you saw. If you could not run something, say so.

## 1b. Trace the requirements

Build a matrix in `verify.md` with one row per requirement ID from the spec (work without requirement IDs gets one row per acceptance criterion or stated goal): the ticket that covers it, the test or check that proves it, and the evidence file. A requirement with no proof is a finding. Save the evidence under `evidence/` and link it.

For a UI feature, also check these.

- Contract tests pass on both sides against the same contract (`docs/project/contracts/<feature-slug>.md`).
- Every journey cited in the spec runs end to end through the real UI, including its failure and empty paths. Save screenshots or a script log.
- Every screen state in `ui.md` was seen at least once.
- Basic accessibility holds: keyboard use, labels, focus order, contrast.

## 2. Review on two axes

Use the base commit recorded in `STATUS.md` as the fixed point (or a commit, branch or `main` if none is recorded) and take the diff `git diff <fixed-point>...HEAD`. Review each axis separately, ideally in two subagents with fresh context so neither colors the other. If you cannot spawn subagents, review them one after the other.

**Spec.** Does the diff do what `spec.md` and the ticket ask? Report requirements that are missing or partial, behavior nobody asked for, and requirements that look done but are implemented wrong. Quote the spec line for each finding.

**Standards.** Does the diff follow the repo's documented standards (`AGENTS.md`, `CONTRIBUTING.md`, lint and format config)? Skip anything tooling already enforces. A documented standard always beats the smells below. Treat the smells as judgment calls, labelled "possible", never as violations.

- Mysterious name: rename it, and if no honest name comes, the design is unclear.
- Duplicated code: extract the shared shape.
- Feature envy: a method that uses another object's data more than its own. Move it there.
- Data clumps: the same few fields travel together. Give them a type.
- Primitive obsession: a string or number standing in for a domain concept. Give it a type.
- Repeated switches on the same type. Use polymorphism or one shared map.
- Shotgun surgery: one change forces scattered edits. Gather what changes together.
- Divergent change: one module edited for unrelated reasons. Split it.
- Speculative generality: parameters or hooks for needs the spec does not have. Delete them.
- Message chains such as `a.b().c().d()`. Hide the walk behind one method.
- Middle man: a function that only delegates. Call the target directly.

Report the two axes under separate headings and do not merge or rerank them. A change can follow every standard and still build the wrong thing, or build the right thing and break the conventions.

## 3. Independent review for risky changes

Use this for large, security-sensitive, irreversible or hard-to-test changes. A different model catches different bugs, and findings that two models raise independently are the strongest signal.

Use the `delegate` skill with a role from a vendor other than the one that wrote the code: `review` (Codex) for the diff, or `critique` (Gemini) for the spec and design. Save the diff (`git diff <base commit>...HEAD > .scratch/<feature-slug>/evidence/review.diff`) and pass it with the spec: `delegate.sh review .scratch/briefs/review.md --input .scratch/<feature-slug>/evidence/review.diff --input .scratch/<feature-slug>/spec.md`. Write a brief with the intent and those paths. The `--input` flags are needed because `.scratch/` is git-ignored. A Codex read role works on a copy of the project as it is now, uncommitted changes included, but it has no spec or diff unless you pass them. Ask it to review adversarially and not to edit anything. If a CLI is unavailable, fall back to a fresh-context subagent. Then act as the lead reviewer and sort every finding into one bucket with a one-line reason.

- **Act on.** Real defects in correctness, security or maintainability. These would block a PR.
- **Consider.** Legitimate, but the cost may outweigh the benefit now. Put it to the user.
- **Noted.** Valid but not actionable now.
- **Dismissed.** Wrong or missing context, with the reason.

Do not apply the other model's suggestions automatically.

## 4. Record and close

Write `verify.md`: the traceability matrix, what you ran and saw, the two review reports, the independent review buckets, and anything deferred on purpose with a reason. Promote lasting findings to `docs/` or an ADR. Run `unslop` on every prose file you wrote, including the PR description.
