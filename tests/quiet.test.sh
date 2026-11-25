#!/usr/bin/env bash
# tests/quiet.test.sh — bin/quiet one-string form: plain commands run, parentheses are literal path characters,
# shell syntax and non-tool first words are refused. One line per case; exit 1 on any failure. Needs node.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
Q="$ROOT/bin/quiet"
T=$(mktemp -d)
FAILS=0
ok() { echo "PASS  $1"; }
ko() { echo "FAIL  $1 — $2"; FAILS=$((FAILS + 1)); }
# run <name> <args…> → exit code; output in $T/<name>.out (run from $T so relative paths stay inside it)
run() { local name=$1; shift; (cd "$T" && "$Q" "$@") >"$T/$name.out" 2>&1; echo $?; }
has() { grep -qF -- "$2" "$T/$1.out"; }

command -v node >/dev/null || { echo "SKIP  node missing"; exit 0; }

# 1. plain one-string command → one ok line
rc=$(run plain "node -e 0")
if [ "$rc" = 0 ] && has plain "ok: node -e 0" && [ "$(wc -l <"$T/plain.out" | tr -d ' ')" = 1 ]; then ok "plain → ok line"; else ko "plain" "rc=$rc $(cat "$T/plain.out")"; fi

# 2. parentheses in a path (route group) → passed to node, which fails on the missing file
rc=$(run parens "node apps/(x)/missing.js")
if [ "$rc" != 0 ] && [ "$rc" != 2 ] && has parens "FAIL (exit $rc): node apps/(x)/missing.js" && has parens "apps/(x)/missing.js" && ! has parens "shell syntax"; then ok "parens → FAIL from node, not shell syntax"; else ko "parens" "rc=$rc $(cat "$T/parens.out")"; fi

# 3. shell syntax → refused before running anything
rc=$(run semi "node -e 0; ls")
if [ "$rc" = 2 ] && has semi "quiet: shell syntax in 'node -e 0; ls'"; then ok "';' → shell syntax refusal"; else ko "semicolon" "rc=$rc $(cat "$T/semi.out")"; fi

# 4. a first word outside the tool list → refused
rc=$(run git "git status")
if [ "$rc" = 2 ] && has git "quiet: 'git' is not a test/lint/typecheck/build tool"; then ok "git → refused"; else ko "git" "rc=$rc $(cat "$T/git.out")"; fi

# 5. trailing -n N after the one string → used as the line count
rc=$(run trailfail "node -e process.exit(1)" -n 5)
if [ "$rc" = 1 ] && has trailfail "FAIL (exit 1): node -e process.exit(1)" && has trailfail "last 5 lines"; then ok "trailing -n on failure → last 5 lines"; else ko "trailing -n fail" "rc=$rc $(cat "$T/trailfail.out")"; fi
rc=$(run trailok "node -e 0" -n 5)
if [ "$rc" = 0 ] && has trailok "ok: node -e 0"; then ok "trailing -n on success → ok line"; else ko "trailing -n ok" "rc=$rc $(cat "$T/trailok.out")"; fi

[ "$FAILS" = 0 ]
