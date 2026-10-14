# Compare local and Ahamatic translations and print the table.
#
# Files in $TMP: local.json, language_ids.json, translations.json, keys.json,
# diff.json ({duplicates, keyIds, rows: [{key, locale, languageId, status,
# local, remote, translationId}]}).
# Statuses: missingKey, missing, empty, different (pending), ok, extra.

PENDING_STATUSES='["missingKey", "missing", "empty", "different"]'

# fetch_remote: AppLanguages, _translations and translation keys of $MODULE.
fetch_remote() {
  aha_list "$LANGUAGES_ENTITY" "$TMP/languages.json"
  jq_file language_ids -n --slurpfile local "$TMP/local.json" \
    --slurpfile languages "$TMP/languages.json" >"$TMP/language_ids.json"

  local locale
  while IFS= read -r locale; do
    warn "No $LANGUAGES_ENTITY row for \"$locale\" in module $MODULE; locale skipped."
  done < <(jq -r 'to_entries[] | select(.value == null) | .key' "$TMP/language_ids.json")
  jq 'with_entries(select(.value != null))' "$TMP/language_ids.json" >"$TMP/tmp.json"
  mv "$TMP/tmp.json" "$TMP/language_ids.json"
  [[ "$(jq length "$TMP/language_ids.json")" != 0 ]] || die "None of the local locales exist in Ahamatic $LANGUAGES_ENTITY."

  aha_resolve_key_entity
  aha_list "$TRANSLATIONS_ENTITY" "$TMP/translations.json" Id Module Language Key Value

  # Keys can exist without any translation, so list them too when the entity is known.
  if [[ -n "$KEY_ENTITY" ]]; then
    aha_list "$KEY_ENTITY" "$TMP/keys.json"
  else
    echo '[]' >"$TMP/keys.json"
  fi
}

compute_diff() {
  jq_file diff -n \
    --slurpfile local "$TMP/local.json" \
    --slurpfile languageIds "$TMP/language_ids.json" \
    --slurpfile translations "$TMP/translations.json" \
    --slurpfile keys "$TMP/keys.json" >"$TMP/diff.json"

  local duplicates
  duplicates="$(jq '.duplicates' "$TMP/diff.json")"
  ((duplicates == 0)) || warn "$duplicates duplicated translations in Ahamatic (same key + language); the newest one is used, like the app does."
}

# Width of the controlling terminal, 0 when unknown. Call it only when stdout
# is a terminal (inside $(...) stdout is a pipe, so it cannot check itself).
terminal_columns() {
  local columns
  columns="$( (stty size </dev/tty | cut -d' ' -f2) 2>/dev/null || tput cols 2>/dev/null || echo "${COLUMNS:-0}")"
  [[ "$columns" =~ ^[0-9]+$ ]] || columns=0
  printf '%s' "$columns"
}

print_diff() {
  local columns=0
  [[ -t 1 ]] && columns="$(terminal_columns)"
  jq_file table -r --argjson all "$SHOW_ALL" --argjson wide "$WIDE" \
    --argjson cols "$columns" --argjson color "$COLOR" "$TMP/diff.json"
}

has_pending() {
  jq -e --argjson pending "$PENDING_STATUSES" '.rows | any(.status | IN($pending[]))' "$TMP/diff.json" >/dev/null
}
