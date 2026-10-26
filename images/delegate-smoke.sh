#!/bin/bash
# Check that the installed CLIs still have the flags delegate.sh depends on, and that the sandbox
# works. Run it after rebuilding the container, because the CLIs install at "latest" and a renamed
# flag would turn every delegation into exit 5. Add --live to also send one tiny task to each CLI.
# Known-good versions when this was written: claude 2.x, codex-cli 0.164.0, gemini 0.65.0.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fail=0
need() { # $1 = description, $2... = command
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; fail=1; fi
}
has() { # $1 = help command, $2 = flag
  $1 2>&1 | grep -q -- "$2"
}

echo "versions: $(claude --version 2>&1 | head -1) | $(codex --version 2>&1 | head -1) | gemini $(gemini --version 2>&1 | head -1)"
need "claude -p / --allowedTools / --disallowedTools / --permission-mode / --max-budget-usd / --model" \
  bash -c "claude --help 2>&1 | grep -q -- '--allowedTools' && claude --help 2>&1 | grep -q -- '--disallowedTools' && claude --help 2>&1 | grep -q -- '--permission-mode' && claude --help 2>&1 | grep -q -- '--max-budget-usd' && claude --help 2>&1 | grep -q -- '--model'"
need "codex exec --sandbox / --ephemeral / --output-last-message / --model" \
  bash -c "codex exec --help 2>&1 | grep -q -- '--sandbox' && codex exec --help 2>&1 | grep -q -- '--ephemeral' && codex exec --help 2>&1 | grep -q -- '--output-last-message' && codex exec --help 2>&1 | grep -q -- '--model'"
need "gemini -p / --approval-mode plan / --model" \
  bash -c "gemini --help 2>&1 | grep -q -- '--prompt' && gemini --help 2>&1 | grep -q 'approval-mode' && gemini --help 2>&1 | grep -q -- '--model'"
need "bwrap can create a user and PID namespace" bwrap --ro-bind / / --unshare-user --unshare-pid true
need "delegate.sh --gc runs a dry run in a git repo" bash -c 't=$(mktemp -d) && cd "$t" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i && mkdir -p .scratch/delegations && "$0" --gc | grep -q "Dry run"; rc=$?; rm -rf "$t"; exit $rc' "$here/delegate.sh"
need "git worktree add --detach, and --pathspec-from-file reset" bash -c '
  t=$(mktemp -d) && cd "$t" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i &&
  git worktree add -q --detach "$t/w" HEAD && echo x > "$t/w/f" && git -C "$t/w" add f &&
  printf "f\0" > "$t/p" && git -C "$t/w" reset -q --pathspec-from-file="$t/p" --pathspec-file-nul; rc=$?; rm -rf "$t"; exit $rc'
need "roles file has every role delegate.sh docs mention" bash -c "for r in decide implement search review critique docs ui-proposals; do grep -q \"^\$r|\" \"\${DELEGATE_CONF:-/etc/delegate-roles.conf}\" || exit 1; done"

if [ "${1:-}" = --live ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL  --live needs a git repo"; exit 1; }
  brief=$(mktemp "$top/.scratch-smoke.XXXXXX.md"); echo "Reply with exactly: ok" > "$brief"
  for role in search review critique; do
    if timeout 200 "$here/delegate.sh" "$role" "$brief" --timeout 150 >/dev/null 2>&1; then echo "ok    live $role"; else echo "FAIL  live $role (see .scratch/delegations/)"; fail=1; fi
  done
  rm -f "$brief"
fi
[ $fail -eq 0 ] && echo "all checks passed" || echo "some checks failed"
exit $fail
