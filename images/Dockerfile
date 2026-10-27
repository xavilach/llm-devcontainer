# syntax=docker/dockerfile:1

# 01 — Runtime foundation: Node.js on Debian Bookworm.
FROM node:22-bookworm

# 02 — Core build and development dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential python3 python3-pip \
    jq less sudo && rm -rf /var/lib/apt/lists/*

# 03 — ripgrep (rg): fast recursive content search; interactive replacement for grep.
RUN apt-get update && apt-get install -y --no-install-recommends ripgrep \
    && rm -rf /var/lib/apt/lists/*

# 04 — fd: fast file-name search; interactive alternative to find.
# Debian Bookworm packages this binary as `fdfind`.
RUN apt-get update && apt-get install -y --no-install-recommends fd-find \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# 05 — bat: syntax-highlighted file viewing; interactive alternative to cat.
# Debian Bookworm packages this binary as `batcat`.
RUN apt-get update && apt-get install -y --no-install-recommends bat \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

# 06 — fzf: fuzzy selection in the terminal.
RUN apt-get update && apt-get install -y --no-install-recommends fzf \
    && rm -rf /var/lib/apt/lists/*

# 07 — tree: structured directory listing.
RUN apt-get update && apt-get install -y --no-install-recommends tree \
    && rm -rf /var/lib/apt/lists/*

# 08 — GitHub CLI for HTTPS Git auth, issues, pull requests, and repo operations.
RUN apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# 09 — Firewall tooling: iptables/ipset enforce the outbound allowlist, dig resolves it.
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset dnsutils iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 10 — bubblewrap (bwrap): unprivileged sandbox that Codex, and optionally Claude Code, use to confine
# the commands they run. It needs user namespaces, which the seccomp profile in devcontainer.json allows.
RUN apt-get update && apt-get install -y --no-install-recommends bubblewrap \
    && rm -rf /var/lib/apt/lists/*

# 11 — Root-owned helper scripts and the outbound domain allowlist.
# install-skills.sh and init-workspace.sh run as `node` (not via sudo) on each start: the first installs
# the skills copied below, the second keeps .scratch/ out of git. delegate.sh is the delegation
# helper, and delegate-gc.sh removes its old runs.
# Edit images/allowed-domains.txt to permit more destinations, then rebuild.
COPY images/init-firewall.sh images/fix-volume-perms.sh images/install-skills.sh images/delegate.sh images/delegate-gc.sh \
     images/init-workspace.sh /usr/local/bin/
COPY images/allowed-domains.txt /etc/firewall-allowed-domains.txt
COPY images/delegate-roles.conf /etc/delegate-roles.conf
COPY skills /usr/local/share/agent-skills
RUN chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/fix-volume-perms.sh \
    /usr/local/bin/install-skills.sh /usr/local/bin/delegate.sh /usr/local/bin/delegate-gc.sh \
    /usr/local/bin/init-workspace.sh \
    && chmod 0644 /etc/firewall-allowed-domains.txt /etc/delegate-roles.conf \
    && chmod -R a+rX /usr/local/share/agent-skills

# 12 — Restricted sudo: `node` may run ONLY these two root-owned scripts, without a password.
# There is no general root access, so an agent cannot lift the firewall or edit system files.
# Need a new system package? Add it to the Dockerfile and rebuild.
RUN printf '%s\n' \
    'node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/fix-volume-perms.sh' \
    > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# 13 — Persistent CLI locations (matched by mounts in devcontainer.json).
# This is the single source for these variables; devcontainer.json does not repeat them.
ENV CLAUDE_CONFIG_DIR=/home/node/.claude \
    CODEX_HOME=/home/node/.codex \
    GH_CONFIG_DIR=/home/node/.config/gh \
    GIT_CONFIG_GLOBAL=/home/node/.config/git/config \
    HISTFILE=/commandhistory/.bash_history

# 14 — Prepare directories; named volume mounts may hide these at runtime.
# /commandhistory holds persistent Bash history (volume mounted in devcontainer.json).
RUN mkdir -p /home/node/.claude /home/node/.codex /home/node/.gemini \
    /home/node/.config/gh /home/node/.config/git \
    /home/node/.vscode-server/extensions /commandhistory /workspace \
    && touch /commandhistory/.bash_history \
    && chown -R node:node /home/node/.claude /home/node/.codex \
       /home/node/.gemini /home/node/.config /home/node/.vscode-server \
       /commandhistory /workspace

# 15 — Opt-in modern interactive command aliases (never affect scripts).
# Use `command grep`, `command find`, and `command cat` to bypass aliases.
# Also append history after each command so concurrent shells do not lose entries.
RUN printf '%s\n' \
    '# Modern interactive tools — Bash only' \
    "alias grep='rg'" \
    "alias find='fd'" \
    "alias cat='bat --paging=never'" \
    "alias rgi='rg --hidden --glob !.git'" \
    > /etc/profile.d/modern-cli.sh \
    && printf '%s\n' \
    'if [ -f /etc/profile.d/modern-cli.sh ]; then' \
    '  . /etc/profile.d/modern-cli.sh' \
    'fi' \
    "PROMPT_COMMAND='history -a'" >> /home/node/.bashrc

# 16 — socat: creates pty pairs, so serial code can be tested on Linux without hardware.
RUN apt-get update && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*

# 17 — Go toolchain from go.dev (official tarball for the build architecture).
# GOPATH is /home/node/go, a named volume, so the module cache survives rebuilds.
ARG GO_VERSION=1.27.3
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -C /usr/local -xz
ENV GOROOT=/usr/local/go \
    GOPATH=/home/node/go \
    PATH=/usr/local/go/bin:/home/node/go/bin:${PATH}

# 18 — staticcheck: Go static analysis, installed into /usr/local/bin.
# A throwaway GOPATH keeps the root-owned module cache out of the image.
ARG STATICCHECK_VERSION=latest
RUN GOPATH=/tmp/gobuild GOBIN=/usr/local/bin go install honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VERSION} \
    && rm -rf /tmp/gobuild

# 19 — Playwright with Chromium, for driving the UI in verify. Browsers live in /opt/ms-playwright
# and their system libraries are installed by --with-deps. The download happens at build time,
# so no firewall entry is needed at runtime.
ARG PLAYWRIGHT_VERSION=latest
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN --mount=type=cache,target=/root/.npm \
    npm install --global playwright@${PLAYWRIGHT_VERSION} \
    && playwright install --with-deps chromium \
    && chmod -R a+rX /opt/ms-playwright \
    && rm -rf /var/lib/apt/lists/*

# 20 — Go cache directory for the named volume mounted at /home/node/go.
RUN mkdir -p /home/node/go && chown node:node /home/node/go

# CLI versions: override via "build.args" in devcontainer.json to pin (default: latest).
# Placed last because they change most often, which keeps earlier layers cached.
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG GEMINI_CLI_VERSION=latest

# 21 — Claude Code CLI (npm download cache kept across builds).
RUN --mount=type=cache,target=/root/.npm \
    npm install --global @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# 22 — OpenAI Codex CLI.
RUN --mount=type=cache,target=/root/.npm \
    npm install --global @openai/codex@${CODEX_VERSION}

# 23 — Google Gemini CLI.
RUN --mount=type=cache,target=/root/.npm \
    npm install --global @google/gemini-cli@${GEMINI_CLI_VERSION}

# 24 — Drop privileges and set the working directory.
USER node
WORKDIR /workspace
CMD ["sleep", "infinity"]
