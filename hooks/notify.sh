#!/bin/bash
# Notification hook: fires when a session needs you (permission prompt, question,
# idle waiting for input). Shows a macOS notification; optionally pushes to your
# phone via ntfy. Independent of Herdr's screen-based state detection, so it
# keeps working when the sidebar misreports a Claude pane.
set -u

in=$(cat)
where=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || basename "$PWD")
body=$(printf '%s' "$in" | jq -r '.message // .title // "needs your input"' 2>/dev/null)
title="Claude · $where"

osascript -e "display notification \"${body//\"/}\" with title \"$title\" sound name \"Glass\"" 2>/dev/null

# Phone push — set your topic (ntfy.sh or self-hosted) and uncomment:
# curl -fsS -H "Title: $title" -d "$body" "https://ntfy.sh/YOUR_TOPIC" >/dev/null 2>&1

exit 0
