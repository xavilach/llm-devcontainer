---
name: design
description: "Phase 2 of engineering-flow. Ground the change in the existing code, sketch types and module boundaries before implementation, check the blast radius, and write design.md. Use for medium and large changes, or when the user says /design, 'architect this' or 'what could this break'."
---

# Design

**Input:** `spec.md`, the existing code, `GLOSSARY.md`, ADRs.
**Output:** `.scratch/<feature-slug>/design.md`; for UI work also `ui.md`, `ui/round-NN/` (the proposals) and the contract at `docs/project/contracts/<feature-slug>.md` (committed); ADRs for decisions that outlive the feature; `STATUS.md`.
**Gate:** boundaries and risks are written down, the clash check has evidence for every row and no open "no", the user agrees with the shape, and for UI work the user has accepted one UI proposal.

Decide the shape of the change and its risks before writing code. Skip for small changes. Medium changes get the short version: one chosen shape with the main rejected alternative, and the safety fact named and pointed at a real `file:line`. The two-shape comparison and the proof ladder below are for the Large path.

## 1. Ground

Learn how the code you will touch works today.

- Read the relevant modules end to end, their tests, and `GLOSSARY.md` and `docs/adr/` if present.
- Explain in a few paragraphs what the code does, who calls it and where its boundaries are. Naming a file is not grounding.
- If the change moves ownership or layering, find out why the current shape exists. Use `git log` and `git blame` on the key lines. A reason found in history is a constraint, and a guess is not.

## 2. Sketch

Write the caller's usage first, then derive the types from it. Sketch types, function signatures and module boundaries with `not implemented` bodies. Prefer deep modules, meaning a small interface that hides a lot of behavior, over many shallow ones.

On the Large path, design it twice. Produce at least two structurally different shapes, not two variants of one. Compare them on these points.

- How much complexity each hides behind its public interface.
- Whether a change that looks right from one file stays right for the whole repo. Assume the next contributor sees only the files it opened and copies the nearest example.
- Escape hatches the shape needs to compile, such as casts, `any` or fields that are optional but always set.
- Callers that must know the internal rules of the abstraction.

Pick one and record why, including what you rejected.

Before detailed design, run the riskiest assumption as a small executable check, such as a spike that calls the real library or reads the real data. If it fails, the design changes now, not after slicing.

## 3. Joint UI and backend design

Skip this section when the feature has no UI. Otherwise decide both sides in this one pass, in this order, and iterate until they agree.

1. **Journeys to screens.** For each journey cited in the spec, list the screens and their states: loading, empty, error, partial, success. Write them to `ui.md` with the data each state shows and the actions it offers.
2. **Contract skeleton.** From the requirements and the screens, draft the contract at `docs/project/contracts/<feature-slug>.md` and mark it `draft`: resources and operations, the fields each screen needs, validation rules, error codes, permissions, pagination, and the performance limits the data source can meet. Write request and response shapes as JSON Schema blocks so scripts can check them. This keeps the UI from being approved on data the backend cannot supply.
3. **UI proposals.** Have Codex draft several distinct UI directions whose mockups use sample data shaped like the skeleton, and let the user choose one or ask for another round. See "UI proposal rounds" below.
4. **Finish the contract.** From the accepted proposal's screens and data needs, update the contract: endpoints or events, request and response shapes, validation rules, error codes, enums, pagination and sorting, permissions, idempotency and latency expectations. Remove `draft`. The contract is the single source of truth, and both sides build against it.
5. **Clash check, with evidence.** Fill in this table. Each row needs a pointer in the Evidence column (a `file:line`, a script and its output saved under `evidence/`, or a decision ID). "I checked" is not evidence. Fix every "no".

| Check | Answer | Evidence |
| --- | --- | --- |
| Every screen state has the data it shows in the contract | | |
| Every contract field or endpoint has a consumer: a screen, an external consumer or a system job | | |
| Validation rules are defined once and applied on both sides | | |
| Every error code maps to a message and a recovery action in the UI | | |
| Loading, empty and partial states have matching API behavior | | |
| The UI only hides what the server also enforces | | |
| Names and enums match `GLOSSARY.md` on both sides | | |
| Locale, time zone, currency and accessibility needs reach the data | | |
| Real-time or polling needs are supported by the contract | | |
| Contract changes are versioned or backward compatible | | |
| The sample data in the accepted mockup validates against the contract schemas | | |

For the last row, extract the JSON the mockup uses and validate it against the schemas with a small script (`ajv`, Python `jsonschema` or similar). Save the output as `evidence/fixtures-vs-contract.txt`. If no validator is available, check by hand and say so.

6. **Resolve together.** A clash is solved by changing the requirement, the UI or the API, never by one side working around the other. Log each resolution in `.scratch/<feature-slug>/decisions.md` and update `docs/project/requirements.md` if a requirement changed.

### UI proposal rounds

The user picks from real alternatives instead of describing a UI in words. "ChatGPT" here means the Codex CLI (OpenAI), through the `ui-proposals` role of `delegate`. It produces static HTML mockups, not images.

1. **Choose the directions.** First ask whether there is a design system or an existing UI to extend. If there is, one proposal that follows it is enough. Otherwise pick N distinct directions, three by default. They must differ in structure, such as navigation model, information density, or guided versus free-form interaction. Do not offer colour variants of one layout. Name each direction in a line.
2. **Write one brief per direction** under `.scratch/briefs/`. Include the journeys and screens from `ui.md`, the requirement IDs, the glossary terms, any design system, brand or platform constraints from `define`, and the contract skeleton, and realistic sample data shaped like its schemas. Pass the context files with `--input`, because `.scratch/` is not in the delegate's worktree. Ask for:
   - a self-contained static `ui-out/proposal-<letter>/index.html` with inline CSS and JS, no network access and no external assets, responsive, with basic accessibility (labels, focus order, contrast);
   - the key screens, plus their loading, empty and error states, reachable by links or a small state switcher;
   - `ui-out/proposal-<letter>/notes.md`: the concept, the trade-offs, the journeys and requirement IDs it serves, and any data or behavior it needs beyond the requirements. The notes flag those for the clash check.
3. **Run them in parallel**, one per direction:

   ```
   delegate.sh ui-proposals .scratch/briefs/<name>.md --tag <letter> --scope ui-out \
     --input .scratch/<feature-slug>/ui.md --input docs/project/contracts/<feature-slug>.md
   ```

4. **Collect.** From each delegation worktree (the script prints it), copy `ui-out/proposal-<letter>/` into `.scratch/<feature-slug>/ui/round-NN/proposal-<letter>/`. Open each `index.html` yourself and check it loads and covers the screens. Fix or re-run a proposal that is broken. Remove the delegation worktrees and branches.
5. **Compare.** Write `ui/round-NN/README.md`: a table of the proposals against the journeys, the requirements and their extra data needs, with a short recommendation. Tell the user where to open the files (the host folder `.scratch/<feature-slug>/ui/round-NN/`).
6. **The user decides.** Ask for one of these:
   - **Accept** one proposal as is.
   - **Base for the next round**: name the proposal, what to keep, what to change, and whether to explore new directions around it. Start a new round with the chosen proposal and the feedback as the input of the briefs.
   - **Reject all**, with the reasons. Start a new round with new directions.
7. **Record.** Log every choice in `.scratch/<feature-slug>/decisions.md` with the round, the proposal and the reason. When one is accepted, write it into `ui.md` as the reference (the path, the screens, the states), copy it to `docs/project/ui/<feature-slug>/` so it is committed, and record the decision as an ADR if the UI style will outlive the feature.

The accepted mockup is a reference, not production code. `build` implements it in the project's own stack. Extra data it needs goes through the clash check and into the contract. The mockup's sample data must validate against the contract schemas.

## 4. Blast radius

On the Large path, find what the change could break outside the diff. On the Medium path, name the one fact the change is safe because of and point at it. Listing callers is not the job, because grep does that. Look where grep stops.

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
