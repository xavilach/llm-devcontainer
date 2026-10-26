#!/bin/bash
# Re-own named-volume mount points to the node user (run via sudo from postStartCommand).
set -euo pipefail
chown -R node:node /home/node/.claude /home/node/.codex /home/node/.gemini \
    /home/node/.config /home/node/.vscode-server /commandhistory
