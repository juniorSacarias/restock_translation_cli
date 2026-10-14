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
  trap 'rm -rf "$TMP"' EXIT
}

# jq_file PROGRAM [JQ ARGS...]: runs lib/jq/PROGRAM.jq.
jq_file() {
  local program="$1"
  shift
  jq -f "$LIB_DIR/jq/$program.jq" "$@"
}
