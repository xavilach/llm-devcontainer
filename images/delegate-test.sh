#!/bin/bash
# Behavioral tests for delegate.sh. Stub claude, codex and gemini CLIs run scripted actions found in
# the brief ("STUB: ..." lines), so every exit code, the commit rules and the Codex jail are
# exercised without calling a model. Run it after any change to delegate.sh:
#   images/delegate-test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
D="$here/delegate.sh"
# The temp root must be outside /tmp (the jail replaces /tmp with an empty directory, which would hide
# a fake HOME by accident) and on a filesystem that honours file modes (a host bind mount may not).
orig_home=$HOME
T=$(mktemp -d "$orig_home/.delegate-test.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 failn=0
ok() { echo "ok    $1"; pass=$((pass + 1)); }
no() { echo "FAIL  $1${2:+ ($2)}"; failn=$((failn + 1)); }
expect() { # name, wanted, got
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "wanted $2, got $3"; fi
}
contains() { # name, text, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1" "missing: $3"; fi
}
lacks() { # name, text, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then no "$1" "unexpected: $3"; else ok "$1"; fi
}

# --- Fixture: a repo, stub CLIs and a roles file ---
repo="$T/repo"; mkdir -p "$repo/.stubs" "$T/home"
git init -q "$repo"; cd "$repo" || exit 1
git config user.email t@t; git config user.name t; git config core.fileMode true
printf 'x\n' > a.txt; printf 'lock-v1\n' > lock.txt; git add -A; git commit -qm init
printf '.scratch/\n.stubs/\n' >> .git/info/exclude
cat > "$repo/.stubs/stub" <<'EOF'
#!/bin/bash
# Stub model CLI. Reads STUB: lines from the prompt and performs them in the current directory.
args=("$@"); prompt=""; outfile=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in -p) prompt="${args[i+1]}" ;; --output-last-message) outfile="${args[i+1]}" ;; esac
done
[ -z "$prompt" ] && prompt="${args[${#args[@]}-1]}"
[ -n "${STUB_LOG:-}" ] && printf '%s argv: %s | GIT_CONFIG_GLOBAL=%s GH_TOKEN=%s\n' "$(basename "$0")" "$*" "${GIT_CONFIG_GLOBAL:-}" "${GH_TOKEN:-}" >> "$STUB_LOG"
while IFS= read -r line; do
  case "$line" in
    "STUB:write "*) set -- ${line#STUB:write }; f=$1; shift; mkdir -p "$(dirname "$f")" 2>/dev/null; printf '%s\n' "$*" > "$f" 2>/dev/null ;;
    "STUB:append "*) set -- ${line#STUB:append }; f=$1; shift; printf '%s\n' "$*" >> "$f" 2>/dev/null ;;
    "STUB:copy "*) set -- ${line#STUB:copy }; mkdir -p "$(dirname "$2")" 2>/dev/null; cp "$1" "$2" 2>/dev/null ;;
    "STUB:rm "*) rm -f "${line#STUB:rm }" ;;
    "STUB:symlink "*) set -- ${line#STUB:symlink }; ln -sfn "$1" "$2" 2>/dev/null ;;
    "STUB:mv "*) set -- ${line#STUB:mv }; mkdir -p "$(dirname "$2")"; mv "$1" "$2" ;;
    "STUB:chmodx "*) chmod +x "${line#STUB:chmodx }" ;;
    "STUB:gitfile") echo "gitdir: /nonexistent" > .git ;;
    "STUB:sleep "*) sleep "${line#STUB:sleep }" ;;
    "STUB:fail") echo "stub failure" >&2; exit 3 ;;
  esac
done <<< "$prompt"
echo "stub done"
[ -n "$outfile" ] && echo "stub done" > "$outfile"
exit 0
EOF
chmod +x "$repo/.stubs/stub"
for c in claude codex gemini; do ln -s stub "$repo/.stubs/$c"; done
cat > "$T/roles.conf" <<'EOF'
w|claude||write
r|claude||read
cw|codex||write
cr|codex||read
g|gemini||read
nocli|nonexistentcli||read
EOF
# Do file modes work here? The mode tests are skipped if not.
touch "$T/modeprobe"; chmod 000 "$T/modeprobe"; modes_work=1; [ "$(stat -c %a "$T/modeprobe")" = 0 ] || modes_work=0
if [ "$(id -u)" = 0 ]; then modes_work=0; fi
export PATH="$repo/.stubs:$PATH" DELEGATE_CONF="$T/roles.conf" STUB_LOG="$T/stub.log" HOME="$T/home"
brief() { printf '%s\n' "$@" > "$T/brief.md"; }
run() { out=$("$D" "$@" 2>&1); rc=$?; }
latest() { ls -d "$repo"/.scratch/delegations/*"$1"* 2>/dev/null | tail -1; }
branch_of() { git branch --list "*$1*" --format='%(refname:short)' | head -1; }
mkdir -p "$HOME/.config/gh" "$HOME/.codex"; echo "FAKE-GH-TOKEN" > "$HOME/.config/gh/hosts.yml"; echo '{"fake":1}' > "$HOME/.codex/auth.json"

echo "== usage and refusals"
run; expect "no arguments -> 2" 2 $rc
brief "x"; run nosuchrole "$T/brief.md"; expect "unknown role -> 2" 2 $rc
run w "$T/missing.md"; expect "missing brief -> 2" 2 $rc
run w "$T/brief.md" --check; expect "option without value -> 2" 2 $rc
run cw "$T/brief.md" --budget 1; expect "--budget with a Codex role -> 2" 2 $rc
run w "$T/brief.md" --input /etc/passwd; expect "--input outside the repo -> 2" 2 $rc
run nocli "$T/brief.md"; expect "CLI not installed -> 3" 3 $rc
export GH_TOKEN=secret-token

echo "== write role basics"
brief "STUB:write out.txt hello"; run w "$T/brief.md" --tag basic; expect "write role succeeds" 0 $rc
d=$(latest basic); expect "changed-files lists the new file" "out.txt" "$(cat "$d/changed-files.txt")"
contains "branch delegate/<id> exists" "$(git branch --list 'delegate/*basic*')" "delegate/"
brief "nothing to do"; run w "$T/brief.md"; expect "no change -> 6" 6 $rc
brief "STUB:fail"; run w "$T/brief.md"; expect "CLI failure -> 5" 5 $rc
contains "failed write run prints the discard command" "$out" "worktree remove --force"
brief "STUB:sleep 6"; run w "$T/brief.md" --timeout 1; expect "timeout -> 5" 5 $rc

echo "== scope, renames, tampering"
brief "STUB:write x.txt 1" "STUB:write y.txt 2"; run w "$T/brief.md" --scope x.txt; expect "change outside --scope -> 7" 7 $rc
contains "scope failure names the file" "$out" "y.txt"
brief "STUB:mv a.txt ok/a.txt"; run w "$T/brief.md" --scope 'ok'; expect "rename into scope is still caught -> 7" 7 $rc
brief "STUB:write x.txt 1" "STUB:gitfile"; run w "$T/brief.md" --tag tamper; expect "modified worktree .git file -> 9" 9 $rc
tb=$(branch_of tamper); [ -n "$tb" ] && expect "tampered run made no commit" "0" "$(git rev-list --count "$tb" ^HEAD)" || no "tampered run made no commit" "branch missing"

echo "== setup and check"
brief "STUB:write out.txt 1"; run w "$T/brief.md" --setup 'exit 3'; expect "setup failure -> 8" 8 $rc
run w "$T/brief.md" --check false; expect "check failure -> 4" 4 $rc
contains "failed check keeps the worktree" "$out" "kept"
mkdir -p docs; echo "ref" > docs/ref.md
run w "$T/brief.md" --tag marker --setup 'touch marker' --input docs/ref.md --check 'test -f marker && test ! -e docs/ref.md'
expect "check ran on a clean checkout (input absent) with setup rerun (marker present)" 0 $rc
d=$(latest marker)
lacks "setup-created file stays out of the commit" "$(cat "$d/changed-files.txt")" "marker"
brief "STUB:append lock.txt from-delegate"
run w "$T/brief.md" --tag lock --setup 'echo from-setup >> lock.txt'; expect "delegate edits a setup-touched file" 0 $rc
br=$(branch_of lock)
contains "setup edit is kept" "$(git show "$br:lock.txt")" "from-setup"
contains "delegate edit is kept" "$(git show "$br:lock.txt")" "from-delegate"
if [ $modes_work = 1 ]; then
  brief "STUB:chmodx run.sh"
  run w "$T/brief.md" --tag mode --setup 'echo s > run.sh'; expect "mode change on a setup file counts as work" 0 $rc
  contains "mode-only change is committed" "$(cat "$(latest mode)/changed-files.txt")" "run.sh"
else echo "skip  mode tests: this filesystem or user ignores file modes"; fi

echo "== inputs"
mkdir -p docs .scratch/f; echo "UNCOMMITTED CONTRACT" > docs/contract.md; echo "SPEC-TEXT" > .scratch/f/spec.md
brief "STUB:copy docs/contract.md out.txt" "STUB:copy .scratch/f/spec.md spec-copy.txt"
run w "$T/brief.md" --tag input --scope out.txt --scope spec-copy.txt --input docs/contract.md --input .scratch/f/spec.md
expect "inputs given, delegate result accepted" 0 $rc
br=$(branch_of input)
expect "delegate could read the tracked-path input" "UNCOMMITTED CONTRACT" "$(git show "$br:out.txt")"
expect "delegate could read the .scratch input" "SPEC-TEXT" "$(git show "$br:spec-copy.txt")"
lacks "inputs are not committed" "$(cat "$(latest input)/changed-files.txt")" "contract.md"
mkdir -p docs/tracked docs/dirin; echo one > docs/tracked/f.md; echo a > docs/dirin/a.md; echo b > docs/dirin/b.md
git add docs/tracked docs/dirin; git commit -qm "tracked inputs"; echo "UNCOMMITTED EDIT" >> docs/tracked/f.md
brief "STUB:copy docs/tracked/f.md out.txt" "STUB:rm docs/dirin/a.md" "STUB:write kept.txt k"
run w "$T/brief.md" --tag trackedin --input docs/tracked/f.md --input docs/dirin --scope out.txt --scope kept.txt
expect "tracked input with uncommitted edits stays out of the commit; deleted input entry too" 0 $rc
expect "delegate saw the uncommitted edit" "UNCOMMITTED EDIT" "$(git show "$(branch_of trackedin):out.txt" | tail -1)"
git checkout -q docs/tracked/f.md
if [ $modes_work = 1 ]; then
  echo secret > docs/unreadable.md; chmod 000 docs/unreadable.md
  brief "STUB:write z.txt 1"; run w "$T/brief.md" --input docs/unreadable.md; expect "unreadable input -> 10" 10 $rc; chmod 644 docs/unreadable.md
fi

echo "== Claude tool restrictions and credentials"
: > "$STUB_LOG"; brief "STUB:write out.txt 1"
run r "$T/brief.md"; contains "read role disallows Bash" "$(cat "$STUB_LOG")" "--disallowedTools Bash"
lacks "read role has no Edit" "$(cat "$STUB_LOG")" "Edit"
: > "$STUB_LOG"; run w "$T/brief.md"
contains "write role may edit" "$(cat "$STUB_LOG")" "Edit Write"
contains "write role also disallows Bash" "$(cat "$STUB_LOG")" "--disallowedTools Bash"
contains "git login masked from Claude" "$(cat "$STUB_LOG")" "GIT_CONFIG_GLOBAL=/dev/null"
lacks "GitHub token removed from Claude's environment" "$(cat "$STUB_LOG")" "secret-token"
: > "$STUB_LOG"; run w "$T/brief.md" --allow 'Bash(npm test:*)'
contains "--allow reaches the Claude delegate" "$(cat "$STUB_LOG")" "Bash(npm test:*)"
lacks "--allow of a Bash rule lifts the Bash ban" "$(cat "$STUB_LOG")" "--disallowedTools"
: > "$STUB_LOG"; brief "x"; run g "$T/brief.md" >/dev/null; contains "git login masked from Gemini" "$(cat "$STUB_LOG")" "GIT_CONFIG_GLOBAL=/dev/null"

echo "== Codex jail"
if "${DELEGATE_BWRAP:-bwrap}" --ro-bind / / --unshare-user --unshare-pid true >/dev/null 2>&1; then
  echo "SECOND" >> a.txt; echo "FRESH" > new.txt   # uncommitted and untracked
  mkdir -p .scratch/delegations/other-run/codex-home; echo "OTHER-RUN-LOGIN" > .scratch/delegations/other-run/codex-home/auth.json
  brief "STUB:copy a.txt ../seen-a.txt" "STUB:copy new.txt ../seen-new.txt" \
        "STUB:copy $HOME/.config/gh/hosts.yml ../seen-gh.txt" "STUB:copy $HOME/.codex/auth.json ../seen-codex.txt" \
        "STUB:copy $repo/.scratch/delegations/other-run/codex-home/auth.json ../seen-other.txt" \
        "STUB:write $repo/outside.txt escaped"
  run cr "$T/brief.md" --tag jailread; expect "Codex read role runs" 0 $rc
  contains "jail announced" "$out" "jailed by bubblewrap"
  d=$(latest jailread)/jail
  contains "snapshot has uncommitted changes" "$(cat "$d/seen-a.txt" 2>/dev/null)" "SECOND"
  contains "snapshot has untracked files" "$(cat "$d/seen-new.txt" 2>/dev/null)" "FRESH"
  expect "GitHub login hidden from Codex" "" "$(cat "$d/seen-gh.txt" 2>/dev/null)"
  expect "the real Codex login is not readable by path" "" "$(cat "$d/seen-codex.txt" 2>/dev/null)"
  expect "another delegation's login hidden" "" "$(cat "$d/seen-other.txt" 2>/dev/null)"
  [ -e "$repo/outside.txt" ] && no "Codex cannot write outside its directory" "outside.txt exists" || ok "Codex cannot write outside its directory"
  git checkout -q a.txt; rm -f new.txt
  brief "STUB:write out.txt from-codex"; run cw "$T/brief.md" --tag jailwrite --scope out.txt --check 'test -f out.txt'
  expect "Codex write role with a check in the jail" 0 $rc
  # Symlink escape: the delegate may only write inside jail/, so it cannot plant a link where the wrapper writes.
  : > "$T/victim"; brief "STUB:symlink $T/victim ../../changed-files.txt" "STUB:symlink $T/victim ../../exclude.nul" "STUB:write out.txt s"
  run cw "$T/brief.md" --tag symlink; expect "Codex write role with planted symlinks still succeeds" 0 $rc
  expect "wrapper output is a regular file, not a planted link" "regular file" "$([ -L "$(latest symlink)/changed-files.txt" ] && echo link || echo 'regular file')"
  expect "the symlink target was never written" "0" "$(wc -c < "$T/victim" | tr -d ' ')"
  # The check discriminates: with the jail, the real Codex login is invisible; without it, visible.
  brief "STUB:write out.txt x"
  run cw "$T/brief.md" --check "test ! -e $HOME/.codex/auth.json && test -f out.txt"; expect "jailed check cannot see the Codex login" 0 $rc
  DELEGATE_BWRAP=/nonexistent DELEGATE_ALLOW_UNSANDBOXED=1 run cw "$T/brief.md" --check "test ! -e $HOME/.codex/auth.json"
  expect "same check outside the jail sees it, so it fails" 4 $rc
  run w "$T/brief.md" --check "test ! -e $HOME/.codex/auth.json && test -f out.txt"; expect "a Claude write role's check is jailed too" 0 $rc
  run w "$T/brief.md" --setup "test ! -e $HOME/.config/gh/hosts.yml"; expect "initial setup is jailed too" 0 $rc
  export DELEGATE_BWRAP=/nonexistent/bwrap
  run cw "$T/brief.md"; expect "no bubblewrap -> Codex refused (3)" 3 $rc
  DELEGATE_ALLOW_UNSANDBOXED=1 run cw "$T/brief.md"; expect "explicit override runs unconfined" 0 $rc
  contains "override prints a warning" "$out" "unconfined"
  unset DELEGATE_BWRAP
else
  echo "skip  Codex jail tests: bubblewrap does not work here"
fi

echo "== parallel runs"
brief "STUB:write p.txt 1"
( "$D" w "$T/brief.md" --tag par1 > "$T/p1.log" 2>&1; echo $? > "$T/p1.rc" ) &
( "$D" w "$T/brief.md" --tag par2 > "$T/p2.log" 2>&1; echo $? > "$T/p2.rc" ) &
wait
expect "parallel run 1" 0 "$(cat "$T/p1.rc")"; expect "parallel run 2" 0 "$(cat "$T/p2.rc")"
expect "parallel runs get separate branches" 2 "$(git branch --list '*par*' | wc -l)"

echo
echo "$pass passed, $failn failed"
[ $failn -eq 0 ]
