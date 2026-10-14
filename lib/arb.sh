# Local translations from the ARB files.

# read_local_translations ARB_DIR LOCALES OUT_FILE: writes locale -> key -> value.
# LOCALES is a comma separated filter; empty means every app_<locale>.arb.
read_local_translations() {
  local dir="$1" locales="$2" out="$3"
  [[ -d "$dir" ]] || die "$dir not found. Run from the Restock repo root or pass --project=<path>."

  local -a files
  shopt -s nullglob
  files=("$dir"/*.arb)
  shopt -u nullglob
  ((${#files[@]})) || die "No ARB files found in $dir."

  jq_file local_translations -n --arg locales "$locales" "${files[@]}" >"$out"
  [[ "$(jq 'length' "$out")" != 0 ]] || die "No ARB files in $dir for ${locales:-any locale}."
}
