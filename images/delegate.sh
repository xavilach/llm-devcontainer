#!/bin/bash
# Hand a bounded task to another model through its CLI, in headless mode.
# Usage: delegate.sh <role> <brief-file> [--check "<cmd>"] [--allow "<tool>"]... [--tag <name>] [--model <m>] [--timeout <sec>]
# Roles and models come from /etc/delegate-roles.conf. Run from inside the git repo.
# Exit codes: 0 ok, 2 usage, 3 CLI unavailable (do the work yourself), 4 check failed, 5 CLI failed,
# 6 a write role changed no files.
set -uo pipefail

CONF=${DELEGATE_CONF:-/etc/delegate-roles.conf}
usage() { echo 'usage: delegate.sh <role> <brief-file> [--check "<cmd>"] [--allow "<tool>"]... [--tag <name>] [--model <m>] [--timeout <sec>]' >&2; exit 2; }

[ $# -ge 2 ] || usage
role=$1 brief=$2; shift 2
check="" override=${DELEGATE_MODEL:-} timeout_s=900 extra="" tag=""
while [ $# -gt 0 ]; do
  # Every option takes a value; a missing one would otherwise loop forever.
  [ $# -ge 2 ] || usage
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

line=$(awk -F'|' -v r="$role" '$1 == r { print; exit }' "$CONF" 2>/dev/null)
[ -n "$line" ] || { echo "delegate: unknown role '$role' (see $CONF)" >&2; exit 2; }
IFS='|' read -r _ cli model mode <<< "$line"
[ -n "$override" ] && model=$override

command -v "$cli" >/dev/null || { echo "delegate: $cli is not installed; do the task yourself" >&2; exit 3; }
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "delegate: run inside a git repo" >&2; exit 2; }

tag=${tag//[^A-Za-z0-9._-]/_}
id="$(date +%Y%m%d-%H%M%S)-$role${tag:+-$tag}-$$"
dir="$top/.scratch/delegations/$id"
mkdir -p "$dir"
cp "$brief" "$dir/brief.md"

# Codex's own sandbox cannot start inside this container (no user namespaces), so Codex runs with
# its sandbox off and the container is the boundary. To keep a read role from changing the project,
# it runs in a throwaway detached worktree that is removed afterwards.
throwaway=""
cleanup() { [ -n "$throwaway" ] && git -C "$top" worktree remove --force "$throwaway" 2>/dev/null; return 0; }
trap cleanup EXIT

workdir=$top
if [ "$mode" != write ] && [ "$cli" = codex ]; then
  throwaway="$dir/scratch-worktree"
  git -C "$top" worktree add -q --detach "$throwaway" HEAD || { echo "delegate: could not create worktree" >&2; exit 5; }
  workdir=$throwaway
fi
if [ "$mode" = write ]; then
  workdir="$dir/worktree"
  # Parallel runs can contend for git locks, so retry briefly.
  base_rev=$(git -C "$top" rev-parse HEAD)
  for try in 1 2 3; do
    git -C "$top" worktree add -q -b "delegate/$id" "$workdir" HEAD 2>/dev/null && break
    [ $try -eq 3 ] && { echo "delegate: could not create worktree" >&2; exit 5; }
    sleep $((try * 2))
  done
fi

prompt="Delegated task, from the brief file:

$(cat "$brief")

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
    timeout "$timeout_s" claude -p "$prompt" "${margs[@]}" "${perm[@]}" > "$out" 2> "$dir/stderr.log" < /dev/null ;;
  codex)
    timeout "$timeout_s" codex exec --sandbox danger-full-access "${margs[@]}" --output-last-message "$out" "$prompt" > "$dir/stdout.log" 2> "$dir/stderr.log" < /dev/null ;;
  gemini)
    ap=plan; [ "$mode" = write ] && ap=auto_edit
    timeout "$timeout_s" gemini -p "$prompt" "${margs[@]}" --approval-mode "$ap" > "$out" 2> "$dir/stderr.log" < /dev/null ;;
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
  if git -C "$workdir" diff --quiet "$base_rev" HEAD --; then
    echo "delegate: $role is a write role but changed no files; see $out and $dir/stderr.log" >&2
    exit 6
  fi
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
