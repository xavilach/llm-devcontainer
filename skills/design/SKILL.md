---
name: design
description: "Phase 2 of engineering-flow. Ground the change in the existing code, sketch types and module boundaries before implementation, check the blast radius, and write design.md. Use for medium and large changes, or when the user says /design, 'architect this' or 'what could this break'."
---

# Design

**Input:** `spec.md`, the existing code, `GLOSSARY.md`, ADRs.
**Output:** `.scratch/<feature-slug>/design.md`; for UI work also `contract.md` and `ui.md`; ADRs for decisions that outlive the feature; `STATUS.md`.
**Gate:** boundaries and risks are written down, the clash check has no open "no", and the user agrees with the shape.

Decide the shape of the change and its risks before writing code. Skip for small changes. Do a short version for medium ones.

## 1. Ground

Learn how the code you will touch works today.

- Read the relevant modules end to end, their tests, and `GLOSSARY.md` and `docs/adr/` if present.
- Explain in a few paragraphs what the code does, who calls it and where its boundaries are. Naming a file is not grounding.
- If the change moves ownership or layering, find out why the current shape exists. Use `git log` and `git blame` on the key lines. A reason found in history is a constraint, and a guess is not.

## 2. Sketch

Write the caller's usage first, then derive the types from it. Sketch types, function signatures and module boundaries with `not implemented` bodies. Prefer deep modules, meaning a small interface that hides a lot of behavior, over many shallow ones.

Design it twice. Produce at least two structurally different shapes, not two variants of one. Compare them on these points.

- How much complexity each hides behind its public interface.
- Whether a change that looks right from one file stays right for the whole repo. Assume the next contributor sees only the files it opened and copies the nearest example.
- Escape hatches the shape needs to compile, such as casts, `any` or fields that are optional but always set.
- Callers that must know the internal rules of the abstraction.

Pick one and record why, including what you rejected.

## 3. Joint UI and backend design

Skip this section when the feature has no UI. Otherwise decide both sides in this one pass, in this order, and iterate until they agree.

1. **Journeys to screens.** For each journey in the spec, list the screens and their states: loading, empty, error, partial, success. Write them to `ui.md` with the data each state shows and the actions it offers.
2. **Screens to contract.** From those needs, derive the contract in `contract.md`: endpoints or events, request and response shapes, validation rules, error codes, enums, pagination and sorting, permissions, idempotency, and latency expectations. The contract is the single source of truth. Both sides build against it.
3. **Clash check.** Fill in this table and fix every "no".

| Check | Answer |
| --- | --- |
| Every screen state has the data it shows in the contract | |
| Every contract field or endpoint is used by some screen | |
| Validation rules are defined once and applied on both sides | |
| Every error code maps to a message and a recovery action in the UI | |
| Loading, empty and partial states have matching API behavior | |
| The UI only hides what the server also enforces | |
| Names and enums match `GLOSSARY.md` on both sides | |
| Locale, time zone, currency and accessibility needs reach the data | |
| Real-time or polling needs are supported by the contract | |
| Contract changes are versioned or backward compatible | |

4. **Resolve together.** A clash is solved by changing the requirement, the UI or the API, never by one side working around the other. Log each resolution in `decisions.md` and update `requirements.md` if a requirement changed.

## 4. Blast radius

Find what the change could break outside the diff. Listing callers is not the job, because grep does that. Look where grep stops.

- The source of any library you call, its pinned version and local patches.
- Timing, such as teardown order and async boundaries.
- Data that crosses a boundary, such as API JSON, database columns, wire formats, another language reading the same bytes, feature flags.

Most risky-looking changes are safe because of one fact, for example "this call only removes entries that are already dead". Find that fact and prove it by running real code, such as a small script or test that calls the actual function. Rate your confidence for each fact.

1. Asserted only. Worthless alone.
2. Pointed at a real `file:line`.
3. Walked through the failure step by step and it cannot occur.
4. Ran a script or test that fails loudly if you are wrong.
5. Reproduced in the running app.

Report the level you reached. If you could not prove a fact, write "unproven".

## 5. Write design.md

```
# Design: <feature>

## Chosen shape
Usage sketch, types and signatures, module map.

## Alternatives rejected
Each with the reason.

## Blast radius
Risks with likelihood, cost and how to check. A separate list of what you checked and cleared.

## The safety fact
The fact the change is safe because of, the level you proved it to, and the proof.

## Open risks
What remains unproven.

## Requirements
The requirement IDs this design satisfies, and any it cannot.
```

Promote decisions that outlive the feature, such as the chosen shape or the public contract, to an ADR in `docs/adr/`. Update `STATUS.md`.

If building later shows the shape is wrong, for example the same workaround repeats across unrelated code, scrap the sketch and redesign. Do not bolt fixes onto it.
