# Output, file and temp-dir helpers shared by every module.
#
# Globals: COLOR (true when stdout is a terminal and NO_COLOR is unset), TMP,
# EXIT_AUTH (exit code when Ahamatic rejects the credentials or token).

EXIT_AUTH=3

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then COLOR=true; else COLOR=false; fi

color() { if $COLOR; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi; }
bold() { color 1 "$1"; }
dim() { color 2 "$1"; }
red() { color 31 "$1"; }
green() { color 32 "$1"; }
warn() { color 33 "⚠ $1" >&2; echo >&2; }
die() { red "✖ $1" >&2; echo >&2; exit 1; }

# trim TEXT: TEXT without leading/trailing whitespace.
trim() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  printf '%s' "${text%"${text##*[![:space:]]}"}"
}

# require_commands NAME...: exits when one of them is not installed.
require_commands() {
  local name
  for name in "$@"; do
    command -v "$name" >/dev/null || die "$name is required (see README: Getting started)."
  done
}

# file_value KEY FILE: value of KEY in a KEY=VALUE file, without sourcing it
# (Restock .env files have spaces around `=`). Quotes are removed.
file_value() {
  [[ -f "$2" ]] || return 0
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$2" | tail -n 1 |
    sed -E "s/[[:space:]]+$//; s/^[\"'](.*)[\"']$/\1/"
}

# make_tmp: creates $TMP, removed when the process exits.
make_tmp() {
  TMP="$(mktemp -d)"
  trap 'spinner_stop; rm -rf "$TMP"' EXIT
}

# spinner_start LABEL: animated "⠹ LABEL" line on stderr while something runs
# (only when stderr is a terminal). spinner_stop clears it.
SPINNER_PID=''
spinner_start() {
  [[ -t 2 ]] || return 0
  spinner_stop
  local label="$1"
  (
    frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    i=0
    while true; do
      printf '\r\033[2K%s %s' "$(color 36 "${frames[i % 10]}")" "$label" >&2
      i=$((i + 1))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
}

spinner_stop() {
  [[ -n "$SPINNER_PID" ]] || return 0
  kill "$SPINNER_PID" 2>/dev/null || true
  wait "$SPINNER_PID" 2>/dev/null || true
  SPINNER_PID=''
  printf '\r\033[2K' >&2
}

# step_note MESSAGE: "✔ MESSAGE" on stderr for a finished step (terminal only).
step_note() {
  [[ -t 2 ]] && printf '%s %s\n' "$(green ✔)" "$1" >&2
  return 0
}

# jq_file PROGRAM [JQ ARGS...]: runs lib/jq/PROGRAM.jq (lib/jq is the module
# path, so programs can `include "text";`).
jq_file() {
  local program="$1"
  shift
  jq -L "$LIB_DIR/jq" -f "$LIB_DIR/jq/$program.jq" "$@"
}
