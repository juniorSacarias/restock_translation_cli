# `translation diff|push`: compare local and Ahamatic translations, then
# optionally upload the missing ones.

cmd_sync() {
  parse_sync_args "$@"
  require_commands curl jq
  make_tmp

  load_env_file "$ENV_FILE"
  read_local_translations "$ARB_DIR" "$LOCALES" "$TMP/local.json"

  printf '%s%s  (env: %s, module: %s)\n' "$(bold 'Ahamatic  ')" "$API_URL" "$ENV_NAME" "$MODULE"
  printf '%s%s  (%s)\n\n' "$(bold 'Local     ')" "$ARB_DIR" \
    "$(jq -r '"\(keys | join(", ")), \([.[] | keys[]] | unique | length) keys"' "$TMP/local.json")"

  aha_authenticate
  fetch_remote
  compute_diff
  print_diff

  if [[ "$COMMAND" == push ]]; then
    run_push
  elif has_pending; then
    printf '\nRun with %s to upload them (add %s to only see the plan).\n' "$(bold push)" "$(bold --dry-run)"
  fi
}
