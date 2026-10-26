#!/bin/bash
# Prepare the workspace for workflow outputs (run as node on each start; best-effort).
# Everything the workflow writes lives under /workspace, a bind mount of the host folder, so it
# survives container restarts and rebuilds. .scratch/ is kept out of git without touching the
# project's committed files: it is added to the repo-local .git/info/exclude, which also keeps
# `git clean -fd` and `git add -A` away from it.
set -uo pipefail

ws=${1:-/workspace}
git -C "$ws" rev-parse --git-dir >/dev/null 2>&1 || exit 0

mkdir -p "$ws/.scratch"
exclude=$(git -C "$ws" rev-parse --path-format=absolute --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
grep -qxF '.scratch/' "$exclude" 2>/dev/null || echo '.scratch/' >> "$exclude"
