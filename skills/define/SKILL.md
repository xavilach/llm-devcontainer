---
name: define
description: "Phase 0 of engineering-flow. Define the project before building features: purpose, users, journeys, scope, constraints, shared vocabulary and one requirements list covering UI and backend together. Use for a new project, a major initiative, the first feature of a project with a UI, or when the user says /define."
---

# Define

**Input:** your idea, plus any existing README, docs and code.
**Output:** `docs/project/` (`project.md`, `requirements.md`, `journeys.md` for UI, `roadmap.md`, `decisions.md`), `GLOSSARY.md`, ADRs in `docs/adr/`. All committed.
**Gate:** you approved the project, requirements and roadmap, every journey is covered, and no UI or backend clash is open.

Fix what the project is before any feature is specced. This matters most when the project has a UI, because the UI and the rest must be decided together.

## 1. Explore

Read what exists: `README`, `docs/`, `GLOSSARY.md`, `docs/adr/`, the manifest files, the main modules, recent history. Say what the project is today in a few sentences. Skip anything already defined, and update instead of rewriting.

## 2. Interview in rounds

Use the interview method from `align`: ask a whole round of questions at once, number them, give a recommended answer to each, and look up facts yourself. Cover these topics.

- **Purpose.** The problem, who has it, and how success is measured.
- **Users.** Actors and roles, with what each needs to do.
- **Scope.** What is in the first release, and what is explicitly out.
- **Constraints.** Stack, hosting, team, deadline, budget, compliance, existing systems.
- **Quality.** Performance, security, privacy, accessibility, languages, browsers or devices, offline needs, availability.
- **Risks and unknowns.** What could sink the project, and what to prototype first.

If the project has a UI, also settle these in the same rounds, not later:

- The main user journeys, step by step, including failure and empty paths.
- The platforms and the design constraints (existing design system, brand, responsive needs).
- Who owns validation, permissions and error wording, and how both sides stay consistent.
- Real-time needs, data freshness, and what the UI may cache.

## 3. Write the outputs

- `docs/project/project.md`: purpose, users, scope, non-goals, constraints, quality targets, success measures, risks.
- `docs/project/requirements.md`: one list with IDs (`REQ-001`). Each line has a layer tag (`ui`, `api`, `data`, `ops`, `cross`), a priority, and a testable statement. A UI need and the backend need it implies are written together and cross-referenced.
- `docs/project/journeys.md` (UI projects): each journey as numbered steps, with the screen, the data it needs, and the failure paths.
- `docs/project/roadmap.md`: the features in order, each with a slug, the requirement IDs it covers and its dependencies. Each feature then goes through `align`.
- `GLOSSARY.md`: every domain term used above, one definition each, and the words to avoid.
- `docs/adr/NNNN-<title>.md`: one short ADR per structural decision, such as stack, repo layout, API style, state management, auth approach. State the context, the decision and the consequences.
- `docs/project/decisions.md`: every question from the interview with the answer given.

## 4. Check for clashes

For a UI project, walk every journey step against the requirements. Each step needs the requirements that make it possible, on both sides. Each backend requirement should be needed by some journey. Fix clashes now, because this is the cheapest moment.

Update `STATUS.md` if a feature directory exists.
