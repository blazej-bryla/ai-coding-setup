#!/usr/bin/env bash
# tests/review-queue.test.sh — bin/review-queue: status heartbeat file (start, reviewing, done upsert, end, .tmp, 7-day prune, malformed); queue states (new, delta, ready, skip, later, malformed → new),
# slug fallback, stack ordering, the max cap; verdict rules 1–5, the --rereview rules 1–6, first-match order. No network:
# the PR list comes from REVIEW_QUEUE_JSON, findings files from a temp REVIEW_QUEUE_SCRATCH. Needs jq.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RQ="$ROOT/bin/review-queue"
T=$(mktemp -d)
FAILS=0
ok() { echo "PASS  $1"; }
ko() { echo "FAIL  $1 — $2"; FAILS=$((FAILS + 1)); }

command -v jq >/dev/null || { echo "SKIP  jq missing"; exit 0; }

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc
D=dddddddddddddddddddddddddddddddddddddddd
E=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
O=0000000000000000000000000000000000000000

# findings <slug> <pr> <head> <status> — a findings.md with a summary block; status "-" omits the line
findings() {
  mkdir -p "$T/scratch/$1/review"
  { echo "<!-- summary -->"; echo "head: $3 pr: #$2"; [ "$4" = - ] || echo "status: $4"
    echo "findings: 0"; echo "actionable: none"; echo "<!-- /summary -->"; } >"$T/scratch/$1/review/findings.md"
}
pr() { printf '{"number":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s","title":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
queue() { REVIEW_QUEUE_SCRATCH="$T/scratch" REVIEW_QUEUE_JSON="$1" "$RQ" acme/widget-app ${2:+"$2"} 2>&1; }

# ---- queue ------------------------------------------------------------------------------------------------
findings abc-11 11 "$A" ready        # same head, ready  → ready
findings abc-12 12 "$O" ready        # head moved        → delta
findings abc-13 13 "$C" submitted    # same head, sent   → skip
findings abc-14 14 "$D" -            # no status line    → new (malformed)
J="[$(pr 11 feat/ABC-11-x "$A" main "Eleven"),$(pr 12 feat/abc-12 "$B" main "Twelve"),$(pr 13 abc-13 "$C" main "Thirteen"),$(pr 14 abc-14 "$D" main "Fourteen"),$(pr 15 no-key-branch "$E" main "Fifteen")]"
out=$(queue "$J" max:5)
echo "$out" | grep -qx "ready #11 slug=abc-11 head=$A base=main Eleven" && ok "same head + ready → ready (slug lowercased)" || ko "ready" "$out"
echo "$out" | grep -qx "delta 0000000..bbbbbbb #12 slug=abc-12 head=$B base=main Twelve" && ok "moved head → delta old..new" || ko "delta" "$out"
echo "$out" | grep -qx "skip #13 slug=abc-13 head=$C base=main Thirteen" && ok "same head + submitted → skip" || ko "skip" "$out"
echo "$out" | grep -qx "new #14 slug=abc-14 head=$D base=main Fourteen" && ok "malformed findings (no status) → new" || ko "malformed" "$out"
echo "$out" | grep -qx "new #15 slug=widget-app-pr-15 head=$E base=main Fifteen" && ok "no key in branch → <repo>-pr-<N>" || ko "slug fallback" "$out"
echo "$out" | tail -1 | grep -qx "queue: new 2 delta 1 ready 1 skip 1 later 0" && ok "summary counts" || ko "summary" "$out"

# head line for another PR number → malformed → new
findings abc-16 99 "$A" ready
out=$(queue "[$(pr 16 abc-16 "$A" main "Sixteen")]")
echo "$out" | grep -qx "new #16 slug=abc-16 head=$A base=main Sixteen" && ok "head line for another PR → new" || ko "other PR" "$out"

# stack ordering: 10 on 20 on 30 (base = the other's head), 25 independent → each after its base, then by number
J="[$(pr 20 abc-20 "$A" abc-30 "Top"),$(pr 30 abc-30 "$B" main "Bottom"),$(pr 25 abc-25 "$C" main "Other"),$(pr 10 abc-10 "$D" abc-20 "Very top")]"
out=$(queue "$J" max:9 | sed -n 's/^new #\([0-9]*\).*/\1/p' | tr '\n' ' ')
[ "$out" = "25 30 20 10 " ] && ok "stack order: bottom before stacked, then by number ($out)" || ko "stack order" "$out"

# max cap: new/delta beyond N → later; ready/skip are not counted against N; default N=2
findings abc-41 41 "$A" ready
J="[$(pr 40 abc-40 "$A" main "a"),$(pr 41 abc-41 "$A" main "b"),$(pr 42 abc-42 "$A" main "c"),$(pr 43 abc-43 "$A" main "d")]"
out=$(queue "$J")
st=$(echo "$out" | awk '{print $1 $2}' | tr '\n' ' ')
[ "$st" = "new#40 ready#41 new#42 later#43 queue:new " ] && echo "$out" | tail -1 | grep -qx "queue: new 2 delta 0 ready 1 skip 0 later 1" \
  && ok "default max 2: third new → later" || ko "max cap" "$out"
out=$(queue "$J" max:1)
echo "$out" | grep -q "^later #42 " && ok "max:1 → second new is later" || ko "max:1" "$out"

# gh failure → exit 2 with its lines (stub gh on PATH, no REVIEW_QUEUE_JSON)
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "gh: boom" >&2\nexit 1\n' >"$T/bin/gh"; chmod +x "$T/bin/gh"
out=$(PATH="$T/bin:$PATH" REVIEW_QUEUE_SCRATCH="$T/scratch" "$RQ" acme/widget-app 2>&1); rc=$?
[ "$rc" = 2 ] && echo "$out" | grep -q "gh: boom" && ok "gh failure → exit 2 with its output" || ko "gh failure" "rc=$rc $out"

# ---- verdict ----------------------------------------------------------------------------------------------
# vf <name> <actionable lines…> — a findings file with those actionable lines
vf() {
  local f="$T/$1.md"; shift
  { echo "<!-- summary -->"; echo "head: $A pr: #1"; echo "status: ready"; echo "findings: $#"; echo "actionable:"
    for l in "$@"; do echo "$l"; done; echo "<!-- /summary -->"; echo; echo "## #1 x"; } >"$f"
  echo "$f"
}
V() { local f=$1; shift; "$RQ" verdict "$f" "$@" 2>&1; }
base() { echo --lines 100 --draft n --checks green --auth n --shared n; }

BLK=$(vf blk "- #1 issue (blocking, proven) src/a.ts:1 — breaks AC" "- #2 issue (proven) src/b.ts:2 — bug" \
  "- #3 suggestion (proven) src/c.ts:3 — tidy" "- #4 issue (plausible) src/d.ts:4 — maybe")
out=$(V "$BLK" $(base))
[ "$out" = "verdict: REQUEST_CHANGES — blocking finding #1
post: 1,2" ] && ok "rule 1: blocking → REQUEST_CHANGES, post proven blocking + issue" || ko "rule 1" "$out"
out=$(V "$BLK" --lines 100 --draft y --checks pending --auth n --shared n)
echo "$out" | head -1 | grep -q "^verdict: REQUEST_CHANGES" && ok "first match: blocking beats pending" || ko "blocking vs pending" "$out"

ISS=$(vf iss "- #1 issue (proven) src/a.ts:1 — bug" "- #2 suggestion (proven) src/b.ts:2 — tidy" \
  "- #3 nitpick (proven) src/c.ts:3 — name" "- #4 question (proven) src/d.ts:4 — why" "- #5 suggestion (unverified) src/e.ts:5 — maybe")
out=$(V "$ISS" --lines 100 --draft n --checks pending --auth n --shared n)
[ "$out" = "verdict: DEFER — CI checks pending
post: none" ] && ok "rule 2: pending → DEFER, post none" || ko "rule 2" "$out"
out=$(V "$ISS" --lines 100 --draft y --checks pending --auth n --shared n)
echo "$out" | head -1 | grep -q "^verdict: DEFER" && ok "first match: pending beats draft" || ko "pending vs draft" "$out"
out=$(V "$ISS" $(base))
[ "$out" = "verdict: COMMENT — proven issue #1
post: 1,2" ] && ok "rule 3: proven issue → COMMENT, post issue + suggestion (no nitpick/question/unverified)" || ko "rule 3" "$out"

SUG=$(vf sug "- #1 suggestion (proven) src/a.ts:1 — tidy" "- #2 nitpick (proven) src/b.ts:2 — name")
for c in "draft y:draft PR" "checks red:CI red" "lines 900:900 changed lines > 500" "auth y:touches auth" "shared y:touches a shared module"; do
  flag=${c%%:*}; why=${c#*:}
  args=$(base | sed "s/--${flag%% *} [^ ]*/--$flag/")
  out=$(V "$SUG" $args)
  [ "$out" = "verdict: COMMENT — no approve: $why
post: 1" ] && ok "rule 4: --$flag → COMMENT naming '$why'" || ko "rule 4 $flag" "$out"
done
out=$(V "$SUG" $(base))
[ "$out" = "verdict: APPROVE — no blocking or proven issue, no approve blocker
post: 1" ] && ok "rule 5: clean → APPROVE, post proven suggestions" || ko "rule 5" "$out"

PLA=$(vf pla "- #1 issue (plausible) src/a.ts:1 — maybe" "- #2 issue (unverified) src/b.ts:2 — maybe" "- #3 thought (proven) src/c.ts:3 — idea")
out=$(V "$PLA" $(base))
[ "$out" = "verdict: APPROVE — no blocking or proven issue, no approve blocker
post: none" ] && ok "only plausible/unverified issues → APPROVE, post none" || ko "only plausible" "$out"

NONE=$(vf none); sed -i.bak 's/^actionable:$/actionable: none/' "$NONE"
out=$(V "$NONE" $(base))
echo "$out" | head -1 | grep -q "^verdict: APPROVE" && echo "$out" | grep -qx "post: none" && ok "actionable: none → APPROVE" || ko "none" "$out"

# ---- verdict --rereview y (REREVIEW_RULE4=drop in bin/review-queue) ----------------------------------------
# vr <name> <carried line | -> <actionable lines…> — a re-review findings file; "-" omits the carried line
vr() {
  local f="$T/$1.md" c=$2; shift 2
  { echo "<!-- summary -->"; echo "head: $A pr: #1"; echo "status: ready"; [ "$c" = - ] || echo "$c"
    echo "findings: $#"; echo "actionable:"; for l in "$@"; do echo "$l"; done; echo "<!-- /summary -->"; } >"$f"
  echo "$f"
}
RR() { local f=$1; shift; V "$f" "$@" --rereview y; }

RFIX=$(vr rfix "carried: fixed 3 · not fixed 0 · obsolete 1 · disputed 0" "- #1 suggestion (proven) src/a.ts:1 — tidy")
out=$(RR "$RFIX" $(base))
[ "$out" = "verdict: APPROVE — previous points fixed, no blocking or proven issue
post: 1" ] && ok "rereview 6: all fixed → APPROVE, post new proven suggestion" || ko "rereview approve" "$out"
for fl in "--shared y" "--auth y" "--lines 900"; do
  args=$(base | sed "s/${fl%% *} [^ ]*/$fl/")
  out=$(RR "$RFIX" $args)
  echo "$out" | head -1 | grep -q "^verdict: APPROVE" && ok "rereview 5 (drop): $fl does not block APPROVE" || ko "rereview drop $fl" "$out"
done
out=$(V "$RFIX" --lines 100 --draft n --checks green --auth n --shared y)
echo "$out" | head -1 | grep -qx "verdict: COMMENT — no approve: touches a shared module" && ok "same file without --rereview: --shared y still blocks" || ko "rereview n shared" "$out"
for c in "draft y:draft PR" "checks red:CI red"; do
  flag=${c%%:*}; why=${c#*:}
  out=$(RR "$RFIX" $(base | sed "s/--${flag%% *} [^ ]*/--$flag/"))
  [ "$out" = "verdict: COMMENT — no approve: $why
post: 1" ] && ok "rereview 5: --$flag still blocks → COMMENT" || ko "rereview 5 $flag" "$out"
done

RNF=$(vr rnf "carried: fixed 1 · not fixed 1 · obsolete 0 · disputed 0" \
  "- #1 issue (proven) src/a.ts:1 — bug [carried: not fixed]" "- #2 suggestion (proven) src/b.ts:2 — tidy")
out=$(RR "$RNF" $(base))
[ "$out" = "verdict: COMMENT — proven issue #1
post: 2" ] && ok "rereview 4: carried not-fixed issue → COMMENT, carried not posted" || ko "rereview 4" "$out"

RDIS=$(vr rdis "carried: fixed 1 · not fixed 0 · obsolete 0 · disputed 1" \
  "- #1 issue (proven) src/a.ts:1 — bug [carried: disputed]" "- #2 issue (proven) src/b.ts:2 — new bug")
out=$(RR "$RDIS" $(base))
[ "$out" = "verdict: COMMENT — disputed point, needs the reviewer
post: 2" ] && ok "rereview 3: disputed → COMMENT (beats proven issue), carried not posted" || ko "rereview 3" "$out"
out=$(RR "$RDIS" --lines 100 --draft n --checks pending --auth n --shared n)
[ "$out" = "verdict: DEFER — CI checks pending
post: none" ] && ok "rereview first match: pending beats disputed" || ko "pending vs disputed" "$out"
RDM=$(vr rdm - "- #1 question (plausible) src/a.ts:1 — why [carried: disputed]")
out=$(RR "$RDM" $(base))
echo "$out" | head -1 | grep -qx "verdict: COMMENT — disputed point, needs the reviewer" && ok "rereview: disputed marker without carried line → COMMENT" || ko "disputed marker" "$out"

RBLK=$(vr rblk "carried: fixed 0 · not fixed 1 · obsolete 0 · disputed 1" \
  "- #1 issue (blocking, proven) src/a.ts:1 — breaks AC [carried: not fixed]" "- #2 issue (proven) src/b.ts:2 — new bug")
out=$(RR "$RBLK" --lines 100 --draft n --checks pending --auth n --shared n)
[ "$out" = "verdict: REQUEST_CHANGES — blocking finding #1
post: 2" ] && ok "rereview 1: carried blocking → REQUEST_CHANGES (beats pending, disputed), carried not posted" || ko "rereview 1" "$out"

out=$(RR "$SUG" --lines 100 --draft n --checks green --auth n --shared y)
echo "$out" | head -1 | grep -q "^verdict: APPROVE" && ok "rereview: no carried line → counts zero" || ko "no carried line" "$out"
for f in "$BLK" "$ISS" "$SUG" "$PLA"; do
  [ "$(V "$f" $(base))" = "$(V "$f" $(base) --rereview n)" ] || ko "--rereview n differs" "$f"
done; ok "--rereview n = no flag on the existing fixtures"
V "$SUG" $(base) --rereview x >/dev/null; [ $? = 2 ] && ok "--rereview x → usage, exit 2" || ko "rereview usage" "exit not 2"

printf 'no summary here\n' >"$T/bad.md"
V "$T/bad.md" $(base) >/dev/null; [ $? = 2 ] && ok "no summary block → exit 2" || ko "bad file" "exit not 2"
V "$SUG" --lines 100 --draft n >/dev/null; [ $? = 2 ] && ok "missing flags → usage, exit 2" || ko "usage" "exit not 2"

# ---- status (heartbeat file) -------------------------------------------------------------------------------
RUN="$T/run"
ST() { REVIEW_LOOP_RUN="$RUN" "$RQ" status acme/widget-app "$@"; }
SF="$RUN/acme__widget-app.json"
J() { jq -c "$1" "$SF"; }
ISO='^"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"$'

printf 'new #5 slug=abc-5 head=x base=main T\nqueue: new 1 delta 2 ready 3 skip 4 later 5\n' >"$T/q.out"
ST start "$T/q.out" && [ -f "$SF" ] && [ "$(J .repo)" = '"acme/widget-app"' ] \
  && [ "$(J .queue)" = '{"new":1,"delta":2,"ready":3,"skip":4,"later":5}' ] \
  && [ "$(J '[.sweep_ended, .running]')" = '[null,null]' ] && J .sweep_started | grep -Eq "$ISO" \
  && ok "status start: repo, queue counts, sweep_started, ended/running null" || ko "status start" "$(cat "$SF" 2>&1)"
ST pr 12 reviewing 2/3 && [ "$(J '.running | [.pr, .i, .n]')" = '[12,2,3]' ] && J .running.since | grep -Eq "$ISO" \
  && ok "status pr reviewing: running {pr, i, n, since}" || ko "status reviewing" "$(cat "$SF")"
ST pr 12 done COMMENT "no approve: touches auth" https://example.test/r/1 needs-you \
  && [ "$(J '.results["12"] | [.event, .reason, .url, .fixed, .needs_you]')" = '["COMMENT","no approve: touches auth","https://example.test/r/1",null,true]' ] \
  && [ "$(J .running)" = null ] && ok "status pr done: result recorded, needs-you, running cleared" || ko "status done" "$(cat "$SF")"
ST pr 12 done APPROVE "previous points fixed" - fixed 2/3 \
  && [ "$(J '.results["12"] | [.event, .url, .fixed, .needs_you]')" = '["APPROVE",null,"2/3",false]' ] \
  && [ "$(J '.results | length')" = 1 ] && ok "status pr done again: upsert replaces, '-' → null url, fixed a/b" || ko "status upsert" "$(cat "$SF")"
ST end && J .sweep_ended | grep -Eq "$ISO" && ok "status end: sweep_ended set" || ko "status end" "$(cat "$SF")"
ls -a "$RUN" | grep -q tmp && ko "status atomic" "a .tmp file is left" || ok "status: written via .tmp + mv, nothing left behind"
ST start "$T/q.out" && [ "$(J '.results | keys')" = '["12"]' ] && [ "$(J .sweep_ended)" = null ] \
  && ok "status start: results kept from the previous file" || ko "status keep" "$(cat "$SF")"

# 7-day pruning: an 8-day-old result and one without a readable time go; a 6-day-old one stays
old=$(date -u -v-8d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ)
recent=$(date -u -v-6d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '6 days ago' +%Y-%m-%dT%H:%M:%SZ)
jq --arg o "$old" --arg r "$recent" '.results += {"1": {event: "APPROVE", at: $o}, "2": {event: "APPROVE", at: $r}, "3": {event: "APPROVE", at: "yesterday"}}' \
  "$SF" >"$T/p.json" && mv "$T/p.json" "$SF"
ST end && [ "$(J '.results | keys')" = '["12","2"]' ] && ok "status: results older than 7 days (or undated) dropped on write" || ko "status prune" "$(J .results)"

printf '{not json' >"$SF"
err=$(ST pr 9 done DEFER "CI checks pending" - 2>&1 >/dev/null); rc=$?
[ $rc = 0 ] && echo "$err" | grep -q "malformed" && [ "$(J '.results | keys')" = '["9"]' ] && [ "$(J .repo)" = '"acme/widget-app"' ] \
  && ok "status: malformed file → fresh start, said on stderr" || ko "status malformed" "rc=$rc err=$err"
ST start "$T/missing.out" 2>/dev/null && [ "$(J .queue)" = '{"new":0,"delta":0,"ready":0,"skip":0,"later":0}' ] \
  && ok "status start without a queue line: counts 0, still a heartbeat" || ko "status no queue" "$(cat "$SF")"
ST pr x reviewing 1/2 2>/dev/null; [ $? = 2 ] && ok "status pr x → usage, exit 2" || ko "status usage" "exit not 2"
ST pr 3 done APPROVE "r" - bogus 2>/dev/null; [ $? = 2 ] && ok "status done with an unknown flag → usage, exit 2" || ko "status flag usage" "exit not 2"

rm -rf "$T"
[ "$FAILS" = 0 ]
