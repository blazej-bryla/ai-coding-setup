# node.sh — the repo's Node version (nvm) before any npm call, and the post-install deps check.
# Sourced (bash and zsh) by hooks/worktree-create.sh, lib/db.sh and shell/worktrees.zsh, after lib/config.sh.
# Callers run these with `set +u` (nvm is not nounset-safe).

wt_node_want() {  # wt_node_want <dir> — <dir>/.nvmrc, else engines.node of <dir>/package.json as an nvm prefix (24.x → 24)
  local v=""
  [ -f "$1/.nvmrc" ] && v=$(head -1 "$1/.nvmrc" | tr -d ' \t\r')
  [ -n "$v" ] || v=$(jq -r '.engines.node // empty' "$1/package.json" 2>/dev/null | sed -e 's/^[^0-9]*//' -e 's/[^0-9.].*//' -e 's/\.$//')
  printf %s "$v"
}

wt_node_use() {  # wt_node_use <dir> — `nvm use` the version <dir> asks for; fails with "nvm install <v>" when it isn't installed
  local d=$1 v r n=${NVM_DIR:-$HOME/.nvm}/nvm.sh
  v=$(wt_node_want "$d")
  [ -n "$v" ] || { echo "node: no .nvmrc or engines.node in $d — keeping $(node -v 2>/dev/null)"; return 0; }
  [ -s "$n" ] || { echo "node: $d needs $v but nvm is not installed ($n)"; return 1; }
  type nvm >/dev/null 2>&1 || . "$n" --no-use || { echo "node: sourcing $n failed"; return 1; }
  r=$(nvm version "$v" 2>/dev/null)
  case "$r" in ''|N/A) echo "node: $v not installed — nvm install $v"; return 1 ;; esac
  nvm use --silent "$r" >/dev/null || { echo "node: nvm use $r failed"; return 1; }
  [ "$(node -v)" = "$r" ] || { echo "node: nvm use $r left $(node -v) on PATH"; return 1; }
  echo "node: $r (wants $v)"
}

wt_deps_check() {  # wt_deps_check <dir> — each app's dev binary resolves from <app>/node_modules/.bin or the root's
  local d=$1 rc=0 app bin
  for app in "$WT_FE_DIR" "$WT_BE_DIR"; do
    if [ "$app" = "$WT_FE_DIR" ]; then bin=$WT_FE_DEV_BIN; else bin=$WT_BE_DEV_BIN; fi
    if [ -n "$bin" ]; then
      [ -x "$d/$app/node_modules/.bin/$bin" ] || [ -x "$d/node_modules/.bin/$bin" ] \
        || { echo "deps: no $bin in $app/node_modules/.bin or node_modules/.bin"; rc=1; }
    else   # no binary configured: at least some node_modules
      [ -d "$d/$app/node_modules" ] || [ -d "$d/node_modules" ] || { echo "deps: no node_modules for $app"; rc=1; }
    fi
  done
  return $rc
}
