#!/usr/bin/env bash
# install.sh — link this repo's skills and agents into ~/.claude. Idempotent: re-running changes nothing
# that is already linked; an existing file or foreign link is left alone (reported) unless --force,
# which moves it to <name>.bak-<timestamp> first.
#
#   ./install.sh [--force] [--dry-run]
#
# Also links ~/.agents → this repo when ~/.agents does not exist (skills and hooks refer to ~/.agents/…).
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE=${CLAUDE_DIR:-$HOME/.claude}
force= dry=
for a in "$@"; do
  case "$a" in
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    *) echo "usage: ./install.sh [--force] [--dry-run]" >&2; exit 2 ;;
  esac
done
run() { if [ -n "$dry" ]; then echo "would: $*"; else "$@"; fi; }

link() {  # link <source> <target>
  local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then echo "ok       $dst"; return; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -z "$force" ]; then echo "skip     $dst (exists; --force to replace)"; return; fi
    run mv "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
  fi
  run ln -s "$src" "$dst"; [ -n "$dry" ] || echo "linked   $dst -> $src"
}

if [ "$REPO" != "$HOME/.agents" ]; then
  if [ ! -e "$HOME/.agents" ] && [ ! -L "$HOME/.agents" ]; then link "$REPO" "$HOME/.agents"
  elif [ "$(cd "$HOME/.agents" && pwd -P)" != "$(cd "$REPO" && pwd -P)" ]; then
    echo "warning: ~/.agents exists and is not this repo — skills and hooks read ~/.agents/…; clone the repo there instead"
  fi
fi

run mkdir -p "$CLAUDE/skills" "$CLAUDE/agents"
for d in "$REPO"/skills/*/; do d=${d%/}; link "$d" "$CLAUDE/skills/${d##*/}"; done
for f in "$REPO"/agents/*.md; do link "$f" "$CLAUDE/agents/${f##*/}"; done
run chmod +x "$REPO"/hooks/*.sh "$REPO"/bin/* "$REPO"/scripts/* "$REPO"/.githooks/*

cat <<'NEXT'

Next (once):
  1. Third-party skills/plugins the workflow calls — see README "Third-party pieces".
  2. Hooks + mod: merge the README "settings.json" snippet into ~/.claude/settings.json.
  3. Config: cp config.example.zsh config.local.zsh, fill it in; source shell/worktrees.zsh from ~/.zshrc;
     bin/wtconf shows the effective values.
  4. Rules: rules/<FE repo dir name>.json and rules/<BE repo dir name>.json (rules/my-frontend.json is an example).
NEXT
