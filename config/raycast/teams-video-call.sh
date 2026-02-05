#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Teams: Video Call (Select Person + Tenant)
# @raycast.mode silent
# @raycast.packageName Teams
# @raycast.description Pick a person from CSV (supports multiple tenants), open tenant-pinned chat, then start a video call
# @raycast.shellPath /usr/bin/env bash
# Optional: type part of a first/last name (or email) to filter the list
# @raycast.argument1 { "type": "text", "placeholder": "Search (name or email)", "optional": true }

set -euo pipefail

# Log stdout/stderr so Raycast "Process tried to run but failed" is diagnosable
LOG_FILE="/tmp/raycast-teams-video-call.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "--- $(date) ---"

CSV_FILE="$HOME/.config/raycast/teams-people.csv"
QUERY="${1:-}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "Missing CSV: $CSV_FILE"
  echo "Create it with lines like: name,email,tenantId"
  exit 1
fi

# Build a selectable list from CSV: "Name — email || tenantId"
# Ignore empty lines and lines starting with '#'
# If QUERY is provided, filter by name/email (case-insensitive)
LIST=$(awk -F',' 'NF>=3 && $0 !~ /^[[:space:]]*#/ {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3);
  if (length($1)>0 && length($2)>0 && length($3)>0) {
    print $1 " — " $2 " || " $3
  }
}' "$CSV_FILE")

if [[ -n "$QUERY" ]]; then
  # shellcheck disable=SC2001
  Q=$(printf "%s" "$QUERY" | tr '[:upper:]' '[:lower:]')
  LIST=$(printf "%s\n" "$LIST" | awk -v q="$Q" 'BEGIN{IGNORECASE=1} index(tolower($0), q) > 0')
fi

if [[ -z "$LIST" ]]; then
  if [[ -n "$QUERY" ]]; then
    echo "No matches for: $QUERY"
  else
    echo "No entries found in $CSV_FILE"
  fi
  exit 1
fi

# Count matches (non-empty lines)
MATCH_COUNT=$(printf "%s\n" "$LIST" | awk 'NF{c++} END{print c+0}')

# If there's exactly one match, skip the picker
if [[ "$MATCH_COUNT" -eq 1 ]]; then
  CHOICE=$(printf "%s\n" "$LIST" | awk 'NF{print; exit}')
else
  # Use macOS chooser to pick an entry (shown only when 2+ matches)
  # Display format: "Name — email" (tenantId is hidden after "||")
  CHOICE=$(osascript <<APPLESCRIPT
set raw to "${LIST//\"/\\\"}"
set rows to paragraphs of raw
set displayRows to {}
repeat with r in rows
  if (r as text) is not "" then
    set AppleScript's text item delimiters to " || "
    set parts to text items of (r as text)
    set AppleScript's text item delimiters to ""
    if (count of parts) ≥ 2 then
      set end of displayRows to (item 1 of parts) as text
    end if
  end if
end repeat
set picked to choose from list displayRows with title "Teams Video Call" with prompt "Pick a person to video call" without empty selection allowed
if picked is false then
  return ""
end if
set pickedDisplay to item 1 of picked
-- Map display string back to full row (to recover tenantId)
repeat with r in rows
  if r starts with pickedDisplay then
    return r as text
  end if
end repeat
return ""
APPLESCRIPT
  )
fi

if [[ -z "$CHOICE" ]]; then
  echo "Cancelled"
  exit 0
fi

# Parse choice string
# CHOICE format: "Name — email || tenantId"
LEFT="${CHOICE% || *}"
TENANT_ID="${CHOICE##* || }"
NAME="${LEFT%% — *}"
EMAIL="${LEFT#* — }"

if [[ -z "$EMAIL" || -z "$TENANT_ID" || "$LEFT" == "$CHOICE" || "$TENANT_ID" == "$CHOICE" ]]; then
  echo "Invalid selection"
  exit 1
fi

# Open chat in the selected tenant
open "msteams://teams.microsoft.com/l/chat/0/0?tenantId=${TENANT_ID}&users=${EMAIL}"

# Give Teams time to activate and load the chat
sleep 1.2

# Start video call via keyboard shortcut (adjust if your Teams shortcut differs)
osascript <<'APPLESCRIPT'
tell application "Microsoft Teams" to activate
delay 0.3
tell application "System Events"
  keystroke "s" using {command down, shift down}
end tell
APPLESCRIPT

echo "Calling ${NAME}"
