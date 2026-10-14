# Restock project location and .env files.
#
# Globals: ENVIRONMENTS (offered in the menu).

ENVIRONMENTS=(development staging production)

is_project() { [[ -d "$1/lib/l10n/arb" ]]; }

# expand_path PATH: ~ expanded, no trailing slash.
expand_path() {
  local path="${1/#\~/$HOME}"
  [[ "$path" == / ]] || path="${path%/}"
  printf '%s' "$path"
}

# Restock repo root when it is known without asking: $TRANSLATION_PROJECT, else
# the current directory when it is a Restock project. Empty otherwise.
default_project_dir() {
  if [[ -n "${TRANSLATION_PROJECT:-}" ]]; then
    expand_path "$TRANSLATION_PROJECT"
  elif is_project "$PWD"; then
    printf '%s' "$PWD"
  fi
}

# load_env_file FILE: sets API_URL and, unless already set, MODULE.
load_env_file() {
  [[ -f "$1" ]] || die "$1 not found. Run from the Restock repo root or pass --project=<path>."
  API_URL="$(file_value AHA_API_URL "$1")"
  API_URL="${API_URL%/}"
  MODULE="${MODULE:-$(file_value MODULE_NAME "$1")}"
  [[ -n "$API_URL" ]] || die "AHA_API_URL missing in $1"
  [[ -n "$MODULE" ]] || die "MODULE_NAME missing in $1 (or pass --module)"
}
