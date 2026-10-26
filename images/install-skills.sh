#!/bin/bash
# Install the repo's agent skills into every CLI's global skills directory (run as node on each start).
# Skills are baked into the image at /usr/local/share/agent-skills (copied from this repo's skills/); no network needed.
set -uo pipefail

SRC=${SKILLS_SRC:-/usr/local/share/agent-skills}
TARGETS=("$CLAUDE_CONFIG_DIR/skills" "$CODEX_HOME/skills" "$HOME/.gemini/skills")
MANIFEST=.llm-devcontainer-skills

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for skill in "$SRC"/*/; do
  [ -f "$skill/SKILL.md" ] || continue
  cp -r "$skill" "$work/$(basename "$skill")"
done

if [ -z "$(ls -A "$work")" ]; then
  echo "install-skills: no skills found in $SRC, leaving existing skills untouched" >&2
  exit 0
fi

for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  # Remove only what a previous run installed, so user-added skills survive.
  if [ -f "$target/$MANIFEST" ]; then
    while read -r old; do [ -n "$old" ] && rm -rf "${target:?}/$old"; done < "$target/$MANIFEST"
  fi
  : > "$target/$MANIFEST"
  for skill in "$work"/*/; do
    base=$(basename "$skill")
    rm -rf "${target:?}/$base"
    cp -r "$skill" "$target/$base"
    echo "$base" >> "$target/$MANIFEST"
  done
done
echo "install-skills: installed $(ls "$work" | wc -l) skills into ${#TARGETS[@]} CLIs"
