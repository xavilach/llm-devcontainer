# AGENTS.md: working on this devcontainer

This repository is a **shared devcontainer, consumed as the `.devcontainer` Git submodule** of many projects. A change here affects every project that updates its submodule pointer. Treat it as shared infrastructure: small, deliberate, documented changes.

## Layout

| Path | Role |
| --- | --- |
| `devcontainer.json` | Container config: build args, mounts, caps, VS Code settings, lifecycle commands. Must stay at the repo root (the submodule root *is* the `.devcontainer` folder). |
| `seccomp-userns.json` | Docker's default seccomp profile (moby v28.0.0) plus eight syscalls, so bubblewrap can create namespaces without any added capability. Passed through `runArgs`. See the Security model. |
| `images/Dockerfile` | The image. Numbered, commented, one-concern-per-step layers. |
| `images/init-firewall.sh` | Default-deny outbound firewall, run as root on every start. |
| `images/allowed-domains.txt` | Hostnames the firewall permits. Copied into the image as `/etc/firewall-allowed-domains.txt`. |
| `images/fix-volume-perms.sh` | Re-owns named-volume mount points to `node` on every start. |
| `skills/` | Our agent skills, baked into the image: `engineering-flow` (the pipeline overview), the phase skills `define`, `align`, `design`, `slice`, `build`, `verify`, and the support skills `diagnose`, `delegate`, `handoff`, `retro`, `unslop`. Self-contained and preconfigured: no setup skills, no third-party skills. Attribution in `skills/NOTICE.md`. |
| `images/init-workspace.sh` | Runs as `node` on every start; creates `.scratch/` and adds it to the repo-local `.git/info/exclude`. Workflow outputs must live under `/workspace` (a bind mount), never in `/tmp`. |
| `images/install-skills.sh` | Runs as `node` on every start; copies the baked skills into the Claude/Codex/Gemini global skills dirs. Offline, never blocks start. |
| `images/delegate.sh`, `images/delegate-roles.conf` | Headless delegation to other models through the installed CLIs. Roles map to a CLI, a model and read or write mode. Write mode works in a git worktree. Needs no extra privileges. |
| `README.md` | Human-facing setup, volumes, security notes and the engineering workflow guide (section 7). |
| `AGENTS.md` | This file (`CLAUDE.md` and `GEMINI.md` point here). |

## Conventions (the owner cares about these)

1. **Keep Dockerfile steps separate and documented.** Do NOT merge apt layers or compress steps for size or speed. The owner wants to read the file step by step. Every step has a `# NN — Purpose.` comment.
2. **Steps are numbered sequentially.** When inserting or removing a step, renumber all following steps. Check with `grep -n '^# [0-9][0-9] —' images/Dockerfile`.
3. **Order for cache efficiency:** stable things first (base, apt, scripts, sudo, env, dirs, aliases), frequently-changing things last (the npm CLI installs), then `USER node`. CLI installs need root, so they stay before `USER node`.
4. **Single source for each setting.** The persistent-config env vars (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `HISTFILE`) live only in the Dockerfile `ENV`. `containerEnv` holds only runtime flags (`DEVCONTAINER`).
5. **Pin through build args.** CLI versions are `ARG`s (`CLAUDE_CODE_VERSION`, `CODEX_VERSION`, `GEMINI_CLI_VERSION`) set in `build.args`. Add new tools the same way.
6. **Docs move with code.** Any change to volumes, tools, security behaviour or workflow updates `README.md` (and this file if conventions change) in the same commit.
7. **Unslop markdown.** Run the `unslop` skill (`skills/unslop`) on every markdown file you write or edit, whether it is for humans or for LLMs (README, this file, skills, specs).

## Security model — do not weaken without the owner's explicit approval

- **Restricted sudo.** `node` may run only `init-firewall.sh` and `fix-volume-perms.sh` via `/etc/sudoers.d/node`. Never restore `NOPASSWD:ALL`, never add a script that accepts arbitrary arguments or commands, and keep sudo-able scripts root-owned and not writable by `node`.
- **Default-deny firewall.** Outbound traffic is limited to DNS, loopback, the Docker host `/24`, GitHub ranges and `allowed-domains.txt`. IPv6 is blocked. To permit a destination, add a hostname to `allowed-domains.txt` (with a section comment) and rebuild. Do not add a catch-all rule, disable the verification at the end of the script, or widen the host network match.
- **Seccomp profile.** `seccomp-userns.json` is Docker's default profile with one change: `clone` (without the namespace-flag filter), `unshare`, `setns`, `mount`, `umount`, `umount2`, `pivot_root` and `sethostname` are allowed without `CAP_SYS_ADMIN`. This lets bubblewrap sandbox Codex, at the cost of a wider kernel attack surface (user namespaces) inside the container. No capability is added. To regenerate it, take `profiles/seccomp/default.json` from moby, remove `clone` from the two argument-restricted rules, and append one `SCMP_ACT_ALLOW` rule for those eight names. Never use `seccomp=unconfined`, and do not add syscalls beyond what bubblewrap needs without the owner's approval.
- **Codex delegates.** `delegate.sh` runs Codex inside its bubblewrap sandbox (`workspace-write` for write roles, `read-only` for read roles) when the probe `bwrap --ro-bind / / --unshare-user --unshare-pid true` succeeds. If it does not, for example on a host that ignores the profile, Codex falls back to `--sandbox danger-full-access` with a printed warning, and the container is the only boundary. Both modes use a scrubbed environment (no `GH_*`, no git credential helper, a throwaway `CODEX_HOME` with only the Codex login). Do not describe the fallback as isolated.
- **Capabilities.** `NET_ADMIN` and `NET_RAW` exist only so the firewall script can run. Do not add other capabilities or `--privileged`.
- **No host credential mounts.** Authentication lives in named Docker volumes (`llm-*`). Do not mount SSH keys, the Docker socket, or host home directories.
- Never commit secrets, tokens or personal config.

## Persistent state

Workflow outputs (specs, handoffs, delegations, evidence) live under `/workspace`, the bind-mounted host project, so they survive restarts and rebuilds. Skills must never write them to `/tmp`, `$TMPDIR` or any container-only path.

Named volumes (see README §3) hold CLI auth and config and **must survive rebuilds**. Never rename a volume without a migration note; renaming silently logs everyone out. Mount targets must match the directories created and chowned in the Dockerfile and in `fix-volume-perms.sh`. Adding a volume means touching four places: `devcontainer.json` mounts, the Dockerfile directory step, `fix-volume-perms.sh`, and the README volume table.

## Common tasks

**Add an apt package:** add a new numbered step in the Dockerfile (same pattern as steps 03–08, with `--no-install-recommends` and apt list cleanup), renumber, mention it in README if user-visible.

**Add a global CLI:** add an `ARG X_VERSION=latest`, a numbered step with the npm cache mount, and a `build.args` entry. Add its config dir as a volume if it stores auth (see Persistent state) and its API domains to `allowed-domains.txt`.

**Allow a new domain:** edit `images/allowed-domains.txt`. Prefer the narrowest hostname. Remember hostnames resolve to IPs once at start; rotating-IP CDNs may need a restart.

**Add a VS Code extension or setting:** `customizations.vscode` in `devcontainer.json`.

**Change firewall behaviour:** edit `init-firewall.sh`; keep it idempotent (it runs on every start), keep `set -euo pipefail`, and keep the end-of-script verification (a blocked site must fail, GitHub must succeed).

## Validating changes

No Docker is guaranteed inside the container (and it should not be: no socket is mounted), so verify what you can statically and say clearly what you could not test:

```bash
python3 -c "import json; json.load(open('devcontainer.json')); json.load(open('seccomp-userns.json'))"   # JSON validity (no comments allowed here)
bash -n images/init-firewall.sh && bash -n images/fix-volume-perms.sh
grep -n '^# [0-9][0-9] —' images/Dockerfile                       # step numbering is sequential
```

Full verification happens on the host: **Dev Containers: Rebuild Container**, then inside it:

```bash
sudo -n -l                                  # only the two scripts should be listed
curl -sS --max-time 5 https://example.com   # must fail
curl -sS https://api.github.com/zen         # must succeed
claude --version && codex --version && gemini --version && gh --version
bwrap --ro-bind / / --unshare-user --unshare-pid true && echo sandbox-ok   # must print sandbox-ok
grep Seccomp: /proc/self/status             # 2 means a filter is active, and it is the custom profile
```

If the container fails to start after changing `seccomp-userns.json`, the profile is invalid or its path is wrong: fix the file and rebuild. The path in `runArgs` is read on the host, relative to the project folder.

Never claim a change "works" if you only ran the static checks. Report them as static checks.

## Submodule workflow

This repo's working tree is checked out inside a parent project at `.devcontainer/` (its `.git` file points to the parent's `.git/modules`). Commit **inside this repo** first, push, then the parent project records the new commit (`git add .devcontainer` in the parent). Do not commit on behalf of the owner unless asked. Never force-push, and never change the parent project's files as part of a devcontainer change.
