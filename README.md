# Reusable LLM devcontainer (Git submodule)

A shared devcontainer for working with Claude Code, Codex and Gemini. It is added as the **`.devcontainer` submodule** of any Git project, so its root must contain `devcontainer.json` (not `.devcontainer/devcontainer.json` inside this repo). It provides:

- the three CLIs, GitHub CLI and modern search tools, behind a default-deny firewall;
- persistent logins in named Docker volumes;
- a ready-made engineering workflow of agent skills, described in [section 7](#7-engineering-workflow).

## 1. Set up a project

Use WSL2 Ubuntu, keep repos in your WSL home (for example `~/projects`, not `/mnt/c/...`), and launch VS Code with `code .` from WSL2.

**New project**

```bash
mkdir my-project && cd my-project
git init
git submodule add https://github.com/YOUR_USERNAME/llm-devcontainer.git .devcontainer
code .
```

**Existing project without a devcontainer**

```bash
git clone https://github.com/OWNER/PROJECT.git
cd PROJECT
git submodule add https://github.com/YOUR_USERNAME/llm-devcontainer.git .devcontainer
code .
```

**Existing project that already contains this submodule**

```bash
git clone --recurse-submodules https://github.com/OWNER/PROJECT.git
cd PROJECT
code .
```

If you cloned normally, run `git submodule update --init --recursive` first.

Then run **Dev Containers: Reopen in Container** in VS Code. Docker Desktop with WSL2 integration, or a working Docker Engine in WSL2, is required.

## 2. Log in once (inside the container)

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
claude
codex login
gemini
```

Use the authentication prompts for each CLI. No SSH-agent forwarding, SSH keys, or host-credential mounts are needed. Authentication persists in named volumes as long as you keep those volumes and credentials remain valid. For best results use HTTPS Git remotes (especially the submodule URL).

## 3. Persistent Docker volumes

| Volume | Container path | Purpose |
| --- | --- | --- |
| `llm-claude-config` | `/home/node/.claude` | Claude Code configuration/auth |
| `llm-codex-config` | `/home/node/.codex` | Codex configuration/auth |
| `llm-gemini-config` | `/home/node/.gemini` | Gemini configuration/auth |
| `llm-github-cli-config` | `/home/node/.config/gh` | GitHub CLI auth |
| `llm-git-config` | `/home/node/.config/git` | Git configuration, credential helper |
| `llm-bash-history` | `/commandhistory` | Persistent Bash history |
| `llm-vscode-extensions` | `/home/node/.vscode-server/extensions` | VS Code extensions installed in containers |

VS Code sometimes relocates the server/extensions path between versions, VS Code variants, and remote environments. This mount targets the standard stable VS Code Server location; `customizations.vscode.extensions` also provisions the declared baseline extensions. UI-side VS Code extensions remain installed on the WSL/desktop host rather than inside this volume.

Volume ownership is fixed automatically on each container start (`postStartCommand`); do not remove the volumes merely to rebuild.

CLI versions can be pinned through `build.args` in `devcontainer.json` (`CLAUDE_CODE_VERSION`, `CODEX_VERSION`, `GEMINI_CLI_VERSION`; default `latest`).

## 4. Updates

In your project:

```bash
git -C .devcontainer fetch origin
git -C .devcontainer switch main
git -C .devcontainer pull --ff-only
git add .devcontainer
git commit -m 'Update devcontainer submodule'
```

The project records the selected submodule commit, not an automatically moving branch. Rebuild the container after changing its image or configuration. If sharing across concurrent containers, understand that all share CLI credentials, extension files and mutable config, and simultaneous writes may occasionally conflict.

## 5. Security: firewall and restricted sudo

- Outbound traffic is **default-deny**. `init-firewall.sh` runs on every start and allows only DNS, loopback, the Docker host network, GitHub's published ranges and the hostnames in `images/allowed-domains.txt`. IPv6 is blocked. Add a hostname to that file and rebuild if a tool needs it.
- The container needs `--cap-add=NET_ADMIN --cap-add=NET_RAW` and runs with `seccomp-userns.json` (both set in `runArgs`). The profile is Docker's default plus the namespace and mount syscalls that bubblewrap needs, so `delegate.sh` can jail delegates. The cost is a wider kernel attack surface (user namespaces); no capability is added. An invalid profile stops the container starting.
- `node` has **no general sudo**: it may only run `init-firewall.sh` and `fix-volume-perms.sh`. To install a system package, add it to the Dockerfile and rebuild.
- Allowlisted hostnames are resolved to IPs at start; CDN-backed hosts whose IPs rotate may need a container restart.

## 6. Command-line tools

`rg` (ripgrep), `fd`, `bat`, `fzf`, `tree`, `jq`; in interactive Bash sessions `grep`, `find`, and `cat` are aliased respectively to `rg`, `fd`, and `bat --paging=never`. These programs have different CLI flags and behavior, so use `command grep`, `command find`, `command cat` to invoke originals. Shell scripts do not load the aliases by default.

## 7. Engineering workflow

You talk to Claude, Codex or Gemini in the container. They follow the `engineering-flow` skill and ask you for a decision at each gate. Nothing is configured per project. The workflow is a pipeline: each phase takes inputs, runs one skill, and writes outputs that feed the next.

```
(idea) -> define -> align -> design -> slice -> build -> verify -> (verified work) -> retro
```

### The pipeline

| Phase | Input | Skill | Output | Gate (you approve) |
| --- | --- | --- | --- | --- |
| 0. Define | idea, existing docs and code | `define` | `docs/project/*`, `GLOSSARY.md`, ADRs | project, requirements, roadmap |
| 1. Align | a roadmap feature or request | `align` | `spec.md`, `decisions.md`, journeys (UI) | spec and test seams |
| 2. Design | spec, existing code | `design` | `design.md`, `ui.md`, UI proposals, the contract (`docs/project/contracts/`) | the shape, an accepted UI proposal, clash check with evidence |
| 3. Slice | spec, design, contract | `slice` | `issues/NN-*.md`, dependency graph | ticket breakdown, every requirement covered |
| 4. Build | a ticket, or the whole graph | `build` | commits, ticket notes, `changes.md` | criteria hold, suite green |
| 5. Verify | built change, spec, tickets | `verify` | `verify.md`, `evidence/` | evidence, findings fixed |

`build` has two modes. For one ticket it works test-first itself. For the whole graph it runs independent tickets in parallel through `delegate`, checks each result, and merges onto an integration branch, with a cap of three delegate launches per ticket. The agent asks once whether it may commit and records the answer in `STATUS.md`. Nothing is merged into main or pushed unless you ask.

### Start and choose the path

Type `/engineering-flow` and describe what you want, or call a skill directly. Ask "what phase are we in?" at any time. The agent reads `.scratch/<feature>/STATUS.md`.

| Size | Example | Path | Stands in for skipped steps |
| --- | --- | --- | --- |
| Trivial | typo, config tweak | build, verify | the goal and its check, in one line |
| Small | bug fix | diagnose if a bug, build, verify | goal, check and test seam in the reply |
| Medium | one feature in one module | short align, design, build, verify | the spec's acceptance list becomes ticket `01` |
| Large | several modules, migration | align, design, slice, build, verify | nothing skipped |
| New project, or first feature with a UI | a new app | define, then the Large path per feature | nothing skipped |

When in doubt, take the larger path.

### Side pipes

| Input | Skill | Output |
| --- | --- | --- |
| a bug or failing behavior | `/diagnose` | `diagnose.md`, regression test, fix |
| a bounded task and a role | `/delegate` | `.scratch/delegations/<id>/` (brief, result, branch) |
| a long or stopped session | `/handoff` | `.scratch/<feature>/handoffs/NN-<slug>.md` |
| a finished feature or a repeated mistake | `/retro` | `retro.md`, approved checks and rules |
| any markdown you or an agent wrote | `/unslop` | the same file without AI writing patterns |

### Projects with a UI

The UI and the backend are decided together so their requirements cannot clash.

```
(journeys + one requirements list) -> define -> (shared requirements, glossary)
(screens and states)               -> design -> (contract skeleton) -> (UI proposals from Codex) -> (you accept or iterate)
(accepted UI)                      -> design -> (finished contract) -> clash check with evidence -> (agreed UI and API)
(the contract)                     -> slice  -> (contract ticket first, then UI and API tickets in parallel)
(UI + API + contract tests)        -> verify -> (every journey walked end to end)
```

A clash is fixed by changing the requirement, the UI or the API together, and the fix is logged in the feature's `decisions.md`. The clash check needs evidence for each row, including a script that validates the mockup's sample data against the contract schemas, so the UI cannot be approved on data the backend cannot supply.

**UI proposal rounds.** After the contract skeleton exists, `design` asks Codex (the OpenAI CLI) for several structurally different UI directions (three for a new product look, one or two for a single screen or a Medium-path feature), each a static HTML mockup with notes on its trade-offs. They are produced in each delegate's worktree and collected into `.scratch/<feature>/ui/round-NN/proposal-<letter>/`. Open the `index.html` files from your host folder and compare them with the `README.md` in the round directory. For each round you choose to:

- accept one proposal;
- take one as the base for another round, saying what to keep and what to change;
- reject all, with the reasons, and start a round with new directions.

Every choice is logged in `decisions.md`. The accepted proposal is copied to `docs/project/ui/<feature>/` and committed. It is a reference: `build` implements it in the project's own stack.

### Where outputs live

| Place | Content | In git |
| --- | --- | --- |
| `docs/project/`, `docs/adr/`, `GLOSSARY.md` | project definition, requirements, journeys, project decisions, vocabulary, the contract, accepted UI proposals | yes |
| `.scratch/<feature>/` | spec, feature decisions, design, tickets, evidence, status, handoffs | no, local working memory |
| `.scratch/delegations/<id>/` | briefs, results and branches of delegated tasks | no |

Ask the agent to promote anything from `.scratch/` that you want to keep.

### What survives a restart or rebuild

| Data | Where | Restart | Rebuild | Volume or folder deleted |
| --- | --- | --- | --- | --- |
| Workflow outputs (`docs/`, `.scratch/`, handoffs, delegations) | `/workspace`, a bind mount of your host project folder | kept | kept | lost only if you delete the host folder |
| CLI logins, settings, installed skills | the `llm-*` named volumes | kept | kept | lost if you remove the volumes |
| Anything else in the container, including `/tmp` | container filesystem | lost on rebuild | lost | lost |

Agents write every file under the workspace and never to `/tmp`. `.scratch/` is added to the repo-local `.git/info/exclude` on each start, so it is not committed and `git clean -fd` leaves it alone. Only committed work reaches the remote: commit and push `docs/`, and ask the agent to promote anything from `.scratch/` that must be shared or backed up. If you open the project with "Clone Repository in Container Volume", the workspace lives in a Docker volume instead, so keep that volume.

### Models and delegation

`/delegate` runs a bounded task on another model through its CLI, headless. Seven roles in `images/delegate-roles.conf` (installed as `/etc/delegate-roles.conf`) map to a CLI, a model and a mode. The brief carries the task, so one role covers several jobs, and `--model` overrides the model for a run. Add a role with one line.

| Role | Model | Mode | Use for |
| --- | --- | --- | --- |
| `decide` | Claude Opus | read | a hard choice, a design sketch, a blast-radius or security read |
| `implement` | Claude Sonnet | write | tickets, tests, bug repro loops; mechanical edits with `--model claude-haiku-5-5` |
| `search` | Claude Haiku | read | reading many files, logs or diffs |
| `review` | Codex | read | second opinion on a diff |
| `critique` | Gemini | read | second opinion on a spec or design; huge inputs |
| `docs` | Codex | write | docs, PR text, changelog entries |
| `ui-proposals` | Codex | write | UI mockups for the `design` phase |

Write roles work in a git worktree built from the committed `HEAD`. Because `.scratch/` is git-ignored, the files a delegate needs are copied in with `--input`. Setup and check commands, and Codex itself, run in a bubblewrap jail (read-only root, empty `$HOME`, one writable directory per run). The network stays open and the repo is readable inside it, so keep secrets out of the repo; Claude roles have no shell unless `--allow` grants one. Gemini roles need `GEMINI_API_KEY` in `~/.gemini/.env`. A delegate's report is a claim, so the agent checks it before using it. The `delegate` skill has the options, exit codes and the full list of limits.

### How the skills are installed

The skills in `skills/` are copied into the image. On every start, `install-skills.sh` installs them into the global skills directory of Claude, Codex and Gemini (in their config volumes). Nothing is fetched at start. Skills added by hand are left alone. To change a skill, edit `skills/` and rebuild. To try an edit without rebuilding, run `SKILLS_SRC=/workspace/.devcontainer/skills install-skills.sh`, because the script otherwise copies the version baked into the image. The skills adapt ideas from mattpocock/skills and pstack; see `skills/NOTICE.md`.

### Habits that help

- Reply "yes" when the agent's recommendation is right. Questions are worded so that "yes" accepts.
- Keep define, align, design and slice in one context. Each build ticket starts fresh.
- Do not skip the gates. A spec is cheap to change, and a built feature is not.
- When something surprises you, read `decisions.md` and `changes.md`. Every choice the agent made is logged there.
- Ask for a second opinion on risky changes, through `verify` or `/delegate` with `review` or `critique`.
- Never accept "done" without `verify.md`.

## 8. Working on this devcontainer with an LLM

Conventions, the security model and validation steps for humans and agents editing this repo are in [`AGENTS.md`](AGENTS.md) (`CLAUDE.md` and `GEMINI.md` point to it).
