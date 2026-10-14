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
  local method="$1" path="$2" body="${3:-}" status
  RESPONSE="$TMP/response.json"
  local -a curl_args=(-sS -g -X "$method" -o "$RESPONSE" -w '%{http_code}' --max-time 60
    -H 'Content-Type: application/json' -H 'Accept: application/json')
  [[ -n "$TOKEN" ]] && curl_args+=(-H "authorization: $TOKEN")
  if [[ -n "$body" ]]; then
    status="$(curl "${curl_args[@]}" --data-binary @- "$API_URL$path" <<<"$body" 2>"$TMP/curl.err")" || true
  else
    status="$(curl "${curl_args[@]}" "$API_URL$path" 2>"$TMP/curl.err")" || true
  fi
  AHA_STATUS="$status"
  if [[ "$status" =~ ^2 ]]; then
    [[ -s "$RESPONSE" ]] || echo '{}' >"$RESPONSE"
    return 0
  fi
  if [[ "$status" == 000 || -z "$status" ]]; then
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
  aha POST /api/auth/email "$body" || request_failed
  TOKEN="$(jq -r '.token // empty' "$RESPONSE")"
  [[ -n "$TOKEN" ]] || die "Login did not return a token: $(jq -c '.message // .' "$RESPONSE")"
  SCHEMA_NAME="${SCHEMA_NAME:-$(jq -r '.application.SchemaName // empty' "$RESPONSE")}"
}

# aha_list ENTITY OUT_FILE [FIELD...]: `data` of GET /api/e/<entity> for $MODULE.
# filter/fields use brackets like Dio in the app (the API parses them with `qs`;
# a JSON-encoded filter would silently return nothing).
aha_list() {
  local entity="$1" out="$2" query field
  shift 2
  query="all=true&filter%5BModule%5D=$(uri "$MODULE")"
  for field in "$@"; do query+="&fields%5B%5D=$(uri "$field")"; done
  aha GET "/api/e/$entity?$query" || request_failed
  jq '.data // []' "$RESPONSE" >"$out"
}

# aha_create ENTITY JSON_BODY: POST /api/e/<entity>; the created record is in .content.
aha_create() { aha POST "/api/e/$1" "$2"; }

# aha_update ENTITY ID JSON_BODY: PUT /api/e/<entity>/<id> (partial update).
aha_update() { aha PUT "/api/e/$1/$2" "$3"; }

# aha_entity_fields ENTITY: field definitions keyed by slug on stdout, or null.
# Needs $SCHEMA_NAME (schemas live per application, not in the API code).
aha_entity_fields() {
  aha GET "/api/entities/$(uri "$1")?collection=$(uri "$SCHEMA_NAME")" || request_failed
  jq_file entity_fields "$RESPONSE"
}

# aha_resolve_key_entity: sets KEY_ENTITY to the entity referenced by
# _translations.Key, unless given with --key-entity or the schema is unknown.
aha_resolve_key_entity() {
  [[ -n "$KEY_ENTITY" || -z "$SCHEMA_NAME" ]] && return 0
  KEY_ENTITY="$(aha_entity_fields "$TRANSLATIONS_ENTITY" | jq -r '.Key.ref // empty')"
  [[ -n "$KEY_ENTITY" ]] || warn "Could not find the Key reference in the $TRANSLATIONS_ENTITY schema; pass --key-entity."
}
