#!/usr/bin/env bash
# tests/abcheck.test.sh — bin/abcheck against a stub `agent-browser` on PATH. One line per case; exit 1 on any failure.
# The stub reads the batch from stdin and answers each command from env: AB_TEXT_OK / AB_IDLE_OK (1|0),
# AB_CONSOLE (JSON array of console messages), AB_ERRORS (JSON array of page errors). It logs the batch to $T/cmds.json.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/bin/abcheck"
T=$(mktemp -d)
FAILS=0
ok() { echo "PASS  $1"; }
ko() { echo "FAIL  $1 — $2"; FAILS=$((FAILS + 1)); }

mkdir -p "$T/bin"
cat > "$T/bin/agent-browser" <<'EOF'
#!/usr/bin/env bash
cmds=$(cat); printf '%s' "$cmds" > "$STUB_LOG"
printf '%s' "$cmds" | jq -c \
  --argjson text_ok "${AB_TEXT_OK:-1}" --argjson idle_ok "${AB_IDLE_OK:-1}" \
  --argjson console "${AB_CONSOLE:-[]}" --argjson errors "${AB_ERRORS:-[]}" '
  map(. as $c | {command: $c, success: true, result: {}}
    | if $c[0] == "wait" and $c[1] == "--text" then
        (if $text_ok == 1 then . else .success = false | .error = "Timeout 25000ms waiting for text" end)
      elif $c[0] == "wait" then
        (if $idle_ok == 1 then . else .success = false | .error = "Timeout waiting for networkidle" end)
      elif $c[0] == "console" and ($c | length) == 1 then .result = {messages: $console}
      elif $c[0] == "errors" and ($c | length) == 1 then .result = {errors: $errors}
      elif $c[0] == "network" and ($c | index("--clear")) == null then .result = {requests: []}
      elif $c[0] == "eval" then .result = {result: ({u: "http://localhost:3000/x", t: "X", pw: false, x: "page text"} | tojson)}
      elif $c[0] == "screenshot" then .result = {path: $c[-1]}
      else . end)'
EOF
chmod +x "$T/bin/agent-browser"
export PATH="$T/bin:$PATH" STUB_LOG="$T/cmds.json"
HYD='[{"type":"error","text":"Warning: Each child  in a list\nshould have a unique \"key\" prop."},{"type":"log","text":"hello"}]'
NEW='[{"type":"error","text":"TypeError: x is undefined"}]'
# run <name> [env…] -- [abcheck args…] → exit code; output in $T/<name>.out
run() {
  local name=$1; shift; local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  env ${envs[@]+"${envs[@]}"} "$A" "$@" >"$T/$name.out" 2>&1; echo $?
}
has() { grep -qF -- "$2" "$T/$1.out"; }

# 1. pass: expectation found, clean console
rc=$(run pass -- s http://x "Invoices" "$T/pass.png")
if [ "$rc" = 0 ] && has pass "PASS expectation" && has pass "verdict: pass" && has pass "shot: $T/pass.png"; then ok "pass → exit 0"; else ko "pass" "rc=$rc $(cat "$T/pass.out")"; fi

# 2. expectation not found → fail, exit 1, page text shown
rc=$(run nofind AB_TEXT_OK=0 -- s http://x "Invoices" -)
if [ "$rc" = 1 ] && has nofind "FAIL expectation" && has nofind "text: page text" && has nofind "verdict: fail"; then ok "expectation missing → exit 1"; else ko "expectation fail" "rc=$rc $(cat "$T/nofind.out")"; fi

# 3. --before: expectation missing + console error → exit 0, verdict before, .errors holds normalised texts
rc=$(run before AB_TEXT_OK=0 "AB_CONSOLE=$HYD" 'AB_ERRORS=[{"message":"Hydration  failed"}]' -- --before s http://x "Invoices" "$T/b.png")
exp=$(printf '%s\n%s' 'Warning: Each child in a list should have a unique "key" prop.' 'Hydration failed')
if [ "$rc" = 0 ] && has before "verdict: before (not gated)" && has before "FAIL console errors: 1" && [ "$(cat "$T/b.png.errors" 2>/dev/null)" = "$exp" ]; then ok "--before → exit 0, .errors written"; else ko "--before" "rc=$rc errors=$(cat "$T/b.png.errors" 2>/dev/null) $(cat "$T/before.out")"; fi

# 4. --before without a shot path → usage error
rc=$(run beforenoshot -- --before s http://x "Invoices" -)
if [ "$rc" = 2 ]; then ok "--before with - shot → exit 2"; else ko "--before no shot" "rc=$rc"; fi

# 5. --known-errors: the before shot's console and page errors are known → pass
rc=$(run known "AB_CONSOLE=$HYD" 'AB_ERRORS=[{"message":"Hydration failed"}]' -- --known-errors "$T/b.png.errors" s http://x "Invoices" "$T/k.png")
if [ "$rc" = 0 ] && has known "PASS console errors: 0" && has known "PASS page errors: 0" && has known "known: 1 console, 1 page" && has known "verdict: pass"; then ok "--known-errors → known errors pass"; else ko "--known-errors" "rc=$rc $(cat "$T/known.out")"; fi

# 6. an error not in the known file still fails
rc=$(run unknown "AB_CONSOLE=$NEW" -- --known-errors "$T/b.png.errors" s http://x "Invoices" "$T/u.png")
if [ "$rc" = 1 ] && has unknown "FAIL console errors: 1 | TypeError: x is undefined" && has unknown "known: 0 console, 0 page"; then ok "unknown error → still fails"; else ko "unknown error" "rc=$rc $(cat "$T/unknown.out")"; fi

# 7. missing known file → treated as empty
rc=$(run nofile "AB_CONSOLE=$NEW" -- --known-errors "$T/none.errors" s http://x "Invoices" "$T/n.png")
if [ "$rc" = 1 ] && has nofile "known: file missing"; then ok "missing known file → known: file missing"; else ko "missing known file" "rc=$rc $(cat "$T/nofile.out")"; fi

# 8. expectation + shot: idle wait follows the text wait; not idle → note, still pass
rc=$(run idle AB_IDLE_OK=0 -- s http://x "Invoices" "$T/i.png")
order=$(jq -c '[.[] | select(.[0] == "wait")]' "$T/cmds.json")
if [ "$rc" = 0 ] && has idle "note: not idle after expectation — Timeout waiting for networkidle" && has idle "verdict: pass" \
   && [ "$order" = '[["wait","--text","Invoices"],["wait","--load","networkidle"]]' ]; then ok "not idle after expectation → note, pass"; else ko "idle note" "rc=$rc order=$order $(cat "$T/idle.out")"; fi

# 9. expectation without a shot → no extra idle wait
run noshot -- s http://x "Invoices" - >/dev/null
n=$(jq '[.[] | select(.[0] == "wait")] | length' "$T/cmds.json")
if [ "$n" = 1 ]; then ok "no shot → single wait"; else ko "no shot waits" "waits=$n"; fi

echo "fixtures: $T"
[ "$FAILS" = 0 ]
