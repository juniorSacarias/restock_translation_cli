# Ahamatic API client (aha-api generic /api/e/<entity> routes).
#
# Globals: API_URL, MODULE (read); TOKEN, SCHEMA_NAME (set by aha_authenticate);
# RESPONSE (file with the last response body); AHA_STATUS, AHA_ERROR (last
# HTTP status and error message).

TRANSLATIONS_ENTITY='_translations'
LANGUAGES_ENTITY='AppLanguages'
TOKEN=''
AHA_STATUS=''
AHA_ERROR=''

# aha METHOD PATH [JSON_BODY]: response body in $RESPONSE. Returns 1 and sets
# $AHA_ERROR on a non-2xx status or a connection error.
aha() {
  local method="$1" path="$2" body="${3:-}" status curl_exit=0
  local timeout="${REQUEST_TIMEOUT:-60}"
  RESPONSE="$TMP/response.json"
  local -a curl_args=(-sS -g -X "$method" -o "$RESPONSE" -w '%{http_code}'
    --connect-timeout "$((timeout < 15 ? timeout : 15))" --max-time "$timeout"
    -H 'Content-Type: application/json' -H 'Accept: application/json')
  [[ -n "$TOKEN" ]] && curl_args+=(-H "authorization: $TOKEN")
  if [[ -n "$body" ]]; then
    status="$(curl "${curl_args[@]}" --data-binary @- "$API_URL$path" <<<"$body" 2>"$TMP/curl.err")" || curl_exit=$?
  else
    status="$(curl "${curl_args[@]}" "$API_URL$path" 2>"$TMP/curl.err")" || curl_exit=$?
  fi
  AHA_STATUS="$status"
  if [[ "$status" =~ ^2 ]]; then
    [[ -s "$RESPONSE" ]] || echo '{}' >"$RESPONSE"
    return 0
  fi
  if ((curl_exit == 28)); then
    AHA_ERROR="$method ${path%%\?*} timed out after ${timeout}s: Ahamatic did not answer. Try again, or give it more time with --timeout=<seconds>."
  elif [[ "$status" == 000 || -z "$status" ]]; then
    AHA_ERROR="$method ${path%%\?*} failed: $(tr -d '\n' <"$TMP/curl.err")"
  else
    AHA_ERROR="$method ${path%%\?*} → HTTP $status: $(head -c 300 "$RESPONSE" 2>/dev/null)"
  fi
  return 1
}

uri() { jq -rn --arg v "$1" '$v | @uri'; }

# Exits with the last request error; with $EXIT_AUTH when Ahamatic rejected
# the credentials or the token (HTTP 401).
request_failed() {
  if [[ "$AHA_STATUS" == 401 ]]; then
    red "✖ $AHA_ERROR" >&2
    echo >&2
    exit "$EXIT_AUTH"
  fi
  die "$AHA_ERROR"
}

# aha_authenticate: uses $AHA_TOKEN, or logs in with AHA_API_KEY/AHA_EMAIL/AHA_PASSWORD
# (the login also gives the application SchemaName). Asks for them when they
# are missing and this runs in a terminal.
aha_authenticate() {
  if [[ -n "${AHA_TOKEN:-}" ]]; then
    TOKEN="${AHA_TOKEN#Bearer }"
    return 0
  fi
  [[ -t 0 ]] && prompt_credentials
  has_credentials || die 'No Ahamatic credentials: run it in a terminal to be asked for them, or set AHA_TOKEN or AHA_API_KEY + AHA_EMAIL + AHA_PASSWORD.'

  local body
  body="$(jq -n --arg k "$AHA_API_KEY" --arg e "$AHA_EMAIL" --arg p "$AHA_PASSWORD" \
    '{apiKey: $k, emailAddress: $e, password: $p}')"
  # aha-api answers wrong credentials or API key with 412 (not 401).
  local ok=true
  spinner_start 'Logging in to Ahamatic…'
  aha POST /api/auth/email "$body" || ok=false
  spinner_stop
  if ! $ok; then
    [[ "$AHA_STATUS" =~ ^4 ]] && AHA_STATUS=401
    if [[ "$AHA_STATUS" == 000 && "$AHA_ERROR" == *'timed out'* ]]; then
      AHA_ERROR+=$'\n  Ahamatic answers wrong credentials at once, so they were probably accepted and the login got stuck on the Ahamatic side (it saves a refresh token after checking the password). Try again later, or report it if it keeps happening.'
    fi
    request_failed
  fi
  TOKEN="$(jq -r '.token // empty' "$RESPONSE")"
  if [[ -z "$TOKEN" ]] && jq -e '.recipient' "$RESPONSE" >/dev/null 2>&1; then
    die "This account needs 2FA by email ($(jq -r '.recipient' "$RESPONSE")); use the Ahamatic service account."
  fi
  [[ -n "$TOKEN" ]] || die "Login did not return a token: $(jq -c '.message // .' "$RESPONSE")"
  SCHEMA_NAME="${SCHEMA_NAME:-$(jq -r '.application.SchemaName // empty' "$RESPONSE")}"
  step_note 'Logged in to Ahamatic'

}

# aha_list ENTITY OUT_FILE [FIELD...]: every row of GET /api/e/<entity> for
# $MODULE, read $PAGE_SIZE rows at a time (`page`/`limit`; the response has
# totalPages and `end`), with a "page N/M" spinner.
# filter/fields use brackets like Dio in the app (the API parses them with `qs`;
# a JSON-encoded filter would silently return nothing).
aha_list() {
  local entity="$1" out="$2" query field page=1 pages='?' ok
  shift 2
  query="limit=${PAGE_SIZE:-100}&filter%5BModule%5D=$(uri "$MODULE")"
  for field in "$@"; do query+="&fields%5B%5D=$(uri "$field")"; done

  echo '[]' >"$out"
  while true; do
    ok=true
    spinner_start "Loading $entity… page $page/$pages"
    aha GET "/api/e/$entity?$query&page=$page" || ok=false
    spinner_stop
    $ok || request_failed

    jq -s '.[0] + (.[1].data // [])' "$out" "$RESPONSE" >"$TMP/page.json"
    mv "$TMP/page.json" "$out"
    pages="$(jq -r '.totalPages // 1 | if . < 1 then 1 else . end' "$RESPONSE")"
    if ((page >= pages)) || jq -e '.end == true or ((.data // []) | length) == 0' "$RESPONSE" >/dev/null; then
      break
    fi
    page=$((page + 1))
  done
  step_note "$entity: $(jq length "$out") rows ($page/$pages pages)"
}

# aha_create ENTITY JSON_BODY: POST /api/e/<entity>; the created record is in .content.
aha_create() { aha POST "/api/e/$1" "$2"; }

# aha_update ENTITY ID JSON_BODY: PUT /api/e/<entity>/<id> (partial update).
aha_update() { aha PUT "/api/e/$1/$2" "$3"; }

# aha_entity_fields ENTITY: field definitions keyed by slug on stdout, or null.
# Needs $SCHEMA_NAME (schemas live per application, not in the API code).
aha_entity_fields() {
  local ok=true
  spinner_start "Reading the $1 schema…"
  aha GET "/api/entities/$(uri "$1")?collection=$(uri "$SCHEMA_NAME")" || ok=false
  spinner_stop
  $ok || request_failed
  jq_file entity_fields "$RESPONSE"
}

# aha_resolve_key_entity: sets KEY_ENTITY to the entity referenced by
# _translations.Key, unless given with --key-entity or the schema is unknown.
aha_resolve_key_entity() {
  [[ -n "$KEY_ENTITY" || -z "$SCHEMA_NAME" ]] && return 0
  KEY_ENTITY="$(aha_entity_fields "$TRANSLATIONS_ENTITY" | jq -r '.Key.ref // empty')"
  [[ -n "$KEY_ENTITY" ]] || warn "Could not find the Key reference in the $TRANSLATIONS_ENTITY schema; pass --key-entity."
}
