#!/bin/bash
# rules-check.sh <repo> [<git-diff-range>]     <repo> = directory name of FE_REPO or BE_REPO
#   Runs ~/.agents/rules/<repo>.json over the ADDED lines of a diff in the current git
#   checkout (main or worktree) — default: uncommitted changes (vs HEAD) plus untracked
#   files. Same engine and semantics as rules-guard.sh, one diff hunk = one edit: a hunk
#   hits when it adds more matches than it removes and has no `rule-ok: <id> <reason>`.
#   Prints `file:line  severity  id  line-text`, or "no hits". Exit 0 either way.
#
# rules-check.sh --try <rule.json> <bad-file> <fix-file> [<repo-relative path>]
#   Tests a drafted rule (one JSON object): it must match <bad-file> (the offending hunk,
#   as added text) and must NOT match <fix-file> (the suggested fix). With a path, also
#   checks the rule's paths/exclude cover it. Exit 0 = good rule, 1 = not.
set -euo pipefail

ENGINE_DIR=$(cd "$(dirname "$0")" && pwd)
RULES_DIR=${RULES_DIR:-$HOME/.agents/rules}

if [ "${1:-}" = --try ]; then
  rule=$2 bad=$3 fix=$4 path=${5:-}
  jq -rn -L "$ENGINE_DIR" --slurpfile r "$rule" --rawfile bad "$bad" --rawfile fix "$fix" --arg p "$path" '
    include "rules-engine";
    ($r[0] | if $p == "" then .paths = ["**"] | .exclude = [] else . end) as $rule
    | (if $p == "" then "x" else $p end) as $path
    | (check([$rule]; $path; [{old: "", new: $bad}]) | length > 0) as $b
    | (check([$rule]; $path; [{old: "", new: $fix}]) | length > 0) as $f
    | "bad hunk: \(if $b then "matches" else "NO match" end)\nfix: \(if $f then "MATCHES" else "no match" end)"
      + (if $p != "" then "\npath \($p): \(if ($rule.paths | globmatch($p)) and (($rule.exclude // []) | globmatch($p) | not) then "covered" else "NOT covered" end)" else "" end)
      + "\n" + (if $b and ($f | not) then "rule ok" else "rule FAILS" end)' | tee /dev/stderr | tail -1 | grep -q '^rule ok$'
  exit
fi

repo=${1:?usage: rules-check.sh <repo> [<git-diff-range>]}
range=${2:-}
rules=$RULES_DIR/$repo.json
[ -f "$rules" ] || { echo "no rules file: $rules" >&2; exit 1; }
cd "$(git rev-parse --show-toplevel)"

changes() {
  if [ -n "$range" ]; then git diff -U0 --no-color --src-prefix=a/ --dst-prefix=b/ --no-ext-diff "$range"
  else
    git diff -U0 --no-color --src-prefix=a/ --dst-prefix=b/ --no-ext-diff HEAD
    git ls-files --others --exclude-standard -z | while IFS= read -r -d '' f; do
      git diff -U0 --no-color --src-prefix=a/ --dst-prefix=b/ --no-index /dev/null "$f" || true
    done
  fi
}

# unified diff → one JSON object per hunk: {path, start, old, new}
changes | awk '
  function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); gsub(/\r/, "\\r", s); return s }
  function join(arr, n,   i, s) { s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? "\\n" : "") arr[i]; return s }
  function flush() {
    if (path != "" && inhunk) printf "{\"path\":\"%s\",\"start\":%d,\"old\":\"%s\",\"new\":\"%s\"}\n", esc(path), start, join(ol, no), join(nl, nn)
    inhunk = 0; no = 0; nn = 0
  }
  /^diff --git / { flush(); path = ""; header = 1; next }
  header && /^\+\+\+ / { p = substr($0, 5); sub(/^b\//, "", p); path = (p == "/dev/null") ? "" : p; next }
  header && !/^@@ / { next }
  /^@@ / { flush(); header = 0; split($3, a, ","); start = substr(a[1], 2) + 0; inhunk = 1; next }
  inhunk && /^\+/ { nl[++nn] = esc(substr($0, 2)); next }
  inhunk && /^-/ { ol[++no] = esc(substr($0, 2)); next }
  END { flush() }
' | jq -rs -L "$ENGINE_DIR" --slurpfile rules "$rules" '
  include "rules-engine";
  [ .[] | . as $h | check($rules[0]; $h.path; [$h])[]
    | if .error then "error  rule \(.id): \(.error)"
      else .lines[] as $l | "\($h.path):\($l)  \(.severity)  \(.id)  \(($h.new | split("\n"))[$l - $h.start] | sub("^[[:space:]]+"; "") | .[0:120])" end ]
  | if length == 0 then "no hits" else .[] end'
