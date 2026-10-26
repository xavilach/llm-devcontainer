# Reusable LLM Devcontainer — Git submodule

This repository is intended to be added as the **`.devcontainer` submodule** of any Git project. Its root must contain `devcontainer.json` (NOT `.devcontainer/devcontainer.json` inside this repo).

## 0. Publish this repository once

Create an empty GitHub repository, e.g. `YOUR_USERNAME/llm-devcontainer`, then from a folder containing these files:

```bash
git init
git add devcontainer.json image/Dockerfile README.md
git commit -m 'Reusable AI devcontainer'
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/llm-devcontainer.git
git push -u origin main
```

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
| `llm-vscode-extensions` | `/home/node/.vscode-server/extensions` | VS Code extensions installed in containers |

VS Code sometimes relocates the server/extensions path between versions, VS Code variants, and remote environments. This mount targets the standard stable VS Code Server location; `customizations.vscode.extensions` also provisions the declared baseline extensions. UI-side VS Code extensions remain installed on the WSL/desktop host rather than inside this volume.

If Docker creates mount paths with unexpected ownership, inspect the container logs and fix the volume ownership once; do not remove the volumes merely to rebuild.

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

## 5. Modern CLI tools

`rg` (ripgrep), `fd`, `bat`, `fzf`, `tree`, `jq`; in interactive Bash sessions `grep`, `find`, and `cat` are aliased respectively to `rg`, `fd`, and `bat --paging=never`. These programs have different CLI flags and behavior, so use `command grep`, `command find`, `command cat` to invoke originals. Shell scripts do not load the aliases by default.

## WSL2 note

Keep repos in your WSL home directory, e.g. `~/projects`, rather than `/mnt/c/...` for performance. Launch VS Code with `code .` from WSL2.
