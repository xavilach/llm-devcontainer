#!/bin/bash
# Hand a bounded task to another model through its CLI, in headless mode.
#
# Usage: delegate.sh <role> <brief-file> [options]
#   --input <path>       copy a file or directory into the delegate's working tree at the same
#                        relative path (repeatable). Needed for .scratch/ files, which git ignores.
#   --setup "<cmd>"      run in the working tree before the CLI starts (for example: npm ci)
#   --check "<cmd>"      run in the working tree after the CLI finishes; exit 4 if it fails
#   --allow "<tool>"     extra tool the Claude delegate may use (repeatable), e.g. "Bash(npm test:*)"
#   --scope <pathspec>   write roles may only change paths matching this (repeatable); exit 7 otherwise
#   --tag <name>         name added to the run ID, such as a ticket ID
#   --model <m>          override the model from the roles file
#   --budget <usd>       cap spend for a Claude delegate (--max-budget-usd)
#   --timeout <sec>      CLI time limit, default 900 (then killed 30 s later)
#   --check-timeout <s>  limit for --setup and --check, default 600
#
# Roles and models come from /etc/delegate-roles.conf. Run from inside the git repo.
# Codex uses its bubblewrap sandbox when the container allows it. Write roles work in a git worktree on branch delegate/<id>, built from the committed HEAD, and the
# wrapper commits the result there. Read roles never change the project.
# Exit codes: 0 ok, 2 usage, 3 CLI unavailable (do the work yourself), 4 check failed, 5 CLI failed or
# timed out, 6 a write role changed no files, 7 changes outside --scope, 8 setup failed, 9 commit failed.
set -uo pipefail

CONF=${DELEGATE_CONF:-/etc/delegate-roles.conf}
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }

[ $# -ge 2 ] || usage
role=$1 brief=$2; shift 2
check="" setup="" override=${DELEGATE_MODEL:-} timeout_s=900 check_timeout=600 extra="" tag="" budget=""
inputs=() scopes=()
while [ $# -gt 0 ]; do
  # Every option takes a value; a missing one would otherwise loop forever.
  [ $# -ge 2 ] || usage
  case $1 in
    --input) inputs+=("$2"); shift 2 ;;
    --setup) setup=$2; shift 2 ;;
    --check) check=$2; shift 2 ;;
    --allow) extra="$extra $2"; shift 2 ;;
    --scope) scopes+=("$2"); shift 2 ;;
    --tag) tag=$2; shift 2 ;;
    --model) override=$2; shift 2 ;;
    --budget) budget=$2; shift 2 ;;
    --timeout) timeout_s=$2; shift 2 ;;
    --check-timeout) check_timeout=$2; shift 2 ;;
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

throwaway="" codexhome=""
cleanup() {
  [ -n "$throwaway" ] && git -C "$top" worktree remove --force "$throwaway" 2>/dev/null
  [ -n "$codexhome" ] && rm -rf "$codexhome"
  return 0
}
trap cleanup EXIT

# --- Working directory ---
workdir=$top
base_rev=$(git -C "$top" rev-parse HEAD)
add_worktree() { # $1 = args before the path, $2 = path
  for try in 1 2 3; do # parallel runs can contend for git locks
    # shellcheck disable=SC2086
    git -C "$top" worktree add -q $1 "$2" HEAD 2>/dev/null && return 0
    sleep $((try * 2))
  done
  return 1
}
if [ "$mode" = write ]; then
  workdir="$dir/worktree"
  add_worktree "-b delegate/$id" "$workdir" || { echo "delegate: could not create worktree" >&2; exit 5; }
elif [ "$cli" = codex ]; then
  # A Codex read role works on a disposable copy of the project as it stands now: HEAD plus
  # uncommitted and untracked changes. Edits are discarded, even if the sandbox is unavailable.
  throwaway="$dir/snapshot"
  add_worktree "--detach" "$throwaway" || { echo "delegate: could not create worktree" >&2; exit 5; }
  git -C "$top" diff --binary HEAD | git -C "$throwaway" apply 2>/dev/null
  git -C "$top" ls-files -z --others --exclude-standard | (cd "$top" && xargs -0 -r cp --parents -t "$throwaway") 2>/dev/null
  workdir=$throwaway
fi

# --- Inputs: files git ignores (such as .scratch/) are not in a worktree, so copy them in ---
if [ "$workdir" != "$top" ]; then
  for p in "${inputs[@]}"; do
    abs=$(realpath -m "$p")
    case $abs in "$top"/*) ;; *) echo "delegate: --input must be inside the repo: $p" >&2; exit 2 ;; esac
    [ -e "$abs" ] || { echo "delegate: --input not found: $p" >&2; exit 2; }
    rel=${abs#"$top"/}
    mkdir -p "$workdir/$(dirname "$rel")"
    cp -r "$abs" "$workdir/$rel"
    # Copies are references for the delegate; making files read-only discourages editing them.
    find "$workdir/$rel" -type f -exec chmod a-w {} +
  done
fi

# --- Setup ---
if [ -n "$setup" ]; then
  if ! (cd "$workdir" && timeout -k 10 "$check_timeout" bash -c "$setup") > "$dir/setup.log" 2>&1; then
    echo "delegate: setup failed, see $dir/setup.log" >&2
    exit 8
  fi
  # Whatever setup created or modified is not the delegate's work, so keep it out of the commit.
  git -C "$workdir" ls-files -z --modified --others --exclude-standard > "$dir/setup-files.nul"
fi

prompt="Delegated task, from the brief file:

$(cat "$brief")

---
You are a delegated agent. Do only what the brief says and stay inside the working directory.
Input files named in the brief are read-only references. Do not commit; the wrapper commits.
Your final message is the result: say what you did, what you found, and anything you could not do.
Do not push, do not touch other branches, and do not print secrets."

margs=(); [ -n "$model" ] && margs=(--model "$model")
out="$dir/result.md"
cd "$workdir" || exit 5

case $cli in
  claude)
    # Headless runs cannot ask for permission, so anything not allowed here is denied. Extra tools come from --allow.
    allowed="Read Grep Glob Bash(rg:*) Bash(fd:*) Bash(tree:*) Bash(git log:*) Bash(git diff:*) Bash(git show:*) Bash(git status:*)"
    bargs=(); [ -n "$budget" ] && bargs=(--max-budget-usd "$budget")
    if [ "$mode" = write ]; then perm=(--permission-mode acceptEdits --allowedTools "$allowed Edit Write$extra")
    else perm=(--allowedTools "$allowed$extra"); fi
    timeout -k 30 "$timeout_s" claude -p "$prompt" "${margs[@]}" "${bargs[@]}" "${perm[@]}" > "$out" 2> "$dir/stderr.log" < /dev/null ;;
  codex)
    # Codex's own sandbox needs bubblewrap and user namespaces. When the container allows them (the
    # seccomp profile in devcontainer.json does), use the sandbox: write roles may write only in
    # their worktree, read roles nothing. Otherwise fall back to no sandbox with a warning, and the
    # container is the only boundary. Either way: a scrubbed environment (no GH_*, no git credential
    # helper, no other CLI's config), a throwaway CODEX_HOME holding only the Codex login, and no
    # session files.
    if command -v bwrap >/dev/null && bwrap --ro-bind / / --unshare-user --unshare-pid true >/dev/null 2>&1; then
      sb=read-only; [ "$mode" = write ] && sb=workspace-write
    else
      sb=danger-full-access
      echo "delegate: warning: bubblewrap sandbox unavailable, Codex runs without a sandbox" >&2
    fi
    echo "delegate: codex sandbox=$sb"
    codexhome="$dir/codex-home"; mkdir -p "$codexhome" "$dir/home"; chmod 700 "$codexhome"
    src=${CODEX_HOME:-$HOME/.codex}
    for f in auth.json config.toml; do [ -f "$src/$f" ] && cp "$src/$f" "$codexhome/"; done
    env -i PATH="$PATH" HOME="$dir/home" CODEX_HOME="$codexhome" LANG=C.UTF-8 TERM=dumb \
      timeout -k 30 "$timeout_s" codex exec --sandbox "$sb" --ephemeral "${margs[@]}" \
      --output-last-message "$out" "$prompt" > "$dir/stdout.log" 2> "$dir/stderr.log" < /dev/null ;;
  gemini)
    ap=plan; [ "$mode" = write ] && ap=auto_edit
    timeout -k 30 "$timeout_s" gemini -p "$prompt" "${margs[@]}" --approval-mode "$ap" > "$out" 2> "$dir/stderr.log" < /dev/null ;;
  *) echo "delegate: unsupported cli '$cli' in $CONF" >&2; exit 2 ;;
esac
rc=$?
if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
  echo "delegate: $cli failed (exit $rc); see $dir/stderr.log. Do the task yourself or retry." >&2
  exit 5
fi

echo "delegate: role=$role cli=$cli model=${model:-default} mode=$mode"
echo "delegate: result  $out"

# --- Write roles: commit on the delegate branch and validate what changed ---
if [ "$mode" = write ]; then
  git -C "$workdir" add -A || { echo "delegate: git add failed" >&2; exit 9; }
  if [ -s "$dir/setup-files.nul" ]; then
    git -C "$workdir" reset -q --pathspec-from-file="$dir/setup-files.nul" --pathspec-file-nul 2>/dev/null
  fi
  # --no-verify: project hooks do not run on delegate branches; run the project's checks when merging.
  git -C "$workdir" commit -q --no-verify --allow-empty -m "delegate($role): $id" \
    || { echo "delegate: git commit failed (is git user.name/user.email set?)" >&2; exit 9; }
  git -C "$workdir" diff --name-only "$base_rev" HEAD -- > "$dir/changed-files.txt"
  if [ ! -s "$dir/changed-files.txt" ]; then
    echo "delegate: $role is a write role but changed no files; see $out and $dir/stderr.log" >&2
    exit 6
  fi
  if [ ${#scopes[@]} -gt 0 ]; then
    excl=(); for sc in "${scopes[@]}"; do excl+=(":(exclude)$sc"); done
    outside=$(git -C "$workdir" diff --name-only "$base_rev" HEAD -- . "${excl[@]}")
    if [ -n "$outside" ]; then
      echo "delegate: changes outside --scope, not safe to merge:" >&2
      echo "$outside" | sed 's/^/  /' >&2
      exit 7
    fi
  fi
  echo "delegate: branch  delegate/$id (worktree $workdir)"
  echo "delegate: changed files ($(wc -l < "$dir/changed-files.txt")), listed in $dir/changed-files.txt:"
  head -20 "$dir/changed-files.txt" | sed 's/^/  /'
fi

# --- Check ---
if [ -n "$check" ]; then
  if (cd "$workdir" && timeout -k 10 "$check_timeout" bash -c "$check") > "$dir/check.log" 2>&1; then
    echo "delegate: check passed"
  else
    echo "delegate: check FAILED, see $dir/check.log" >&2
    exit 4
  fi
fi
echo "delegate: review the result yourself before using it"
