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

# 09 — Claude Code CLI.
RUN npm install --global @anthropic-ai/claude-code

# 10 — OpenAI Codex CLI.
RUN npm install --global @openai/codex

# 11 — Google Gemini CLI.
RUN npm install --global @google/gemini-cli

# 12 — Permit sudo for routine container administration.
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# 13 — Persistent CLI locations (matched by mounts in devcontainer.json).
ENV CLAUDE_CONFIG_DIR=/home/node/.claude \
    CODEX_HOME=/home/node/.codex \
    GH_CONFIG_DIR=/home/node/.config/gh \
    GIT_CONFIG_GLOBAL=/home/node/.config/git/config

# 14 — Prepare directories; named volume mounts may hide these at runtime.
RUN mkdir -p /home/node/.claude /home/node/.codex /home/node/.gemini \
    /home/node/.config/gh /home/node/.config/git \
    /home/node/.vscode-server/extensions /workspace \
    && chown -R node:node /home/node/.claude /home/node/.codex \
       /home/node/.gemini /home/node/.config /home/node/.vscode-server /workspace

# 15 — Opt-in modern interactive command aliases (never affect scripts).
# Use `command grep`, `command find`, and `command cat` to bypass aliases.
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
    'fi' >> /home/node/.bashrc

# 16 — Drop privileges and set the working directory.
USER node
WORKDIR /workspace
CMD ["sleep", "infinity"]
