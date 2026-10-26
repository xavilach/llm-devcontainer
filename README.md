# Reusable LLM Devcontainer — Git submodule

This repository is intended to be added as the **`.devcontainer` submodule** of any Git project. Its root must contain `devcontainer.json` (NOT `.devcontainer/devcontainer.json` inside this repo).

## 1a. New project (run on WSL2 Ubuntu)

```bash
mkdir my-project && cd my-project
git init
git submodule add https://github.com/YOUR_USERNAME/llm-devcontainer.git .devcontainer
code .
```

## 1b. Existing project without devcontainer

```bash
git clone https://github.com/OWNER/PROJECT.git
cd PROJECT
git submodule add https://github.com/YOUR_USERNAME/llm-devcontainer.git .devcontainer
code .
```

## 1c. Existing project already containing this submodule

```bash
git clone --recurse-submodules https://github.com/OWNER/PROJECT.git
cd PROJECT
code .
```

If you cloned normally, run `git submodule update --init --recursive` before opening the container.

In VS Code (launched from WSL2), use **Dev Containers: Reopen in Container**. Docker Desktop with WSL2 integration or a working Docker Engine in WSL2 is required.

## 2. Once-only login (inside the container)

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
- The container needs `--cap-add=NET_ADMIN --cap-add=NET_RAW` (set in `runArgs`).
- `node` has **no general sudo**: it may only run `init-firewall.sh` and `fix-volume-perms.sh`. To install a system package, add it to the Dockerfile and rebuild.
- Allowlisted hostnames are resolved to IPs at start; CDN-backed hosts whose IPs rotate may need a container restart.

## 6. Modern CLI tools

`rg` (ripgrep), `fd`, `bat`, `fzf`, `tree`, `jq`; in interactive Bash sessions `grep`, `find`, and `cat` are aliased respectively to `rg`, `fd`, and `bat --paging=never`. These programs have different CLI flags and behavior, so use `command grep`, `command find`, `command cat` to invoke originals. Shell scripts do not load the aliases by default.

## 7. Working on this devcontainer with an LLM

Conventions, the security model and validation steps for humans and agents editing this repo are in [`AGENTS.md`](AGENTS.md) (`CLAUDE.md` and `GEMINI.md` point to it).

## WSL2 note

Keep repos in your WSL home directory, e.g. `~/projects`, rather than `/mnt/c/...` for performance. Launch VS Code with `code .` from WSL2.
