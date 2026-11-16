#!/usr/bin/env bash
# tests/refine-html.test.sh — bin/refine-html against fixture JSONs in a temp dir. One line per case; exit 1 on any failure.
# The UI locales come from temp REFINE_DIR copies (ui-pl.json there is synthesised), so the test also runs where
# only the public files exist. Diacritics are written as JSON \u escapes to keep this file free of Polish letters (the export denylist).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/bin/refine-html"
SRC_DIR="$ROOT/skills/kickoff/refine"
T=$(mktemp -d); export PYTHONDONTWRITEBYTECODE=1
FAILS=0
ok() { echo "PASS  $1"; }
ko() { echo "FAIL  $1 — $2"; FAILS=$((FAILS + 1)); }
# build <refine-dir> <name> → exit code; output in $T/<name>.out, page in $T/<name>.html
build() { REFINE_DIR="$1" "$R" "$T/$2.json" "$T/$2.html" >"$T/$2.out" 2>&1; echo $?; }
nofile() { [ ! -e "$T/$1.html" ]; }

# refine dirs: en+pl (ui-pl synthesised from ui-en), en only, pl with one key missing
mkdir -p "$T/both" "$T/en" "$T/badpl"
for d in both en badpl; do cp "$SRC_DIR/template.html" "$SRC_DIR/ui-en.json" "$T/$d/"; done
python3 -I - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
en = json.load(open(f"{t}/both/ui-en.json", encoding="utf-8"))
pl = {k: "pl:" + v for k, v in en.items()}
json.dump(pl, open(f"{t}/both/ui-pl.json", "w", encoding="utf-8"), ensure_ascii=False)
del pl["copy"]
json.dump(pl, open(f"{t}/badpl/ui-pl.json", "w", encoding="utf-8"), ensure_ascii=False)
EOF

cat > "$T/full.json" <<'EOF'
{"meeting":{"date":"2026-11-16","title":{"pl":"Refinement \u2014 za\u017c\u00f3\u0142\u0107 g\u0119\u015bl\u0105 ja\u017a\u0144","en":"Refinement \u2014 sprint 47"}},
 "issues":[
  {"id":"ABC-12","url":"https://linear.app/x/issue/ABC-12","title":"Eksport faktur do CSV",
   "summary":{"pl":"U\u017cytkownik pobiera faktury jako CSV.","en":"User downloads invoices as CSV."},
   "known":[{"pl":"Endpoint /invoices stronicuje po 50.","en":"/invoices paginates by 50.","source":"apps/api/src/invoices/controller.ts:42"}],
   "questions":[
    {"id":"ABC-12-q1","category":"contract","for":"be","weight":"blocker",
     "text":{"pl":"Czy pole \"notatka\" mo\u017ce zawiera\u0107 </script><b>HTML</b> & 'x'?","en":"Can the \"note\" field contain </script><b>HTML</b> & 'x'?"},
     "why":{"pl":"Escapowanie CSV.","en":"CSV escaping."},
     "proposal":{"pl":"Tak, RFC 4180.","en":"Yes, RFC 4180."}},
    {"id":"ABC-12-q2","category":"ux","for":"design","weight":"detail",
     "text":{"pl":"Gdzie stoi przycisk?","en":"Where does the button sit?"},
     "why":{"pl":"Sp\u00f3jno\u015b\u0107.","en":"Consistency."},"proposal":null}]},
  {"id":"ABC-13","url":"https://linear.app/x/issue/ABC-13","title":"Limity",
   "summary":{"pl":"Limit eksportu.","en":"Export limit."},"known":[],
   "questions":[
    {"id":"ABC-13-q1","category":"scope","for":"po","weight":"estimate",
     "text":{"pl":"Maksymalny zakres dat?","en":"Maximum date range?"},
     "why":{"pl":"Estymacja.","en":"Estimate."},"proposal":{"pl":"12 miesi\u0119cy.","en":"12 months."}}]}]}
EOF

# 1. valid, en+pl → ok line, no placeholders, data and UI blocks round-trip, no raw < > & in them, one inline JS
rc=$(build "$T/both" full)
chk=$(python3 -I - "$T" <<'EOF'
import json, re, sys
t = sys.argv[1]
h = open(f"{t}/full.html", encoding="utf-8").read()
out = []
if "__REFINE_" in h: out.append("placeholder left")
data = re.findall(r'<script id="data" type="application/json">(.*?)</script>', h, re.S)
ui = re.findall(r'<script id="ui" type="application/json">(.*?)</script>', h, re.S)
if len(data) != 1 or len(ui) != 1: out.append(f"blocks data={len(data)} ui={len(ui)}")
else:
    for name, blk in (("data", data[0]), ("ui", ui[0])):
        if any(c in blk for c in "<>&"): out.append(f"raw < > & in {name}")
    if json.loads(data[0]) != json.load(open(f"{t}/full.json", encoding="utf-8")): out.append("data mismatch")
    u = json.loads(ui[0])
    if sorted(u) != ["en", "pl"] or u["en"] != json.load(open(f"{t}/both/ui-en.json", encoding="utf-8")): out.append("ui mismatch")
if "\\u003c/script\\u003e" not in h: out.append("escaped </script> missing")
js = re.findall(r"<script>(.*?)</script>", h, re.S)
if len(js) != 1: out.append(f"inline js blocks={len(js)}")
else: open(f"{t}/page.js", "w", encoding="utf-8").write(js[0])
print("; ".join(out) or "ok")
EOF
)
if [ "$rc" = 0 ] && [ "$chk" = ok ] && grep -qF "(2 issues, 3 questions, ui: en,pl)" "$T/full.out"; then ok "valid en+pl → $(cat "$T/full.out")"; else ko "valid en+pl" "rc=$rc chk=$chk out=$(cat "$T/full.out")"; fi

# 2. inline JS parses
if command -v node >/dev/null; then
  if node --check "$T/page.js" 2>"$T/node.out"; then ok "inline JS: node --check"; else ko "inline JS" "$(head -3 "$T/node.out")"; fi
else ok "inline JS: node missing, skipped"; fi

# 3. invalid JSON → exit 1, no file
echo '{not json' > "$T/badj.json"
rc=$(build "$T/both" badj)
if [ "$rc" = 1 ] && nofile badj && grep -q 'invalid JSON' "$T/badj.out"; then ok "invalid JSON → exit 1, no file"; else ko "invalid JSON" "rc=$rc"; fi

# 4. missing text.en → exit 1, no file
python3 -I - "$T" <<'EOF'
import json, sys
t = sys.argv[1]
d = json.load(open(f"{t}/full.json", encoding="utf-8"))
del d["issues"][0]["questions"][0]["text"]["en"]
json.dump(d, open(f"{t}/noen.json", "w", encoding="utf-8"), ensure_ascii=False)
EOF
rc=$(build "$T/both" noen)
if [ "$rc" = 1 ] && nofile noen && grep -q 'text.en: string required' "$T/noen.out"; then ok "missing text.en → exit 1, no file"; else ko "missing text.en" "rc=$rc out=$(cat "$T/noen.out")"; fi

# 5. refine dir without ui-pl.json → ok, ui: en, UI block holds only en
cp "$T/full.json" "$T/enonly.json"
rc=$(build "$T/en" enonly)
keys=$(python3 -I -c 'import json,re,sys; h=open(sys.argv[1],encoding="utf-8").read(); print(",".join(sorted(json.loads(re.search(r"<script id=\"ui\" type=\"application/json\">(.*?)</script>",h,re.S).group(1)))))' "$T/enonly.html" 2>/dev/null)
if [ "$rc" = 0 ] && grep -qF ", ui: en)" "$T/enonly.out" && [ "$keys" = en ]; then ok "no ui-pl.json → ui: en"; else ko "en only" "rc=$rc keys=$keys out=$(cat "$T/enonly.out")"; fi

# 6. ui-pl.json with a missing key → exit 1 naming it, no file
cp "$T/full.json" "$T/badui.json"
rc=$(build "$T/badpl" badui)
if [ "$rc" = 1 ] && nofile badui && grep -q 'missing: copy' "$T/badui.out"; then ok "ui-pl.json missing key → exit 1 ($(cat "$T/badui.out"))"; else ko "ui key check" "rc=$rc out=$(cat "$T/badui.out")"; fi

echo "fixtures: $T"
[ "$FAILS" = 0 ]
