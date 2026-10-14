# Upload the pending translations: keys first, then one _translations row per
# language, then fill empty values (and different ones with --update, or the
# ones chosen one by one with --review).
#
# Reads $TMP/diff.json (lib/diff.sh). Writes are sent one at a time; failures
# are collected and reported at the end (exit code 1).

FAILURES=()
REVIEWED_COUNT=0

# Plan files: to_create.ndjson (rows), keys_to_create.txt, to_update.ndjson,
# key_ids.json (name -> Id, grows while keys are created).
prepare_push_plan() {
  jq -c '.rows[] | select(.status | IN("missing", "missingKey"))' "$TMP/diff.json" >"$TMP/to_create.ndjson"
  jq -r '[.rows[] | select(.status == "missingKey") | .key] | unique[]' "$TMP/diff.json" >"$TMP/keys_to_create.txt"
  jq -c --argjson update "$UPDATE" '.rows[] | select(.status == "empty" or ($update and .status == "different"))' \
    "$TMP/diff.json" >"$TMP/to_update.ndjson"
  jq '.keyIds' "$TMP/diff.json" >"$TMP/key_ids.json"

  CREATE_COUNT="$(wc -l <"$TMP/to_create.ndjson")"
  KEYS_COUNT="$(wc -l <"$TMP/keys_to_create.txt")"
  UPDATE_COUNT="$(wc -l <"$TMP/to_update.ndjson")"
  DIFFERENT_COUNT="$(jq '[.rows[] | select(.status == "different")] | length' "$TMP/diff.json")"
  RENAME_COUNT="$(jq '.renames // [] | length' "$TMP/diff.json")"
  if $UPDATE; then SKIPPED_DIFFERENT=0; else SKIPPED_DIFFERENT=$DIFFERENT_COUNT; fi
}

# --review: asks for every DIFFERENT value whether to overwrite Ahamatic with
# the local value. The chosen rows are added to to_update.ndjson.
review_different() {
  ((DIFFERENT_COUNT > 0)) || return 0
  [[ -t 0 ]] || die '--review needs a terminal to ask for each value.'

  echo
  bold "Review $DIFFERENT_COUNT different values"
  echo " $(dim 'l: use local · k: keep Ahamatic · a: local for the rest · s: keep the rest')"

  local row index=0 choice rest=''
  : >"$TMP/reviewed.ndjson"
  while IFS= read -r row <&3; do
    index=$((index + 1))
    if [[ -n "$rest" ]]; then
      choice="$rest"
    else
      echo
      jq_file review_item -r --argjson index "$index" --argjson total "$DIFFERENT_COUNT" \
        --argjson color "$COLOR" <<<"$row"
      printf '  [l] local  [k] keep  [a] local for the rest  [s] keep the rest › '
      while true; do
        IFS= read -rsn1 choice </dev/tty || choice=s
        case "${choice,,}" in
          l | k) break ;;
          a) rest=l; break ;;
          s) rest=k; break ;;
        esac
      done
      choice="${rest:-${choice,,}}"
      case "$choice" in
        l) echo "$(color 32 'use local')${rest:+ (and the rest)}" ;;
        k) echo "$(dim 'keep Ahamatic')${rest:+ $(dim '(and the rest)')}" ;;
      esac
    fi
    if [[ "$choice" == l ]]; then
      echo "$row" >>"$TMP/reviewed.ndjson"
    fi
  done 3< <(jq -c '.rows[] | select(.status == "different")' "$TMP/diff.json")

  REVIEWED_COUNT="$(wc -l <"$TMP/reviewed.ndjson")"
  cat "$TMP/reviewed.ndjson" >>"$TMP/to_update.ndjson"
  UPDATE_COUNT="$(wc -l <"$TMP/to_update.ndjson")"
  SKIPPED_DIFFERENT=$((DIFFERENT_COUNT - REVIEWED_COUNT))
}

# Aborts before writing if the schemas require fields we do not send, or lack
# the ones we send.
check_schemas() {
  if [[ -z "$SCHEMA_NAME" ]]; then
    warn 'Schema name unknown: cannot check required fields before writing.'
    return 0
  fi
  local problems='' spec entity
  for spec in "$KEY_ENTITY:Name,Module" "$TRANSLATIONS_ENTITY:Module,Language,Key,Value"; do
    entity="${spec%%:*}"
    aha_entity_fields "$entity" >"$TMP/fields.json"
    if [[ "$(cat "$TMP/fields.json")" == null ]]; then
      warn "Schema of $entity not found: cannot check its required fields."
      continue
    fi
    problems+="$(jq_file schema_problems -r --arg entity "$entity" --arg sent "${spec#*:}" "$TMP/fields.json")"
  done
  [[ -z "$problems" ]] || die "Schema mismatch, nothing written:$problems"
}

print_push_plan() {
  local updated='empty'
  $UPDATE && updated+=' + different'
  $REVIEW && updated+=" + $REVIEWED_COUNT reviewed"
  echo
  bold "Plan for $API_URL (module $MODULE):"; echo
  echo "  • create $KEYS_COUNT keys in $KEY_ENTITY"
  ((RENAME_COUNT == 0)) || echo "    $(color 33 "⚠ $RENAME_COUNT of them look like renamed Ahamatic keys (see Possible renames)")"
  echo "  • create $CREATE_COUNT translations in $TRANSLATIONS_ENTITY"
  echo "  • update $UPDATE_COUNT translations ($updated)"
  if ((SKIPPED_DIFFERENT > 0)); then
    if $REVIEW; then
      echo "  • keep $SKIPPED_DIFFERENT different values as they are in Ahamatic (your review)"
    else
      echo "  • leave $SKIPPED_DIFFERENT different values untouched (use --review to choose, or --update to overwrite them)"
    fi
  fi
}

# Returns 1 unless the user types "yes" (or --yes was given).
confirm_push() {
  $YES && return 0
  [[ -t 0 ]] || die 'No terminal to confirm; pass --yes to push non-interactively.'
  local target="$ENV_NAME" answer
  [[ "$ENV_NAME" == production ]] && target="$(red PRODUCTION)"
  printf '\nType "yes" to write to %s: ' "$target"
  read -r answer
  [[ "${answer,,}" == yes ]]
}

progress() { [[ -t 1 ]] && printf '\r%s… %d/%d' "$1" "$2" "$3"; return 0; }

step_done() {
  local label="$1" total="$2" failed="$3"
  [[ -t 1 ]] && printf '\r'
  if ((failed == 0)); then
    printf '%s… %d/%d %s\n' "$label" "$total" "$total" "$(green ✔)"
  else
    printf '%s… %d/%d %s\n' "$label" "$total" "$total" "$(red "✖ $failed failed")"
  fi
}

# 1. Keys first: each translation references its key by Id.
create_keys() {
  ((KEYS_COUNT > 0)) || return 0
  local done_count=0 failed=0 key body id
  while IFS= read -r key; do
    body="$(jq -n --arg name "$key" --arg module "$MODULE" '{Name: $name, Module: $module}')"
    AHA_ERROR=''
    if aha_create "$KEY_ENTITY" "$body" && id="$(jq -e '.content.Id | numbers' "$RESPONSE")"; then
      jq --arg key "$key" --argjson id "$id" '.[$key] = $id' "$TMP/key_ids.json" >"$TMP/tmp.json"
      mv "$TMP/tmp.json" "$TMP/key_ids.json"
    else
      FAILURES+=("$key: ${AHA_ERROR:-no Id in response}")
      failed=$((failed + 1))
    fi
    done_count=$((done_count + 1))
    progress 'Creating keys' "$done_count" "$KEYS_COUNT"
  done <"$TMP/keys_to_create.txt"
  step_done 'Creating keys' "$KEYS_COUNT" "$failed"
}

# 2. One translation per key and language.
create_translations() {
  ((CREATE_COUNT > 0)) || return 0
  local done_count=0 failed=0 row body label
  while IFS= read -r row; do
    body="$(jq -nc --arg module "$MODULE" --slurpfile keyIds "$TMP/key_ids.json" --argjson row "$row" '
      $keyIds[0][$row.key] as $keyId
      | if $keyId == null then null
        else {Module: $module, Language: $row.languageId, Key: $keyId, Value: $row.local} end')"
    label="$(jq -r '"\(.key) [\(.locale)]"' <<<"$row")"
    if [[ "$body" == null ]]; then
      FAILURES+=("$label: skipped, key could not be created")
      failed=$((failed + 1))
    elif ! aha_create "$TRANSLATIONS_ENTITY" "$body"; then
      FAILURES+=("$label: $AHA_ERROR")
      failed=$((failed + 1))
    fi
    done_count=$((done_count + 1))
    progress 'Creating translations' "$done_count" "$CREATE_COUNT"
  done <"$TMP/to_create.ndjson"
  step_done 'Creating translations' "$CREATE_COUNT" "$failed"
}

# 3. Fill empty values (and different ones with --update).
update_translations() {
  ((UPDATE_COUNT > 0)) || return 0
  local done_count=0 failed=0 row
  while IFS= read -r row; do
    if ! aha_update "$TRANSLATIONS_ENTITY" "$(jq -r '.translationId' <<<"$row")" "$(jq -c '{Value: .local}' <<<"$row")"; then
      FAILURES+=("$(jq -r '"\(.key) [\(.locale)]"' <<<"$row"): $AHA_ERROR")
      failed=$((failed + 1))
    fi
    done_count=$((done_count + 1))
    progress 'Updating translations' "$done_count" "$UPDATE_COUNT"
  done <"$TMP/to_update.ndjson"
  step_done 'Updating translations' "$UPDATE_COUNT" "$failed"
}

run_push() {
  prepare_push_plan
  $REVIEW && review_different

  if ((CREATE_COUNT == 0 && UPDATE_COUNT == 0)); then
    echo
    green '✔ Nothing to push.'; echo
    if ((SKIPPED_DIFFERENT > 0)) && ! $REVIEW; then
      echo "  $SKIPPED_DIFFERENT different values were left untouched (use --review to choose, or --update to overwrite them)."
    fi
    return 0
  fi

  [[ -n "$KEY_ENTITY" ]] || die "Unknown translation key entity. Log in with AHA_EMAIL/AHA_PASSWORD/AHA_API_KEY, or pass --schema=<SchemaName> or --key-entity=<entity>."
  check_schemas
  print_push_plan

  if $DRY_RUN; then
    printf '\nDry run: nothing was written.\n'
    return 0
  fi
  if ! confirm_push; then
    echo 'Aborted.'
    return 0
  fi
  echo

  create_keys
  create_translations
  update_translations

  echo
  if ((${#FAILURES[@]} == 0)); then
    green '✔ Done. Run the diff again to verify.'; echo
  else
    red "✖ ${#FAILURES[@]} operations failed:"; echo
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
  fi
}
