#!/bin/bash
# Remove old delegation runs left in .scratch/delegations/ by delegate.sh.
#
# Usage: delegate.sh --gc [--older-than DAYS] [--apply] [--include-unmerged]
#   --older-than DAYS    only runs older than this (default 7). A run younger than one hour is never touched.
#   --apply              really delete. Without it this prints a report and changes nothing.
#   --include-unmerged   with --apply, also remove runs that hold work which is not merged.
#
# A run is removable when it is old enough and nothing in it would be lost:
#   - its delegate/<id> branch, if any, is merged into HEAD, never committed, or changes nothing;
#   - every worktree registered under the run is on a commit that is merged into HEAD or changes nothing;
#   - a run that never finished (no changed-files.txt) has no uncommitted work in its worktree.
# Anything else is protected. A run whose delegate.sh process is still alive is skipped. Squash-merged and
# rebase-merged branches look unmerged, so they are protected: that errs on the safe side.
# Just before a run is removed its state is checked again, and the branch is deleted only if it still points
# at the commit that was judged safe. A run that changed since the scan is left alone.
# Removal order for a run: its registered worktrees, then the branch, then the directory.
# Test hooks: DELEGATE_GC_NOW sets the current time (epoch seconds); DELEGATE_GC_HOOK is evaluated between
# the scan and the removals, and DELEGATE_GC_HOOK_LATE just before a branch is deleted.
# Exit codes: 0 ok, 1 a removal failed, 2 usage error or an unsafe delegations directory.
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
# The physical directory must be exactly <repo>/.scratch/delegations. A symlink at .scratch or at
# delegations would otherwise send the removals somewhere else.
[ "$(realpath "$runs")" = "$(realpath "$top")/.scratch/delegations" ] \
  || { echo "delegate-gc: $runs is a symlink or resolves outside the repository; refusing to continue" >&2; exit 2; }

now=${DELEGATE_GC_NOW:-$(date +%s)}
limit=$((days * 86400)) floor=3600
id_re='^[0-9]{8}-[0-9]{6}-[A-Za-z0-9._-]+-[0-9]+$'

human() { # KiB -> 12K, 3.4M, 1.2G
  awk -v k="$1" 'BEGIN { if (k < 1024) printf "%dK", k; else if (k < 1048576) printf "%.1fM", k / 1024; else printf "%.1fG", k / 1048576 }'
}
row() { printf '%-8s %-46s %8s  %s\n' "$1" "$2" "$3" "$4"; }
run_age() { # seconds since the timestamp in the id (local time, as delegate.sh wrote it); empty if unparseable
  local ts age
  ts=$(date -d "${1:0:4}-${1:4:2}-${1:6:2} ${1:9:2}:${1:11:2}:${1:13:2}" +%s 2>/dev/null) || return 0
  age=$((now - ts))
  [ $age -lt 0 ] && age=0 # a timestamp in the future (a clock that moved back) counts as brand new
  echo $age
}
is_live() { # is the pid in the id a running delegate.sh?
  local pid=${1##*-}
  [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q 'delegate\.sh'
}

# Full ref names everywhere: a tag called delegate/<id> must never stand in for the branch.
ref() { echo "refs/heads/delegate/$1"; }
tip() { git -C "$top" rev-parse --verify -q "$(ref "$1")^{commit}"; }
commit_is_safe() { # merged into HEAD, never committed, or commits that change nothing
  local mb
  git -C "$top" merge-base --is-ancestor "$1" HEAD && return 0
  mb=$(git -C "$top" merge-base HEAD "$1" 2>/dev/null) || return 1
  git -C "$top" diff --quiet "$mb" "$1" --
}
wts=() # worktrees registered under a run, filled by collect_wts
collect_wts() { # NUL-separated porcelain output, so unusual paths are safe
  local id=$1 rec prefix="worktree $runs/$id/"
  wts=()
  while IFS= read -r -d '' rec; do
    case $rec in "$prefix"*) wts+=("${rec#worktree }") ;; esac
  done < <(git -C "$top" worktree list --porcelain -z)
}
is_dirty() { [ -n "$(git -C "$1" status --porcelain --untracked-files=all 2>/dev/null)" ]; }
fingerprint() { # everything the safety decision depends on, so it can be compared before removal
  local id=$1 w out
  out="tip=$(tip "$id")"
  collect_wts "$id"
  for w in "${wts[@]}"; do
    out+="|$w@$(git -C "$w" rev-parse HEAD 2>/dev/null)/$(is_dirty "$w" && echo dirty || echo clean)"
  done
  echo "$out"
}
unsafe_reason() { # prints why the run holds work that would be lost; empty if nothing would be lost
  local id=$1 t w n
  t=$(tip "$id")
  if [ -n "$t" ] && ! commit_is_safe "$t"; then
    n=$(git -C "$top" rev-list --count "HEAD..$t" 2>/dev/null || echo "?")
    echo "$n unmerged commits on the branch"; return
  fi
  collect_wts "$id"
  for w in "${wts[@]}"; do
    if ! commit_is_safe "$(git -C "$w" rev-parse HEAD 2>/dev/null || echo 0000)"; then echo "a worktree holds unmerged commits"; return; fi
    # changed-files.txt exists once the wrapper committed the delegate's work. Without it the run never
    # finished, and anything left uncommitted in the worktree may be the delegate's partial work.
    if [ ! -e "$runs/$id/changed-files.txt" ] && is_dirty "$w"; then echo "uncommitted work in an unfinished run"; return; fi
  done
}

declare -A fp
remove_run() { # re-check, then worktrees, then the branch, then the directory
  local id=$1 w t
  if [ "$(fingerprint "$id")" != "${fp[$id]}" ] || is_live "$id"; then
    echo "delegate-gc: $id changed since the scan, left alone" >&2; return 0
  fi
  collect_wts "$id"
  for w in "${wts[@]}"; do
    git -C "$top" worktree remove --force "$w" 2>/dev/null || { echo "delegate-gc: could not remove worktree $w" >&2; return 1; }
  done
  t=${fp[$id]%%|*}; t=${t#tip=} # the commit that was judged safe at scan time
  [ -n "${DELEGATE_GC_HOOK_LATE:-}" ] && eval "$DELEGATE_GC_HOOK_LATE" # test hook: change the branch after the re-check
  if [ -n "$t" ]; then # delete only if the branch still points at that commit
    git -C "$top" update-ref -d "$(ref "$id")" "$t" 2>/dev/null || { echo "delegate-gc: could not delete branch delegate/$id" >&2; return 1; }
  fi
  rm -rf -- "${runs:?}/${id:?}" # id matched id_re, so it holds no slash, and runs was verified above
}

n_remove=0 n_protect=0 n_skip=0 kib_remove=0 failed=0
to_remove=()
row action run size reason
for path in "$runs"/*/; do
  path=${path%/}
  [ -L "$path" ] && continue
  id=$(basename "$path")
  [[ $id =~ $id_re ]] || continue
  age=$(run_age "$id"); [ -n "$age" ] || continue
  kib=$(du -sk "$path" 2>/dev/null | cut -f1); kib=${kib:-0}
  size=$(human "$kib")
  if [ "$age" -lt "$floor" ]; then why="younger than 1 hour"
  elif [ "$age" -lt "$limit" ]; then why="younger than $days days"
  elif is_live "$id"; then why="process still running"
  else why=""; fi
  if [ -n "$why" ]; then row skip "$id" "$size" "$why"; n_skip=$((n_skip + 1)); continue; fi

  bad=$(unsafe_reason "$id")
  collect_wts "$id" # unsafe_reason ran in a subshell, so look again here
  if [ -z "$bad" ]; then
    if [ -z "$(tip "$id")" ] && [ ${#wts[@]} -eq 0 ]; then reason="read run, no branch"; else reason="merged, never committed, or no net change"; fi
  elif [ "$unmerged" = 1 ] && [ "$apply" = 1 ]; then reason="DISCARDS: $bad"
  else row keep "$id" "$size" "protected: $bad"; n_protect=$((n_protect + 1)); continue
  fi
  row remove "$id" "$size" "$reason"
  n_remove=$((n_remove + 1)); kib_remove=$((kib_remove + kib)); to_remove+=("$id"); fp[$id]=$(fingerprint "$id")
done

echo
[ "$apply" = 0 ] && [ "$unmerged" = 1 ] && echo "--include-unmerged has no effect without --apply."
echo "summary: $n_remove removable ($(human "$kib_remove")), $n_protect protected, $n_skip skipped."
if [ "$apply" = 1 ]; then
  [ -n "${DELEGATE_GC_HOOK:-}" ] && eval "$DELEGATE_GC_HOOK" # test hook: change something after the scan
  for id in "${to_remove[@]}"; do remove_run "$id" || failed=$((failed + 1)); done
  git -C "$top" worktree prune
  if [ $failed -eq 0 ]; then echo "Removed up to $n_remove runs, freed up to $(human "$kib_remove")."
  else echo "$failed of $n_remove removals failed (see messages above); the rest were removed, up to $(human "$kib_remove") freed."; exit 1
  fi
else
  echo "Dry run: nothing deleted, would free $(human "$kib_remove"). Use --apply to remove."
fi
exit 0
