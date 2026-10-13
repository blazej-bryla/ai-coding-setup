#!/bin/bash
# PreToolUse (matcher: Edit|Write|MultiEdit) hook — project rules that Biome/ESLint can't see.
# Rules: ~/.agents/rules/<repo>.json, <repo> = the directory name of FE_REPO / BE_REPO (lib/config.sh);
# engine: rules-engine.jq.
# A rule fires only when an edit ADDS an occurrence of its pattern (more matches in the new
# text than in the old); `rule-ok: <id> <reason>` in the new text skips that rule.
#   block → deny with id + message;  warn → allow, message goes to the model as additionalContext.
# Every hit → ~/.agents/rules/hits.log. Fails open: any internal error → allow, logged to
# ~/.agents/rules/errors.log. No network.
set -u

RULES_DIR=${RULES_DIR:-$HOME/.agents/rules}
ENGINE_DIR=$(cd "$(dirname "$0")" && pwd)
. "$ENGINE_DIR/lib/config.sh"
fe_name=${FE_REPO##*/} be_name=${BE_REPO##*/}

logerr() { printf '%s\terror\t%s\n' "$(date '+%F %T')" "$*" >>"$RULES_DIR/errors.log" 2>/dev/null; exit 0; }
trap 'logerr "unexpected failure (line $LINENO)"' ERR

command -v jq >/dev/null 2>&1 || logerr "jq not found"
in=$(cat)
IFS=$'\037' read -r tool file sid cwd < <(printf '%s' "$in" | jq -r '[.tool_name // "", .tool_input.file_path // "", .session_id // "", .cwd // ""] | join("\u001f")' 2>/dev/null) \
  || logerr "bad hook input JSON"
[ -n "$file" ] || exit 0
case "$file" in /*) ;; *) file="$cwd/$file" ;; esac

# repo + root + session name from the path: main checkout or a <slug>-fe|-be worktree
repo= root= sess=
case "$file" in
  "$FE_REPO"/*) repo=$fe_name root=$FE_REPO ;;
  "$BE_REPO"/*) repo=$be_name root=$BE_REPO ;;
  "$WT_ROOT"/*)
    wt=${file#"$WT_ROOT"/}; wt=${wt%%/*}; root=$WT_ROOT/$wt; sess=$wt
    case "$(printf %s "$wt" | tr A-Z a-z)" in *-fe) repo=$fe_name ;; *-be) repo=$be_name ;; esac ;;
esac
[ -n "$repo" ] || exit 0
rules=$RULES_DIR/$repo.json
[ -f "$rules" ] || exit 0
rel=${file#"$root"/}
[ -n "$sess" ] || sess=$repo
[ -n "$sid" ] && sess="$sess (${sid:0:8})"

# old text for Write = the file as it is on disk (a rewrite that keeps an occurrence is no addition)
old=/dev/null
[ "$tool" = Write ] && [ -f "$file" ] && old=$file

out=$(printf '%s' "$in" | jq -r -L "$ENGINE_DIR" --slurpfile rules "$rules" --rawfile old "$old" --arg path "$rel" '
  include "rules-engine";
  (.tool_input) as $t
  | (if .tool_name == "Write" then [{old: $old, new: ($t.content // "")}]
     elif .tool_name == "MultiEdit" then [$t.edits[]? | {old: .old_string, new: .new_string}]
     else [{old: ($t.old_string // ""), new: ($t.new_string // "")}] end) as $pairs
  | check($rules[0]; $path; $pairs)[]
  | if .error then ["err", .id, (.error | tostring)] else ["hit", .id, .severity, .message] end
  | @tsv' 2>&1) || logerr "$repo/$rel: engine failed: $(printf '%s' "$out" | head -1)"
[ -n "$out" ] || exit 0

deny= warn= wids=
while IFS=$'\t' read -r kind id sev msg; do
  if [ "$kind" = err ]; then
    printf '%s\terror\t%s\t%s\trule %s: %s\n' "$(date '+%F %T')" "$repo" "$rel" "$id" "$sev" >>"$RULES_DIR/errors.log"
    continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$repo" "$rel" "$id" "$sev" "$sess" >>"$RULES_DIR/hits.log"
  msg=$(printf '%b' "$msg")   # @tsv escapes; undo for the message text
  if [ "$sev" = block ]; then
    deny+="rule $id ($rel): $msg"$'\n'"If this is a false positive, add \`rule-ok: $id <reason>\` as a comment in the new text."$'\n'
  else
    warn+="rule $id (warn, $rel): $msg"$'\n'; wids+="${wids:+ / }$id"
  fi
done <<<"$out"

if [ -n "$deny" ]; then
  jq -n --arg r "${deny}${warn}" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
elif [ -n "$warn" ]; then
  jq -n --arg c "${warn}Allowed; fix it now if the rule applies, or add \`rule-ok: <id> <reason>\` (id: $wids) if it doesn't." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
fi
exit 0
