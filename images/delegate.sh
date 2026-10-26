#!/bin/bash
# Hand a bounded task to another model through its CLI, in headless mode.
#
# Usage: delegate.sh <role> <brief-file> [options]
#        delegate.sh --gc [--older-than DAYS] [--apply] [--include-unmerged]   (remove old runs; see delegate-gc.sh)
#   --input <path>       copy a file or directory into the delegate's working tree at the same
#                        relative path (repeatable). Needed for .scratch/ files, which git ignores,
#                        and for files with uncommitted changes. Inputs are references: they are
#                        never part of the delegate's commit.
#   --setup "<cmd>"      run in the working tree before the CLI starts (for example: npm ci)
#   --check "<cmd>"      run on the finished work; exit 4 if it fails. For write roles it runs in a
#                        fresh checkout of the committed result (setup runs there again), so it
#                        validates exactly what would be merged.
#   --allow "<tool>"     extra tool the Claude delegate may use (repeatable), e.g. "Bash(npm test:*)"
#   --scope <pathspec>   write roles may only change paths matching this (repeatable); exit 7 otherwise
#   --tag <name>         name added to the run ID, such as a ticket ID
#   --model <m>          override the model from the roles file
#   --budget <usd>       spend cap, Claude only (other CLIs have none, so this exits 2 for them)
#   --timeout <sec>      CLI time limit, default 900 (then killed 30 s later)
#   --check-timeout <s>  limit for --setup and --check, default 600
#
# Roles and models come from /etc/delegate-roles.conf. Run from inside the git repo.
# Write roles work in a git worktree on branch delegate/<id>, built from the HEAD that was current
# when the run started, and the wrapper commits the result there. Read roles never change the
# project: Claude read roles have no shell and no edit tools (unless --allow adds one), and Codex
# runs in a jail (see below).
#
# Layout of .scratch/delegations/<id>/ : the wrapper owns the directory itself (brief, logs, result,
# changed-files). Everything the delegate can write lives in jail/ (worktree, snapshot, check
# checkout, scratch HOME, Codex login). Only jail/ is ever writable from inside the Codex jail, and
# the wrapper never writes through a path inside it that it did not create.
# Exit codes: 0 ok, 2 usage, 3 CLI or confinement unavailable (do the work yourself), 4 check failed,
# 5 CLI failed or timed out, 6 a write role changed no files, 7 changes outside --scope, 8 setup
# failed, 9 commit failed or the worktree was tampered with, 10 could not prepare the working tree.
set -uo pipefail

CONF=${DELEGATE_CONF:-/etc/delegate-roles.conf}
BWRAP=${DELEGATE_BWRAP:-bwrap}
usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "delegate: $2" >&2; exit "$1"; }

# "delegate.sh --gc ..." cleans up old runs; the work is done by delegate-gc.sh.
if [ "${1:-}" = --gc ]; then shift; exec "$(dirname "$(readlink -f "$0")")/delegate-gc.sh" "$@"; fi

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
[ -f "$brief" ] || die 2 "brief not found: $brief"

line=$(awk -F'|' -v r="$role" '$1 == r { print; exit }' "$CONF" 2>/dev/null)
[ -n "$line" ] || die 2 "unknown role '$role' (see $CONF)"
IFS='|' read -r _ cli model mode <<< "$line"
[ -n "$override" ] && model=$override

command -v "$cli" >/dev/null || die 3 "$cli is not installed; do the task yourself"
top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "run inside a git repo"
if [ "$cli" != claude ]; then
  [ -z "$budget" ] || die 2 "--budget is only enforced for Claude; $role uses $cli"
  [ -z "$extra" ] || echo "delegate: warning: --allow only applies to Claude; ignored for $cli" >&2
fi

# Validate inputs before creating anything.
input_rels=()
for p in "${inputs[@]}"; do
  abs=$(realpath -m "$p")
  case $abs in "$top"/*) ;; *) die 2 "--input must be inside the repo: $p" ;; esac
  [ -e "$abs" ] || die 2 "--input not found: $p"
  input_rels+=("${abs#"$top"/}")
done

tag=${tag//[^A-Za-z0-9._-]/_}
id="$(date +%Y%m%d-%H%M%S)-$role${tag:+-$tag}-$$"
dir="$top/.scratch/delegations/$id"
jdir="$dir/jail"
home="$jdir/home" tmp="$jdir/tmp"
mkdir -p "$home" "$tmp" || die 10 "cannot create $dir"
cp "$brief" "$dir/brief.md" || die 10 "cannot copy the brief"
out="$dir/result.md"

throwaway="" checktree="" keep_worktree=""
cleanup() {
  local rc=$?
  [ -n "$throwaway" ] && git -C "$top" worktree remove --force "$throwaway" 2>/dev/null
  [ -n "$checktree" ] && git -C "$top" worktree remove --force "$checktree" 2>/dev/null
  rm -rf "$jdir/codex-home"
  if [ $rc -ne 0 ] && [ -n "$keep_worktree" ]; then
    echo "delegate: kept $keep_worktree and branch delegate/$id for inspection. To discard:" >&2
    echo "  git -C '$top' worktree remove --force '$keep_worktree' && git -C '$top' branch -D delegate/$id" >&2
  fi
  return 0
}
trap cleanup EXIT

# --- The jail ---
# Anything that runs code the delegate may have written (Codex itself, and the --setup and --check
# commands run on its result) goes through this jail whenever bubblewrap works. The root is
# read-only. $HOME, /tmp, /run, the shell history, and the .scratch directory of the project and of
# every ancestor (other delegations and their copied logins) are replaced by empty directories.
# The only writable path is this run's jail/ directory. The network stays open because the CLIs need
# their APIs; the container firewall applies. Codex requires the jail; the other CLIs use it for
# setup and check only. Without bubblewrap those commands still run with a scrubbed environment.
jail=()
if command -v "$BWRAP" >/dev/null && "$BWRAP" --ro-bind / / --unshare-user --unshare-pid true >/dev/null 2>&1; then
  case "$HOME/" in
    "$top"/*)
      # The project contains $HOME, so masking $HOME would also hide the project.
      [ "$cli" = codex ] && die 3 "the project root contains \$HOME, so the jail cannot hide your credentials" ;;
    *)
      jail=("$BWRAP" --die-with-parent --new-session --unshare-pid --unshare-ipc --ro-bind / / --dev /dev --proc /proc
            --tmpfs /tmp --tmpfs /run --tmpfs "$HOME")
      [ -d /commandhistory ] && jail+=(--tmpfs /commandhistory)
      # Order matters: masks first, then the project, then hide its .scratch, then expose this run.
      anc=$(dirname "$top")
      while [ "$anc" != / ] && [ "$anc" != . ]; do
        [ -d "$anc/.scratch" ] && jail+=(--tmpfs "$anc/.scratch")
        anc=$(dirname "$anc")
      done
      jail+=(--ro-bind "$top" "$top" --tmpfs "$top/.scratch" --bind "$jdir" "$jdir")
      [ "$cli" = codex ] && echo "delegate: codex jailed by bubblewrap (read-only root, \$HOME hidden, writable: $jdir)" ;;
  esac
elif [ "$cli" = codex ]; then
  if [ "${DELEGATE_ALLOW_UNSANDBOXED:-}" = 1 ]; then
    echo "delegate: warning: bubblewrap unavailable, Codex runs unconfined (DELEGATE_ALLOW_UNSANDBOXED=1)" >&2
  else
    die 3 "bubblewrap is unavailable, so Codex would run unconfined. Rebuild the container, or set DELEGATE_ALLOW_UNSANDBOXED=1 to accept that."
  fi
fi
# Run "$2" with bash in directory "$1". Inside the jail's tree it uses the jail when there is one,
# and always a scratch HOME and a scrubbed environment (no GH_*, no git credential helper).
run_in() {
  case "$1" in
    "$jdir"/*)
      if [ ${#jail[@]} -gt 0 ]; then
        timeout -k 10 "$check_timeout" "${jail[@]}" --chdir "$1" env -i PATH="$PATH" HOME="$home" TMPDIR="$tmp" \
          LANG=C.UTF-8 TERM=dumb bash -c "$2"
      else
        (cd "$1" && timeout -k 10 "$check_timeout" env -i PATH="$PATH" HOME="$home" TMPDIR="$tmp" LANG=C.UTF-8 TERM=dumb bash -c "$2")
      fi ;;
    *) (cd "$1" && timeout -k 10 "$check_timeout" bash -c "$2") ;;
  esac
}

# --- Working directory ---
# Resolve HEAD once: the worktree, the snapshot and the later diffs must use the same commit even
# if another result is merged while this run is in progress.
workdir=$top
base_rev=$(git -C "$top" rev-parse HEAD) || die 10 "no commits in $top"
add_worktree() { # $1 = path, $2 = revision or branch, $3.. = extra git worktree add arguments
  local path=$1 rev=$2 try; shift 2
  for try in 1 2 3; do # parallel runs can contend for git locks
    git -C "$top" worktree add -q "$@" "$path" "$rev" 2>> "$dir/worktree-add.log" && return 0
    sleep $((try * 2))
  done
  return 1
}
copy_inputs() { # $1 = destination root
  local rel
  for rel in "${input_rels[@]}"; do
    if [ -d "$top/$rel" ]; then
      mkdir -p "$1/$rel" && cp -r "$top/$rel/." "$1/$rel/" || return 1
    else
      mkdir -p "$1/$(dirname "$rel")" && cp "$top/$rel" "$1/$rel" || return 1
    fi
    # Copies are references for the delegate; read-only files discourage editing them.
    find "$1/$rel" -type f -exec chmod a-w {} + 2>/dev/null
  done
  return 0
}
if [ "$mode" = write ]; then
  workdir="$jdir/worktree"
  # Create the branch once, then retry only the checkout, so a retry cannot fail on "branch exists".
  git -C "$top" branch "delegate/$id" "$base_rev" || die 10 "could not create branch delegate/$id"
  add_worktree "$workdir" "delegate/$id" || die 10 "could not create worktree (see $dir/worktree-add.log)"
  keep_worktree=$workdir
elif [ "$cli" = codex ]; then
  # A Codex read role works on a disposable copy of the project as it stands now: the base commit
  # plus uncommitted and untracked changes. Anything it writes is discarded.
  throwaway="$jdir/snapshot"
  add_worktree "$throwaway" "$base_rev" --detach || die 10 "could not create worktree (see $dir/worktree-add.log)"
  git -C "$top" diff --binary "$base_rev" > "$dir/uncommitted.patch" || die 10 "could not diff the working tree"
  if [ -s "$dir/uncommitted.patch" ]; then
    git -C "$throwaway" apply "$dir/uncommitted.patch" || die 10 "could not apply uncommitted changes to the snapshot"
  fi
  (cd "$top" && git ls-files -z --others --exclude-standard | xargs -0 -r cp -P --parents -t "$throwaway") \
    || die 10 "could not copy untracked files to the snapshot"
  workdir=$throwaway
fi

# Files git ignores (such as .scratch/) are not in a worktree, so copy the requested inputs in.
if [ "$workdir" != "$top" ]; then
  copy_inputs "$workdir" || die 10 "could not copy --input files"
fi

# --- Git as the wrapper uses it on a write role's worktree ---
# The git directory is pinned from outside, hooks and fsmonitor are off, pathspecs are literal, and
# the user's global and system git config (filters, aliases, credential helpers) is not read. A
# delegate that rewrote the worktree's .git file or config therefore cannot make the wrapper run its
# code, and the .git file is compared before and after the run. Filters defined in the repository's
# own .git/config are still honoured.
gitdir="" gitfile=""
uname=$(git -C "$top" config user.name 2>/dev/null); uemail=$(git -C "$top" config user.email 2>/dev/null)
if [ "$mode" = write ]; then
  gitdir=$(git -C "$workdir" rev-parse --absolute-git-dir) || die 10 "cannot find the worktree git directory"
  gitfile=$(cat "$workdir/.git")
fi
wgit() {
  GIT_DIR="$gitdir" GIT_WORK_TREE="$workdir" GIT_LITERAL_PATHSPECS="${WGIT_LITERAL:-1}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.fileMode=true \
        -c user.name="${uname:-delegate}" -c user.email="${uemail:-delegate@localhost}" "$@"
}
file_sig() { # content hash and mode of a path in the work tree
  printf '%s:%s' "$(git hash-object --no-filters -- "$workdir/$1" 2>/dev/null || echo MISSING)" \
    "$(stat -c %a "$workdir/$1" 2>/dev/null || echo 0)"
}

# --- Setup ---
if [ -n "$setup" ]; then
  run_in "$workdir" "$setup" > "$dir/setup.log" 2>&1 || die 8 "setup failed, see $dir/setup.log"
  if [ "$mode" = write ]; then
    # Remember what setup produced. After the run, a setup file the delegate left untouched (same
    # content and mode) stays out of the commit; one the delegate changed is part of its work.
    : > "$dir/setup-files.nul"
    while IFS= read -r -d '' f; do
      printf '%s\0%s\0' "$f" "$(file_sig "$f")" >> "$dir/setup-files.nul"
    done < <(wgit ls-files -z --modified --others --exclude-standard)
  fi
fi

prompt="Delegated task, from the brief file:

$(cat "$brief")

---
You are a delegated agent. Do only what the brief says and stay inside the working directory.
Input files named in the brief are read-only references. Do not commit; the wrapper commits.
Your final message is the result: say what you did, what you found, and anything you could not do.
Do not push, do not touch other branches, and do not print secrets."

margs=(); [ -n "$model" ] && margs=(--model "$model")
cd "$workdir" || die 10 "cannot enter $workdir"
# The git and GitHub logins are masked from the Claude and Gemini processes: no token variables, an
# empty global git config and an empty gh config directory, so a stray push has no credentials.
# Anything that can read the files by path (a test command, for example) is not stopped by this.
mask=(env -u GH_TOKEN -u GITHUB_TOKEN GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GH_CONFIG_DIR="$home/gh")

case $cli in
  claude)
    # Headless runs cannot ask for permission, so anything not allowed here is denied. Bash is
    # disallowed outright unless --allow adds a Bash rule: Claude Code auto-allows some read-only
    # shell commands, and acceptEdits auto-approves file commands such as mv and rm. Read roles get
    # Read, Grep and Glob; write roles add Edit and Write. Whatever --allow adds, such as the test
    # suite, runs with the full permissions of this user, so keep it narrow.
    bargs=(); [ -n "$budget" ] && bargs=(--max-budget-usd "$budget")
    if [ "$mode" = write ]; then
      perm=(--permission-mode acceptEdits --allowedTools "Read Grep Glob Edit Write$extra")
    else
      perm=(--allowedTools "Read Grep Glob$extra")
    fi
    case $extra in *Bash*) ;; *) perm+=(--disallowedTools "Bash") ;; esac
    timeout -k 30 "$timeout_s" "${mask[@]}" claude -p "$prompt" "${margs[@]}" "${bargs[@]}" "${perm[@]}" \
      > "$out" 2> "$dir/stderr.log" < /dev/null
    rc=$? ;;
  codex)
    # Scrubbed environment, a throwaway CODEX_HOME holding only the Codex login, no config.toml (it
    # can carry MCP servers or hooks), no session files. Codex's own sandbox is off inside the jail
    # because the jail confines it. Its answer is written inside jail/ and copied out below.
    mkdir -p "$jdir/codex-home"; chmod 700 "$jdir/codex-home"
    src=${CODEX_HOME:-$HOME/.codex}
    [ -f "$src/auth.json" ] && cp "$src/auth.json" "$jdir/codex-home/"
    jail_cd=(); [ ${#jail[@]} -gt 0 ] && jail_cd=(--chdir "$workdir")
    timeout -k 30 "$timeout_s" "${jail[@]}" "${jail_cd[@]}" env -i PATH="$PATH" HOME="$home" CODEX_HOME="$jdir/codex-home" \
      TMPDIR="$tmp" LANG=C.UTF-8 TERM=dumb \
      codex exec --sandbox danger-full-access --ephemeral "${margs[@]}" \
      --output-last-message "$jdir/result.md" "$prompt" > "$dir/stdout.log" 2> "$dir/stderr.log" < /dev/null
    rc=$?
    # Take the answer out of the jail only if it is a plain file the wrapper can trust.
    if [ -f "$jdir/result.md" ] && [ ! -L "$jdir/result.md" ]; then cp "$jdir/result.md" "$out"; fi ;;
  gemini)
    ap=plan; [ "$mode" = write ] && ap=auto_edit
    timeout -k 30 "$timeout_s" "${mask[@]}" gemini -p "$prompt" "${margs[@]}" --approval-mode "$ap" > "$out" 2> "$dir/stderr.log" < /dev/null
    rc=$? ;;
  *) die 2 "unsupported cli '$cli' in $CONF" ;;
esac
if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
  die 5 "$cli failed (exit $rc); see $dir/stderr.log. Do the task yourself or retry."
fi

echo "delegate: role=$role cli=$cli model=${model:-default} mode=$mode"
echo "delegate: result  $out"

# --- Write roles: commit on the delegate branch and validate what changed ---
if [ "$mode" = write ]; then
  [ "$(cat "$workdir/.git" 2>/dev/null)" = "$gitfile" ] || die 9 "the worktree's .git file was modified; not safe to commit"
  wgit add -A || die 9 "git add failed"
  # Keep out of the commit: setup files the delegate did not change, and the --input copies.
  : > "$dir/exclude.nul"
  if [ -s "$dir/setup-files.nul" ]; then
    while IFS= read -r -d '' f && IFS= read -r -d '' sig; do
      [ "$(file_sig "$f")" = "$sig" ] && printf '%s\0' "$f" >> "$dir/exclude.nul"
    done < "$dir/setup-files.nul"
  fi
  # An input directory is excluded as a whole, so deleted and symlinked entries are covered too.
  for rel in "${input_rels[@]}"; do printf '%s\0' "$rel" >> "$dir/exclude.nul"; done
  if [ -s "$dir/exclude.nul" ]; then
    wgit reset -q --pathspec-from-file="$dir/exclude.nul" --pathspec-file-nul \
      || die 9 "could not keep setup files and inputs out of the commit"
  fi
  # --no-verify: project hooks do not run on delegate branches; run the project's checks when merging.
  wgit commit -q --no-verify --allow-empty -m "delegate($role): $id" || die 9 "git commit failed"
  wgit diff --name-only --no-renames "$base_rev" HEAD -- > "$dir/changed-files.txt"
  [ -s "$dir/changed-files.txt" ] || die 6 "$role is a write role but changed no files; see $out and $dir/stderr.log"
  if [ ${#scopes[@]} -gt 0 ]; then
    excl=(); for sc in "${scopes[@]}"; do excl+=(":(exclude)$sc"); done
    # Scope patterns are real pathspecs, so turn literal matching off for this one command.
    outside=$(WGIT_LITERAL=0 wgit diff --name-only --no-renames "$base_rev" HEAD -- . "${excl[@]}")
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
  checkdir=$workdir
  if [ "$mode" = write ]; then
    # Validate the artifact that would be merged: a clean checkout of the commit, not the working
    # tree, which may hold files the commit does not. It runs in the jail when there is one.
    checktree="$jdir/check-tree"
    add_worktree "$checktree" "$(wgit rev-parse HEAD)" --detach || die 10 "could not create the check checkout (see $dir/worktree-add.log)"
    checkdir=$checktree
    if [ -n "$setup" ]; then
      run_in "$checkdir" "$setup" > "$dir/check-setup.log" 2>&1 \
        || die 8 "setup failed in the check checkout, see $dir/check-setup.log"
    fi
  fi
  if run_in "$checkdir" "$check" > "$dir/check.log" 2>&1; then
    echo "delegate: check passed (on $([ "$mode" = write ] && echo 'a clean checkout of the commit' || echo 'the working tree'))"
  else
    die 4 "check FAILED, see $dir/check.log"
  fi
fi
echo "delegate: review the result yourself before using it"
