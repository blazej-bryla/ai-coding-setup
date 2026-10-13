# Shared by rules-guard.sh (PreToolUse) and rules-check.sh (diffs).
# check($rules; $path; $pairs) → [{id, severity, message, lines}] — one entry per violated rule.
#   $path  = repo-relative path of the edited file
#   $pairs = [{old, new, start?}] — one per edit (Write: file on disk vs content; diff: one hunk)
# A rule is violated by a pair when its pattern matches MORE often in `new` than in `old`
# (touching a line that already had it never counts), and `new` carries no
# `rule-ok: <id> <reason>`. Matching is per line, like grep -E. A rule that fails to
# compile comes back as {id, error} instead of breaking the rest.

def esc: gsub("(?<c>[.+^$(){}|\\[\\]\\\\])"; "\\\(.c)");
def glob2re:
  "^" + (esc
    | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002")
    | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]")
    | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*")) + "$";
def globmatch($p): any(.[]?; . as $g | $p | test($g | glob2re));
def count($re): (split("\n") | map([match($re; "g")] | length) | add) // 0;
def hitlines($re; $start): [split("\n") | to_entries[] | select(.value | test($re)) | .key + $start];

def check($rules; $path; $pairs):
  [ $rules[]
    | select((.paths // ["**"]) | globmatch($path))
    | select((.exclude // []) | globmatch($path) | not)
    | . as $r
    | try (
        [ $pairs[]
          | (.start // 1) as $s
          | ((.new // "") | count($r.pattern)) as $n
          | ((.old // "") | count($r.pattern)) as $o
          | select($n > $o)
          | select((.new // "") | test("rule-ok:[[:space:]]*" + ($r.id | esc) + "[ \\t]+[^[:space:]]") | not)
          | (.new // "") | hitlines($r.pattern; $s) ] as $hits
        | if ($hits | length) > 0
          then {id: $r.id, severity: ($r.severity // "warn"), message: $r.message, lines: ($hits | add)}
          else empty end
      ) catch {id: ($r.id // "?"), error: .}
  ];
