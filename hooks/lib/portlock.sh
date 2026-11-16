# portlock.sh — FIFO lock on the shared FE port R (WT_REMOTE_FE_PORT). Bash, sourceable; used by
# bin/wtsrv (agents) and `wts` (humans, via `bash -c`). macOS has no flock: every state change runs
# under a mkdir mutex.
#
# State: ${WT_PORTLOCK_DIR:-$HOME/.agents/run}/port-<R>/
#   holder.json        {slug, pgid, since, by: "agent"|"human"}   (pgid "pending" until the server starts)
#   queue/<ms>-<slug>  FIFO entries; the file holds the waiter's pid (dead waiters are dropped)
#   last-release.json  {slug, at}
# A holder is live while `kill -0 -- -<pgid>` succeeds (a human holder: its shell pid); a dead holder is
# cleared and counts as released now. After a release the released slug may come back for GRACE seconds
# (${WT_PORT_GRACE:-15}); after that the queue head takes the port.
#
#   pl_status                     free | held by <slug> since <t>  + queue
#   pl_acquire <slug> <timeout-s> 0 = holder (pgid pending) | 3 = timeout, prints `queued: <pos> behind <holder>`
#   pl_set_pgid <slug> <pgid>     pl_release <slug>     pl_claim_human <slug> <pid> (non-blocking)
# PL_PORT overrides R (tests; `wts` passes its own WT_REMOTE_FE_PORT).

pl_port() { [ -n "${PL_PORT:-}" ] || PL_PORT=$("$HOME/.agents/bin/wtconf" -v WT_REMOTE_FE_PORT); printf %s "$PL_PORT"; }
pl_dir() { printf %s "${WT_PORTLOCK_DIR:-$HOME/.agents/run}/port-$(pl_port)"; }
_pl_now() { date +%s; }
_pl_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }
_pl_grace() { printf %s "${WT_PORT_GRACE:-15}"; }

_pl_lock() {  # mkdir mutex; a mutex older than 10 s is stale (its owner died) and is broken
  local d; d=$(pl_dir); mkdir -p "$d/queue" || return 1
  local n=0
  until mkdir "$d/.mutex" 2>/dev/null; do
    n=$((n + 1))
    if [ $((n % 100)) -eq 0 ]; then
      local m; m=$(stat -f %m "$d/.mutex" 2>/dev/null || stat -c %Y "$d/.mutex" 2>/dev/null || echo 0)
      [ $(( $(_pl_now) - m )) -gt 10 ] && rmdir "$d/.mutex" 2>/dev/null
    fi
    sleep 0.05
  done
}
_pl_unlock() { rmdir "$(pl_dir)/.mutex" 2>/dev/null; return 0; }

_pl_get() { jq -r ".$2 // empty" "$1" 2>/dev/null; }   # <file> <field>
_pl_listening() { lsof -iTCP:"$(pl_port)" -sTCP:LISTEN -t >/dev/null 2>&1; }

_pl_holder_live() {  # holder.json present and its process group (or pid) alive
  local f; f="$(pl_dir)/holder.json"; [ -f "$f" ] || return 1
  local pg since; pg=$(_pl_get "$f" pgid); since=$(_pl_get "$f" since)
  if [ "$pg" = pending ]; then   # between acquire and the server's start; a crashed starter expires
    [ $(( $(_pl_now) - ${since:-0} )) -lt 120 ]; return
  fi
  case "$pg" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 -- "-$pg" 2>/dev/null || kill -0 "$pg" 2>/dev/null
}

_pl_write_release() {  # <slug>; called under the mutex
  local d; d=$(pl_dir)
  jq -nc --arg s "$1" --argjson t "$(_pl_now)" '{slug: $s, at: $t}' > "$d/last-release.json.tmp" && mv "$d/last-release.json.tmp" "$d/last-release.json"
}
_pl_write_holder() {  # <slug> <pgid> <by>; under the mutex
  local d; d=$(pl_dir)
  jq -nc --arg s "$1" --arg p "$2" --arg b "$3" --argjson t "$(_pl_now)" '{slug: $s, pgid: $p, since: $t, by: $b}' > "$d/holder.json.tmp" && mv "$d/holder.json.tmp" "$d/holder.json"
}
_pl_clear_dead() {  # under the mutex: a dead holder → cleared, released now
  local d s; d=$(pl_dir)
  [ -f "$d/holder.json" ] || return 0
  _pl_holder_live && return 0
  s=$(_pl_get "$d/holder.json" slug); rm -f "$d/holder.json"; _pl_write_release "$s"
}
_pl_prune_queue() {  # under the mutex: drop entries whose waiter is gone
  local e p
  for e in "$(pl_dir)"/queue/*; do
    [ -f "$e" ] || continue
    p=$(cat "$e" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) rm -f "$e"; continue ;; esac
    kill -0 "$p" 2>/dev/null || rm -f "$e"
  done
}
_pl_queue() { ls "$(pl_dir)/queue" 2>/dev/null | LC_ALL=C sort; }   # entry names, FIFO order
_pl_qslug() { printf %s "${1#*-}"; }

pl_status() {
  local d f q="" e s since; d=$(pl_dir); f="$d/holder.json"
  for e in $(_pl_queue); do q="$q${q:+ }$(_pl_qslug "$e")"; done
  if _pl_holder_live; then
    s=$(_pl_get "$f" slug); since=$(_pl_get "$f" since)
    printf 'held by %s since %s (%s) · queue: %s\n' "$s" "$(date -r "$since" '+%H:%M:%S' 2>/dev/null || echo "$since")" "$(_pl_get "$f" by)" "${q:--}"
  else
    printf 'free · queue: %s\n' "${q:--}"
  fi
}

pl_acquire() {  # <slug> <timeout-s>
  local slug=$1 timeout=${2:-1800} d entry="" deadline now e head lr lrs lrt take pos hs
  [ -n "$slug" ] || { echo "pl_acquire: slug?" >&2; return 2; }
  d=$(pl_dir); deadline=$(( $(_pl_now) + timeout ))
  _pl_lock || return 1
  for e in $(_pl_queue); do [ "$(_pl_qslug "$e")" = "$slug" ] && entry=$e; done
  if [ -z "$entry" ]; then entry="$(_pl_ms)-$slug"; echo "${BASHPID:-$$}" > "$d/queue/$entry"; else echo "${BASHPID:-$$}" > "$d/queue/$entry"; fi
  _pl_unlock
  while :; do
    _pl_lock || return 1
    _pl_clear_dead; _pl_prune_queue
    [ -f "$d/queue/$entry" ] || echo "${BASHPID:-$$}" > "$d/queue/$entry"
    take=""
    if [ ! -f "$d/holder.json" ] && ! _pl_listening; then
      now=$(_pl_now); head=$(_pl_queue | head -1); head=$(_pl_qslug "$head")
      lr="$d/last-release.json"; lrs=$(_pl_get "$lr" slug); lrt=$(_pl_get "$lr" at)
      if [ -n "$lrs" ] && [ "$lrs" = "$slug" ] && [ $(( now - ${lrt:-0} )) -lt "$(_pl_grace)" ]; then take=1
      elif [ "$head" = "$slug" ] && { [ -z "$lrt" ] || [ $(( now - lrt )) -ge "$(_pl_grace)" ]; }; then take=1
      fi
    fi
    if [ -n "$take" ]; then
      rm -f "$d/queue/$entry"; _pl_write_holder "$slug" pending agent; _pl_unlock; return 0
    fi
    if [ "$(_pl_now)" -ge "$deadline" ]; then
      pos=1; for e in $(_pl_queue); do [ "$e" = "$entry" ] && break; pos=$((pos + 1)); done
      hs=$(_pl_get "$d/holder.json" slug); [ -n "$hs" ] || { _pl_listening && hs="a process not under the lock" || hs="the grace period"; }
      rm -f "$d/queue/$entry"; _pl_unlock
      echo "queued: $pos behind $hs"; return 3
    fi
    _pl_unlock
    sleep 2
  done
}

pl_set_pgid() {  # <slug> <pgid>
  local d f; d=$(pl_dir); f="$d/holder.json"
  _pl_lock || return 1
  if [ "$(_pl_get "$f" slug)" = "$1" ]; then _pl_write_holder "$1" "$2" "$(_pl_get "$f" by)"; _pl_unlock; return 0; fi
  _pl_unlock; return 1
}

pl_release() {  # <slug> — only the holder's own slug releases
  local d f; d=$(pl_dir); f="$d/holder.json"
  _pl_lock || return 1
  if [ -f "$f" ] && [ "$(_pl_get "$f" slug)" = "$1" ]; then rm -f "$f"; _pl_write_release "$1"; _pl_unlock; return 0; fi
  _pl_unlock; return 1
}

pl_claim_human() {  # <slug> <pid> — non-blocking; a live holder → `held by <slug>`, 1
  local d f s; d=$(pl_dir); f="$d/holder.json"
  _pl_lock || return 1
  _pl_clear_dead
  if [ -f "$f" ]; then
    s=$(_pl_get "$f" slug)
    if [ "$s" != "$1" ] || [ "$(_pl_get "$f" by)" != human ]; then _pl_unlock; echo "held by $s"; return 1; fi
  fi
  _pl_write_holder "$1" "$2" human; _pl_unlock; return 0
}
