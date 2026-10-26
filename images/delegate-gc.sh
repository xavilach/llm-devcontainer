#!/bin/bash
# Remove old delegation runs left in .scratch/delegations/ by delegate.sh.
#
# Usage: delegate.sh --gc [--older-than DAYS] [--apply] [--include-unmerged]
#   --older-than DAYS    only runs older than this (default 7). A run younger than one hour is never touched.
#   --apply              really delete. Without it this prints a report and changes nothing.
#   --include-unmerged   with --apply, also remove runs whose branch holds work that is not merged.
#
# A run is removable when it is old enough and its work is safe:
#   - it has no delegate/<id> branch (a read run), or
#   - the branch tip is an ancestor of HEAD (merged, or never committed), or
#   - the branch content equals its merge base with HEAD (its commits change nothing).
# A run with unmerged work is protected. A run whose delegate.sh process is still alive is skipped.
# Squash-merged and rebase-merged branches look unmerged, so they are protected: that errs on the safe side.
# Removal order for a run: its registered worktrees, then the branch, then the directory.
# Test hook: DELEGATE_GC_NOW sets the current time (epoch seconds).
# Exit codes: 0 ok, 1 a removal failed, 2 usage error.
set -uo pipefail

usage() { echo 'usage: delegate.sh --gc [--older-than DAYS] [--apply] [--include-unmerged]' >&2; exit 2; }

days=7 apply=0 unmerged=0
while [ $# -gt 0 ]; do
  case $1 in
    --older-than) [ $# -ge 2 ] || usage; days=$2; shift 2 ;;
    --apply) apply=1; shift ;;
    --include-unmerged) unmerged=1; shift ;;
    *) usage ;;
  esac
done
[[ $days =~ ^[0-9]+$ ]] || usage

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "delegate-gc: run inside a git repo" >&2; exit 2; }
git -C "$top" rev-parse --verify -q HEAD >/dev/null || { echo "delegate-gc: the repository has no commits" >&2; exit 2; }
runs="$top/.scratch/delegations"
[ -d "$runs" ] || { echo "delegate-gc: no delegations in $runs"; exit 0; }

now=${DELEGATE_GC_NOW:-$(date +%s)}
limit=$((days * 86400)) floor=3600
id_re='^[0-9]{8}-[0-9]{6}-[A-Za-z0-9._-]+-[0-9]+$'

human() { # KiB -> 12K, 3.4M, 1.2G
  awk -v k="$1" 'BEGIN { if (k < 1024) printf "%dK", k; else if (k < 1048576) printf "%.1fM", k / 1024; else printf "%.1fG", k / 1048576 }'
}
run_age() { # seconds since the timestamp in the id (local time, as delegate.sh wrote it); empty if unparseable
  local ts age
  ts=$(date -d "${1:0:4}-${1:4:2}-${1:6:2} ${1:9:2}:${1:11:2}:${1:13:2}" +%s 2>/dev/null) || return 0
  age=$((now - ts))
  # A timestamp in the future (a clock that moved back) counts as brand new, so it is reported and kept.
  [ $age -lt 0 ] && age=0
  echo $age
}
is_live() { # is the pid in the id a running delegate.sh?
  local pid=${1##*-}
  [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q 'delegate\.sh'
}
has_branch() { git -C "$top" show-ref --verify --quiet "refs/heads/delegate/$1"; }
branch_is_safe() { # merged, never committed, or commits that change nothing
  local b="delegate/$1" mb
  git -C "$top" merge-base --is-ancestor "$b" HEAD && return 0
  mb=$(git -C "$top" merge-base HEAD "$b" 2>/dev/null) || return 1
  git -C "$top" diff --quiet "$mb" "$b" --
}

remove_run() { # worktrees, then the branch, then the directory
  local id=$1 w
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    git -C "$top" worktree remove --force "$w" 2>/dev/null || { echo "delegate-gc: could not remove worktree $w" >&2; return 1; }
  done < <(git -C "$top" worktree list --porcelain | awk -v p="worktree $runs/$id/" 'index($0, p) == 1 { print substr($0, 10) }')
  if has_branch "$id"; then
    git -C "$top" branch -D "delegate/$id" >/dev/null 2>&1 || { echo "delegate-gc: could not delete branch delegate/$id" >&2; return 1; }
  fi
  case "$runs/$id" in "$top"/.scratch/delegations/?*) rm -rf -- "$runs/$id" ;; *) return 1 ;; esac
}

n_remove=0 n_protect=0 n_skip=0 kib_remove=0 failed=0
to_remove=()
printf '%-8s %-46s %8s  %s\n' action run size reason
for path in "$runs"/*/; do
  path=${path%/}
  [ -L "$path" ] && continue
  id=$(basename "$path")
  [[ $id =~ $id_re ]] || continue
  kib=$(du -sk "$path" 2>/dev/null | cut -f1); kib=${kib:-0}
  age=$(run_age "$id")
  [ -n "$age" ] || continue
  if [ "$age" -lt "$floor" ]; then
    printf '%-8s %-46s %8s  %s\n' skip "$id" "$(human "$kib")" "younger than 1 hour"; n_skip=$((n_skip + 1)); continue
  fi
  if [ "$age" -lt "$limit" ]; then
    printf '%-8s %-46s %8s  %s\n' skip "$id" "$(human "$kib")" "younger than $days days"; n_skip=$((n_skip + 1)); continue
  fi
  if is_live "$id"; then
    printf '%-8s %-46s %8s  %s\n' skip "$id" "$(human "$kib")" "process still running"; n_skip=$((n_skip + 1)); continue
  fi
  if ! has_branch "$id"; then reason="read run, no branch"
  elif branch_is_safe "$id"; then reason="merged, never committed, or no net change"
  else
    ahead=$(git -C "$top" rev-list --count "HEAD..delegate/$id" 2>/dev/null || echo "?")
    if [ "$unmerged" = 1 ] && [ "$apply" = 1 ]; then reason="DISCARDS $ahead unmerged commits"
    else
      printf '%-8s %-46s %8s  %s\n' keep "$id" "$(human "$kib")" "protected: $ahead unmerged commits"; n_protect=$((n_protect + 1)); continue
    fi
  fi
  printf '%-8s %-46s %8s  %s\n' remove "$id" "$(human "$kib")" "$reason"
  n_remove=$((n_remove + 1)); kib_remove=$((kib_remove + kib)); to_remove+=("$id")
done

echo
echo "summary: $n_remove removable ($(human "$kib_remove")), $n_protect protected, $n_skip skipped."
if [ "$apply" = 1 ]; then
  for id in "${to_remove[@]}"; do remove_run "$id" || failed=$((failed + 1)); done
  git -C "$top" worktree prune
  [ $failed -eq 0 ] && echo "Removed $n_remove runs, freed $(human "$kib_remove")." \
    || { echo "Removed $((n_remove - failed)) of $n_remove runs; $failed failed (see messages above)." ; exit 1; }
else
  echo "Dry run: nothing deleted, would free $(human "$kib_remove"). Use --apply to remove."
  [ "$unmerged" = 1 ] && echo "--include-unmerged has no effect without --apply."
fi
exit 0
