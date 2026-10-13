#!/bin/bash
# Per-worktree Postgres database for the BE (v3.6).
# Sourced by worktree-create.sh (BE side); run directly by `wtdb` / `wtrm` / `wtclean`:
#   db.sh ensure <worktree-dir> [--fresh]   create <worktree>/.env's DB name, copy the source db, migrate
#   db.sh exists <name>                     exit 0 if the db exists (1 no, 2 container down / error)
#   db.sh drop <name>                       drop it — only $WT_DB_PREFIX names, never the source db
# Config (lib/config.sh): WT_DB_CONTAINER, WT_DB_PREFIX, WT_DB_SOURCE_ENV, DB_NAME_VARS (first = the DB
# name), WT_DB_USER_VAR, WT_DB_PASSWORD_VAR, WT_DB_MIGRATE_CMD. Source db, user and password come from
# $WT_DB_SOURCE_ENV. Everything runs inside the container (`docker exec`), so host/port don't matter.
# All output goes to stderr (the WorktreeCreate hook prints only the worktree path on stdout).

. "$(dirname "${BASH_SOURCE[0]}")/config.sh"
_wtdb_var=${DB_NAME_VARS%% *}

_wtdb_say() { echo "wtdb: $*" >&2; }
_wtdb_env() { grep -h "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- | sed -e 's/^["'\'']//' -e 's/["'\'']$//'; }   # _wtdb_env <file> <KEY>

_wtdb_init() {  # sets _src _user _pw; checks the container
  [ -n "$WT_DB_CONTAINER" ] || { _wtdb_say "WARNING: WT_DB_CONTAINER not configured — no per-worktree databases"; return 2; }
  case "$WT_DB_PREFIX" in [a-z]*_) ;; *) _wtdb_say "WARNING: WT_DB_PREFIX '$WT_DB_PREFIX' must be lowercase and end in _"; return 2 ;; esac
  _src=$(_wtdb_env "$WT_DB_SOURCE_ENV" "$_wtdb_var")
  _user=$(_wtdb_env "$WT_DB_SOURCE_ENV" "$WT_DB_USER_VAR")
  _pw=$(_wtdb_env "$WT_DB_SOURCE_ENV" "$WT_DB_PASSWORD_VAR")
  [ -n "$_src" ] && [ -n "$_user" ] || { _wtdb_say "WARNING: no $_wtdb_var / $WT_DB_USER_VAR in $WT_DB_SOURCE_ENV"; return 2; }
  command -v docker >/dev/null || { _wtdb_say "WARNING: docker not found — start $WT_DB_CONTAINER in Docker"; return 2; }
  [ "$(docker inspect -f '{{.State.Running}}' "$WT_DB_CONTAINER" 2>/dev/null)" = true ] \
    || { _wtdb_say "WARNING: container $WT_DB_CONTAINER not running — start $WT_DB_CONTAINER in Docker"; return 2; }
}
_wtdb_x() { docker exec -i -e PGPASSWORD="$_pw" "$WT_DB_CONTAINER" "$@"; }   # run a pg client inside the container
_wtdb_has() { [ "$(_wtdb_x psql -U "$_user" -d postgres -tAc "select 1 from pg_database where datname = '$1'" 2>/dev/null)" = 1 ]; }
_wtdb_safe() {  # only per-worktree names; never the source db
  case "$1" in "$WT_DB_PREFIX"*) ;; *) _wtdb_say "WARNING: refusing '$1' — only $WT_DB_PREFIX* databases"; return 1 ;; esac
  printf %s "$1" | grep -qE "^${WT_DB_PREFIX}[a-z0-9_]+\$" || { _wtdb_say "WARNING: refusing '$1' — bad name"; return 1; }
  [ "$1" != "$_src" ] || { _wtdb_say "WARNING: refusing '$1' — that is the source db"; return 1; }
}

wt_db_exists() { _wtdb_init || return 2; _wtdb_has "$1"; }

wt_db_drop() {
  _wtdb_init || return 2
  _wtdb_safe "$1" || return 1
  _wtdb_x dropdb -U "$_user" --if-exists "$1" >&2 || { _wtdb_say "WARNING: dropdb $1 failed"; return 1; }
  _wtdb_say "dropped $1"
}

# wt_db_ensure <worktree-dir> [--fresh]
wt_db_ensure() {
  local dir=${1:-} fresh=${2:-} t
  [ -f "$dir/.env" ] || { _wtdb_say "WARNING: no .env in '$dir'"; return 1; }
  t=$(_wtdb_env "$dir/.env" "$_wtdb_var")
  [ -n "$t" ] || { _wtdb_say "WARNING: no $_wtdb_var in $dir/.env"; return 1; }
  _wtdb_init || return 2
  _wtdb_safe "$t" || return 1
  if _wtdb_has "$t"; then _wtdb_say "db exists: $t"; return 0; fi

  _wtdb_x createdb -U "$_user" "$t" >&2 || { _wtdb_say "WARNING: createdb $t failed"; return 1; }
  if [ "$fresh" = --fresh ]; then
    _wtdb_say "created $t (empty, --fresh)"
  else
    _wtdb_say "copying $_src → $t …"
    if ! ( set -o pipefail
           _wtdb_x pg_dump -U "$_user" --no-owner --no-acl "$_src" \
             | _wtdb_x psql -q -v ON_ERROR_STOP=1 -U "$_user" -d "$t" >/dev/null ); then
      _wtdb_say "WARNING: copy $_src → $t failed — dropping the half-filled $t"
      _wtdb_x dropdb -U "$_user" --if-exists "$t" >&2
      return 1
    fi
    _wtdb_say "copied $_src → $t"
  fi

  [ -n "$WT_DB_MIGRATE_CMD" ] || { _wtdb_say "no WT_DB_MIGRATE_CMD configured — $t not migrated"; return 0; }
  [ -d "$dir/node_modules" ] || { _wtdb_say "WARNING: no node_modules in $dir — run the setup command, then $WT_DB_MIGRATE_CMD there"; return 1; }
  ( cd "$dir" && set +u \
    && { n="${NVM_DIR:-$HOME/.nvm}/nvm.sh"; [ ! -s "$n" ] || { . "$n" && nvm use --silent >&2; } || true; } \
    && eval "$WT_DB_MIGRATE_CMD" >&2 ) \
    || { _wtdb_say "WARNING: '$WT_DB_MIGRATE_CMD' failed in $dir — db $t is there, migrate it by hand"; return 1; }
  _wtdb_say "migrated $t"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then   # executed, not sourced
  cmd=${1:-}; shift || true
  case "$cmd" in
    ensure) wt_db_ensure "$@" ;;
    exists) wt_db_exists "$@" ;;
    drop)   wt_db_drop "$@" ;;
    *) echo "usage: db.sh ensure <worktree-dir> [--fresh] | exists <name> | drop <name>" >&2; exit 64 ;;
  esac
fi
