#!/bin/bash
# Hand a bounded task to another model through its CLI, in headless mode.
# Usage: delegate.sh <role> <brief-file> [--check "<cmd>"] [--allow "<tool>"]... [--tag <name>] [--model <m>] [--timeout <sec>]
# Roles and models come from /etc/delegate-roles.conf. Run from inside the git repo.
# Exit codes: 0 ok, 2 usage, 3 CLI unavailable (do the work yourself), 4 check failed, 5 CLI failed.
set -uo pipefail

CONF=${DELEGATE_CONF:-/etc/delegate-roles.conf}
usage() { echo 'usage: delegate.sh <role> <brief-file> [--check "<cmd>"] [--allow "<tool>"]... [--tag <name>] [--model <m>] [--timeout <sec>]' >&2; exit 2; }

[ $# -ge 2 ] || usage
role=$1 brief=$2; shift 2
check="" override=${DELEGATE_MODEL:-} timeout_s=900 extra="" tag=""
while [ $# -gt 0 ]; do
  case $1 in
    --check) check=${2:-}; shift 2 ;;
    --tag) tag=${2:-}; shift 2 ;;
    --allow) extra="$extra ${2:-}"; shift 2 ;;
    --model) override=${2:-}; shift 2 ;;
    --timeout) timeout_s=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$brief" ] || { echo "delegate: brief not found: $brief" >&2; exit 2; }

line=$(grep -E "^${role}\|" "$CONF" 2>/dev/null | head -1)
[ -n "$line" ] || { echo "delegate: unknown role '$role' (see $CONF)" >&2; exit 2; }
IFS='|' read -r _ cli model mode <<< "$line"
[ -n "$override" ] && model=$override

command -v "$cli" >/dev/null || { echo "delegate: $cli is not installed; do the task yourself" >&2; exit 3; }
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "delegate: run inside a git repo" >&2; exit 2; }

id="$(date +%Y%m%d-%H%M%S)-$role${tag:+-$tag}-$$"
dir="$top/.scratch/delegations/$id"
mkdir -p "$dir"
cp "$brief" "$dir/brief.md"

workdir=$top
if [ "$mode" = write ]; then
  workdir="$dir/worktree"
  # Parallel runs can contend for git locks, so retry briefly.
  for try in 1 2 3; do
    git -C "$top" worktree add -q -b "delegate/$id" "$workdir" HEAD 2>/dev/null && break
    [ $try -eq 3 ] && { echo "delegate: could not create worktree" >&2; exit 5; }
    sleep $((try * 2))
  done
fi

prompt="$(cat "$brief")

---
You are a delegated agent. Do only what the brief says and stay inside the working directory.
Your final message is the result: say what you did, what you found, and anything you could not do.
Do not push, do not touch other branches, and do not print secrets."

margs=(); [ -n "$model" ] && margs=(--model "$model")
out="$dir/result.md"
cd "$workdir" || exit 5

case $cli in
  claude)
    # Headless runs cannot ask for permission, so anything not allowed here is denied. Extra tools come from --allow.
    base="Read Grep Glob Bash(rg:*) Bash(fd:*) Bash(tree:*) Bash(git log:*) Bash(git diff:*) Bash(git show:*) Bash(git status:*)"
    if [ "$mode" = write ]; then perm=(--permission-mode acceptEdits --allowedTools "$base Edit Write$extra")
    else perm=(--allowedTools "$base$extra"); fi
    timeout "$timeout_s" claude -p "$prompt" "${margs[@]}" "${perm[@]}" > "$out" 2> "$dir/stderr.log" ;;
  codex)
    sb=read-only; [ "$mode" = write ] && sb=workspace-write
    timeout "$timeout_s" codex exec --sandbox "$sb" "${margs[@]}" --output-last-message "$out" "$prompt" > "$dir/stdout.log" 2> "$dir/stderr.log" ;;
  gemini)
    ap=default; [ "$mode" = write ] && ap=auto_edit
    timeout "$timeout_s" gemini -p "$prompt" "${margs[@]}" --approval-mode "$ap" > "$out" 2> "$dir/stderr.log" ;;
  *) echo "delegate: unsupported cli '$cli' in $CONF" >&2; exit 2 ;;
esac
rc=$?
if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
  echo "delegate: $cli failed (exit $rc); see $dir/stderr.log. Do the task yourself or retry." >&2
  exit 5
fi

echo "delegate: role=$role cli=$cli model=${model:-default} mode=$mode"
echo "delegate: result  $out"
if [ "$mode" = write ]; then
  git -C "$workdir" add -A && git -C "$workdir" commit -q -m "delegate($role): $id" --allow-empty
  echo "delegate: branch  delegate/$id (worktree $workdir)"
  git -C "$top" diff --stat "HEAD...delegate/$id" | tail -5
fi
if [ -n "$check" ]; then
  if (cd "$workdir" && bash -c "$check") > "$dir/check.log" 2>&1; then
    echo "delegate: check passed"
  else
    echo "delegate: check FAILED, see $dir/check.log" >&2
    exit 4
  fi
fi
echo "delegate: review the result yourself before using it"
