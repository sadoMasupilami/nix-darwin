#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Teams: Video Call (Select Person + Tenant)
# @raycast.mode silent
# @raycast.packageName Teams
# @raycast.description Pick a person from a private CSV, then open a Teams video call
# @raycast.shellPath /usr/bin/env bash
# @raycast.argument1 { "type": "text", "placeholder": "Search (name or email)", "optional": true }

set -euo pipefail
umask 077

CSV_FILE="${TEAMS_PEOPLE_CSV:-$HOME/.config/raycast/teams-people.csv}"
QUERY="${1:-}"
OPEN_CMD="${TEAMS_CALL_OPEN_CMD:-/usr/bin/open}"
OSASCRIPT_CMD="${TEAMS_CALL_OSASCRIPT_CMD:-/usr/bin/osascript}"
STATE_DIR="${TEAMS_CALL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/raycast-teams-call}"
STATUS_FILE="$STATE_DIR/status"

private_directory_mode() {
  local directory="$1"
  [[ ! -L "$directory" && -d "$directory" ]] || return 1
  [[ "$(/usr/bin/stat -f '%Lp' "$directory" 2>/dev/null || true)" == 700 ]]
}

initialize_private_state() {
  local parent="${STATE_DIR%/*}"
  [[ "$parent" != "$STATE_DIR" ]] || return 1

  if [[ -L "$STATE_DIR" || ( -e "$STATE_DIR" && ! -d "$STATE_DIR" ) ]]; then
    return 1
  fi
  if [[ -d "$STATE_DIR" ]] && ! private_directory_mode "$STATE_DIR"; then
    return 1
  fi

  /bin/mkdir -p "$STATE_DIR"
  private_directory_mode "$STATE_DIR"
}

write_status() {
  local status="$1"
  local temporary="$STATE_DIR/.status.$$"

  printf '%s\n' "$status" > "$temporary"
  /bin/chmod 600 "$temporary"
  /bin/mv -f "$temporary" "$STATUS_FILE"
}

if ! initialize_private_state; then
  echo "Das Teams-Statusverzeichnis ist nicht privat (erwartet: Modus 700)." >&2
  echo "Bitte die Rechte bewusst manuell mit chmod 700 korrigieren." >&2
  exit 1
fi
write_status "Bereit"

CONFIG_DIR="${CSV_FILE%/*}"
if ! private_directory_mode "$CONFIG_DIR"; then
  write_status "Fehler"
  echo "Das Teams-Konfigurationsverzeichnis ist nicht privat (erwartet: Modus 700)." >&2
  echo "Bitte einmal ausführen: chmod 700 ~/.config/raycast" >&2
  exit 1
fi

urlencode() {
  local value="$1"
  local encoded=""
  local character
  local i

  for ((i = 0; i < ${#value}; i++)); do
    character="${value:i:1}"
    case "$character" in
      [a-zA-Z0-9.~_-]) encoded+="$character" ;;
      *) printf -v character '%%%02X' "'$character"; encoded+="$character" ;;
    esac
  done

  printf '%s' "$encoded"
}

private_file_mode() {
  local file="$1"
  local mode=""

  mode="$(/usr/bin/stat -f '%Lp' "$file" 2>/dev/null || true)"
  if [[ -z "$mode" ]]; then
    mode="$(/usr/bin/stat -c '%a' "$file" 2>/dev/null || true)"
  fi

  [[ "$mode" == 600 ]]
}

if [[ -L "$CSV_FILE" || ! -f "$CSV_FILE" || ! -r "$CSV_FILE" ]]; then
  write_status "Fehler"
  echo "Die private Teams-Kontaktdatei fehlt oder ist nicht lesbar." >&2
  echo "Erwartet wird ~/.config/raycast/teams-people.csv." >&2
  exit 1
fi

if ! private_file_mode "$CSV_FILE"; then
  write_status "Fehler"
  echo "Die Teams-Kontaktdatei hat nicht den erwarteten Modus 600." >&2
  echo "Bitte einmal ausführen: chmod 600 ~/.config/raycast/teams-people.csv" >&2
  exit 1
fi

OWNER_UID="$(/usr/bin/stat -f '%u' "$CSV_FILE" 2>/dev/null || true)"
if [[ "$OWNER_UID" != "$(/usr/bin/id -u)" ]]; then
  write_status "Fehler"
  echo "Die Teams-Kontaktdatei gehört nicht dem aktuellen Benutzer." >&2
  exit 1
fi

WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/raycast-teams-call.XXXXXX")"
/bin/chmod 700 "$WORK_DIR"
trap '/bin/rm -rf "$WORK_DIR"' EXIT HUP INT TERM

CONTACTS_FILE="$WORK_DIR/contacts.tsv"
DISPLAY_FILE="$WORK_DIR/display.tsv"

# The temporary files are private (0600 through umask). Personal data is never
# written to the shared /tmp log used by the previous implementation.
awk -F',' -v q="$QUERY" '
  BEGIN { count = 0; query = tolower(q) }
  NF >= 3 && $0 !~ /^[[:space:]]*#/ {
    name = $1
    email = $2
    tenant = $3
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", email)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", tenant)
    gsub(/[\t\r\n]/, " ", name)
    gsub(/[\t\r\n]/, "", email)
    gsub(/[\t\r\n]/, "", tenant)
    searchable = tolower(name " " email)
    if (name != "" && email != "" && tenant != "" &&
        (query == "" || index(searchable, query) > 0)) {
      count++
      print count "\t" name " — " email "\t" name "\t" email "\t" tenant
    }
  }
' "$CSV_FILE" > "$CONTACTS_FILE"
/bin/chmod 600 "$CONTACTS_FILE"

MATCH_COUNT="$(awk 'END { print NR + 0 }' "$CONTACTS_FILE")"
if [[ "$MATCH_COUNT" -eq 0 ]]; then
  write_status "Fehler"
  echo "Keine passenden Teams-Kontakte gefunden." >&2
  exit 1
fi

if [[ "$MATCH_COUNT" -eq 1 ]]; then
  SELECTED_ID=1
else
  awk -F '\t' '{ print $1 "\t" $2 }' "$CONTACTS_FILE" > "$DISPLAY_FILE"
  /bin/chmod 600 "$DISPLAY_FILE"

  if [[ ! -x "$OSASCRIPT_CMD" ]]; then
    write_status "Fehler"
    echo "Die macOS-Auswahlanzeige ist nicht verfügbar." >&2
    exit 1
  fi

  # Pass only a private temporary filename to osascript. No contact or tenant
  # data is interpolated into executable AppleScript source or process args.
  SELECTED_ID="$("$OSASCRIPT_CMD" - "$DISPLAY_FILE" <<'APPLESCRIPT'
on run argv
  set sourceFile to POSIX file (item 1 of argv)
  set raw to read sourceFile as «class utf8»
  set rows to paragraphs of raw
  set displayRows to {}

  repeat with rowText in rows
    if (rowText as text) is not "" then
      set AppleScript's text item delimiters to tab
      set columns to text items of (rowText as text)
      set AppleScript's text item delimiters to ""
      if (count of columns) ≥ 2 then
        set end of displayRows to ((item 1 of columns) & ". " & (item 2 of columns))
      end if
    end if
  end repeat

  set picked to choose from list displayRows with title "Teams Video Call" with prompt "Pick a person to video call" without empty selection allowed
  if picked is false then return ""

  set pickedDisplay to item 1 of picked
  set AppleScript's text item delimiters to ". "
  set selectedId to first text item of pickedDisplay
  set AppleScript's text item delimiters to ""
  return selectedId
end run
APPLESCRIPT
  )"
fi

if [[ -z "$SELECTED_ID" ]]; then
  write_status "Abgebrochen"
  echo "Abgebrochen."
  exit 0
fi

SELECTED_ROW="$(awk -F '\t' -v selected="$SELECTED_ID" '$1 == selected { print; exit }' "$CONTACTS_FILE")"
if [[ -z "$SELECTED_ROW" ]]; then
  write_status "Fehler"
  echo "Ungültige Auswahl." >&2
  exit 1
fi

IFS=$'\t' read -r _ DISPLAY_NAME NAME EMAIL TENANT_ID <<< "$SELECTED_ROW"
if [[ -z "$NAME" || -z "$EMAIL" || -z "$TENANT_ID" ]]; then
  write_status "Fehler"
  echo "Ungültiger Kontakteintrag." >&2
  exit 1
fi

EMAIL_ENCODED="$(urlencode "$EMAIL")"
TENANT_ID_ENCODED="$(urlencode "$TENANT_ID")"
CALL_URL="msteams://teams.microsoft.com/l/call/0/0?users=${EMAIL_ENCODED}&withVideo=true&tenantId=${TENANT_ID_ENCODED}&source=raycast"

if [[ "${TEAMS_CALL_DRY_RUN:-0}" == "1" ]]; then
  echo "Teams-Videoanruf würde geöffnet."
else
  if [[ ! -x "$OPEN_CMD" ]]; then
    write_status "Fehler"
    echo "Das Werkzeug zum Öffnen des Teams-Links ist nicht verfügbar." >&2
    exit 1
  fi
  "$OPEN_CMD" "$CALL_URL"
  echo "Teams-Videoanruf wird geöffnet."
fi
write_status "Anruf gestartet"
