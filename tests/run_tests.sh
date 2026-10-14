#!/usr/bin/env bash
#
# Tests for the `translation` tool against a local mock of the Ahamatic API
# (tests/mock_ahamatic.py). Nothing reaches a real Ahamatic server.
#
# Requires: bash, curl, jq, python3. `script` (util-linux) for the TTY tests.
# Usage:    tests/run_tests.sh [name-filter]

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../translation"   # diff/push tests call it with --env=test first
TRANSLATION="$HERE/../translation"
FILTER="${1:-}"

WORK="$(mktemp -d)"
MOCK_PID=''
cleanup() {
  [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

# Never use real credentials from the caller's environment.
unset AHA_TOKEN AHA_API_KEY AHA_EMAIL AHA_PASSWORD NO_COLOR TRANSLATION_PROJECT

# ---------------------------------------------------------------------------
# Mock server and project
# ---------------------------------------------------------------------------

python3 -I "$HERE/mock_ahamatic.py" "$HERE/fixtures/state.json" >"$WORK/mock.port" 2>"$WORK/mock.err" &
MOCK_PID=$!
for _ in $(seq 50); do
  [[ -s "$WORK/mock.port" ]] && break
  sleep 0.1
done
[[ -s "$WORK/mock.port" ]] || { echo "Mock server did not start:" >&2; cat "$WORK/mock.err" >&2; exit 1; }
MOCK_URL="http://127.0.0.1:$(head -n 1 "$WORK/mock.port")"

PROJECT="$WORK/project"
cp -r "$HERE/fixtures/project" "$PROJECT"
sed -i "s|__MOCK_URL__|$MOCK_URL|" "$PROJECT/.env.test"
for environment in development staging production; do
  cp "$PROJECT/.env.test" "$PROJECT/.env.$environment"
done

# reset_mock [STATE_JSON]: restore the fixture state (or the given one) and clear the log.
reset_mock() {
  curl -sS -o /dev/null -X POST --data-binary "${1:-}" "$MOCK_URL/__reset"
}

# State fixture transformed with a jq filter, for reset_mock.
state_with() {
  jq -c "$1" "$HERE/fixtures/state.json"
}

mock_log() {
  curl -sS "$MOCK_URL/__log"
}

# Writes received by the mock (everything but GETs and the login), one per line.
writes() {
  mock_log | jq -r '.[] | select(.method != "GET" and .path != "/api/auth/email")
    | "\(.method) \(.path) \(.body | tojson)"'
}

with_credentials() {
  export AHA_API_KEY=test-api-key AHA_EMAIL=svc@test.local AHA_PASSWORD=test-password
}

# run [ARGS...]: runs the script from the project dir; sets $OUT (stdout+stderr) and $STATUS.
run() {
  OUT="$(cd "$PROJECT" && "$SCRIPT" --env=test "$@" 2>&1 </dev/null)"
  STATUS=$?
}

# run_tty INPUT COLUMNS [ARGS...]: like run, inside a pseudo terminal.
run_tty() {
  local input="$1" columns="$2" command
  shift 2
  command="stty cols $columns; cd $(printf '%q' "$PROJECT") && $(printf '%q ' "$SCRIPT" --env=test "$@")"
  OUT="$(printf '%s\n' "$input" | script -qec "$command" /dev/null 2>&1 | tr -d '\r' | strip_ansi)"
  STATUS=$?
}

strip_ansi() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

# tty_session COMMAND KEYS...: runs the shell COMMAND in a pseudo terminal and
# types each KEYS chunk (printf %b escapes) after a pause, like a user would
# (input sent before a prompt would be echoed by the terminal). Sets $OUT
# (without ANSI sequences) and $STATUS.
tty_session() {
  command -v script >/dev/null || return 1
  local command="$1" chunk
  shift
  OUT="$(
    {
      sleep 0.6
      for chunk in "$@"; do
        printf '%b' "$chunk"
        sleep 0.6
      done
      sleep 0.5
    } | script -qec "$command" /dev/null 2>&1 | tr -d '\r' | strip_ansi
  )"
  STATUS=$?
}

# run_typed KEYS...: `translation --env=test` from the project in a pseudo terminal, typing KEYS.
run_typed() {
  tty_session "stty cols 120; cd $(printf '%q' "$PROJECT") && $(printf '%q' "$SCRIPT") --env=test" "$@"
}

# ---------------------------------------------------------------------------
# Assertions (each test runs in a subshell; a failed assertion exits it)
# ---------------------------------------------------------------------------

fail() {
  printf '    %s\n' "$@" >&2
  printf '    --- output ---\n%s\n    --------------\n' "$OUT" | sed 's/^/    /' >&2
  exit 1
}

assert_status() {
  [[ "$STATUS" == "$1" ]] || fail "expected exit status $1, got $STATUS"
}

assert_contains() {
  [[ "$OUT" == *"$1"* ]] || fail "expected output to contain: $1"
}

assert_not_contains() {
  [[ "$OUT" != *"$1"* ]] || fail "expected output not to contain: $1"
}

# assert_row KEY LOCALE STATUS: the table has that row.
assert_row() {
  grep -qE "│ $1 +│ $2 +│ $3 +│" <<<"$OUT" || fail "expected table row: $1 | $2 | $3"
}

assert_no_row() {
  ! grep -qE "│ $1 +│ $2 +│" <<<"$OUT" || fail "expected no table row for: $1 | $2"
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected: $2" "actual:   $1"
}

assert_no_writes() {
  local w
  w="$(writes)"
  [[ -z "$w" ]] || fail "expected no writes, got:" "$w"
}

# ---------------------------------------------------------------------------
# Arguments and configuration
# ---------------------------------------------------------------------------

test_help_prints_usage() {
  run --help
  assert_status 0
  assert_contains 'Usage:'
  assert_contains '--project=<path>'
}

test_unknown_argument_exits_64() {
  run --nope
  assert_status 64
  assert_contains 'Unknown argument --nope'
}

test_option_without_value_exits_64() {
  run --module
  assert_status 64
  assert_contains 'Missing value for --module'
}

test_missing_env_file_suggests_project() {
  with_credentials
  run --env=nope
  assert_status 1
  assert_contains '.env.nope not found'
  assert_contains '--project=<path>'
}

test_project_option_works_from_another_directory() {
  with_credentials
  OUT="$(cd / && "$SCRIPT" --env=test --project="$PROJECT" 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_row orphan en MISSING
}

test_reads_env_file_with_spaces_quotes_and_trailing_slash() {
  with_credentials
  run
  assert_status 0
  assert_contains "Ahamatic  $MOCK_URL  (env: test, module: falckWebApp)"
}

test_module_option_overrides_env_file() {
  with_credentials
  run --module=otherModule --locales=sv
  assert_status 0
  assert_contains 'module: otherModule'
  assert_row hello sv 'NO KEY'
}

test_without_terminal_requires_credentials_in_environment() {
  run
  assert_status 1
  assert_contains 'No Ahamatic credentials: run it in a terminal to be asked for them'
}

test_wrong_credentials_exit_with_auth_code() {
  export AHA_API_KEY=test-api-key AHA_EMAIL=svc@test.local AHA_PASSWORD=wrong
  run
  assert_status 3
  assert_contains 'POST /api/auth/email → HTTP 401'
}

test_expired_token_exits_with_auth_code() {
  export AHA_TOKEN=expired-token
  run
  assert_status 3
  assert_contains 'HTTP 401'
}

test_terminal_asks_for_missing_credentials_without_echoing_secrets() {
  run_typed 'svc@test.local\r' 'test-password\r' 'test-api-key\r' || return 0
  assert_contains 'Ahamatic credentials'
  assert_contains 'only kept in memory'
  assert_row orphan en MISSING
  assert_not_contains 'test-password'
  assert_not_contains 'test-api-key'
}

test_terminal_does_not_ask_when_environment_has_credentials() {
  with_credentials
  run_typed || return 0
  assert_not_contains 'Ahamatic credentials'
  assert_row orphan en MISSING
}

test_unreachable_api_reports_error() {
  with_credentials
  sed "s|$MOCK_URL|http://127.0.0.1:9|" "$PROJECT/.env.test" >"$PROJECT/.env.down"
  run --env=down
  assert_status 1
  assert_contains 'POST /api/auth/email failed'
}

# ---------------------------------------------------------------------------
# Diff
# ---------------------------------------------------------------------------

test_diff_classifies_every_case() {
  with_credentials
  run
  assert_status 0
  assert_row bye da EMPTY
  assert_row bye en DIFFERENT
  assert_row orphan da MISSING
  assert_row orphan en MISSING
  assert_row new_key en 'NO KEY'
  assert_row only_en en 'NO KEY'
  # A key with the same name in another module does not count.
  assert_row special da 'NO KEY'
  assert_no_row only_en da
  assert_contains 'Run with push to upload them'
}

test_diff_hides_ok_and_extra_rows_by_default() {
  with_credentials
  run
  assert_no_row hello en
  assert_no_row remote_only en
}

test_diff_all_shows_ok_and_ahamatic_only_rows() {
  with_credentials
  run --all
  assert_status 0
  assert_row hello en OK
  assert_row hello da OK
  assert_row remote_only en 'ONLY AHAMATIC'
}

test_diff_summary_counts_per_locale() {
  with_credentials
  run
  assert_contains 'da   NO KEY: 3   MISSING: 1   EMPTY: 1   OK: 1'
  assert_contains 'en   NO KEY: 4   MISSING: 1   DIFFERENT: 1   OK: 1   ONLY AHAMATIC: 1'
}

test_diff_shows_newlines_escaped_in_one_line() {
  with_credentials
  run
  assert_contains 'Line 1\nLine "2" æøå'
}

test_diff_does_not_write() {
  with_credentials
  run
  assert_no_writes
}

test_diff_queries_like_the_app() {
  with_credentials
  run
  local request
  request="$(mock_log | jq -c '[.[] | select(.method == "GET" and .path == "/api/e/_translations")][0]')"
  assert_eq "$(jq -c '[.query[] | select(.[0] == "filter[Module]")]' <<<"$request")" '[["filter[Module]","falckWebApp"]]'
  assert_eq "$(jq -c '[.query[] | select(.[0] == "fields[]") | .[1]]' <<<"$request")" '["Id","Module","Language","Key","Value"]'
  assert_eq "$(jq -r '.authorization' <<<"$request")" 'test-token'
}

test_locale_without_app_language_is_skipped_with_warning() {
  with_credentials
  run
  assert_contains 'No AppLanguages row for "sv" in module falckWebApp; locale skipped.'
  assert_no_row hello sv
}

test_locales_option_limits_the_comparison() {
  with_credentials
  run --locales=en
  assert_row orphan en MISSING
  assert_no_row orphan da
  assert_not_contains 'locale skipped'
}

test_fails_when_no_local_locale_exists_in_ahamatic() {
  with_credentials
  run --locales=sv
  assert_status 1
  assert_contains 'None of the local locales exist in Ahamatic AppLanguages.'
}

test_token_auth_skips_login_and_strips_bearer() {
  export AHA_TOKEN='Bearer test-token'
  run --key-entity=_translationKeys
  assert_status 0
  assert_row orphan en MISSING
  assert_eq "$(mock_log | jq '[.[] | select(.path == "/api/auth/email")] | length')" 0
  assert_eq "$(mock_log | jq -r '[.[].authorization] | unique | join(",")')" 'test-token'
}

test_token_without_key_entity_cannot_tell_missing_from_no_key() {
  export AHA_TOKEN=test-token
  run
  assert_status 0
  # orphan has a key but no translations; without the key entity it looks like a new key.
  assert_row orphan en 'NO KEY'
}

test_duplicated_remote_translations_warn_and_use_first() {
  with_credentials
  reset_mock "$(state_with '.translations += [{Id: 7, Module: "falckWebApp", Language: 11, Key: 100, Value: "Hello duplicate"}]')"
  run --all
  assert_contains '1 duplicated translations in Ahamatic'
  assert_row hello en OK
}

test_everything_in_sync() {
  with_credentials
  reset_mock "$(state_with '.keys = [] | .translations = [] | .failKeyNames = []')"
  run push --yes
  assert_status 0
  run
  assert_status 0
  assert_contains '✔ Ahamatic has every local translation.'
  assert_not_contains 'Run with push'
}

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------

test_push_dry_run_shows_plan_without_writing() {
  with_credentials
  run push --dry-run
  assert_status 0
  assert_contains 'create 4 keys in _translationKeys'
  assert_contains 'create 9 translations in _translations'
  assert_contains 'update 1 translations (empty)'
  assert_contains 'leave 1 different values untouched'
  assert_contains 'Dry run: nothing was written.'
  assert_no_writes
}

test_push_without_terminal_requires_yes() {
  with_credentials
  run push
  assert_status 1
  assert_contains 'No terminal to confirm; pass --yes'
  assert_no_writes
}

test_push_creates_keys_then_translations_with_their_ids() {
  with_credentials
  run push --yes
  local w
  w="$(writes)"
  # Keys are created before any translation.
  assert_eq "$(head -n 4 <<<"$w" | cut -d' ' -f1-2 | sort -u)" 'POST /api/e/_translationKeys'
  assert_contains 'Creating keys… 4/4'
  # Translations reference the Id the API gave the new key; en = AppLanguages 11, da = 12.
  local key_id
  key_id="$(curl -sS -g -H 'authorization: test-token' \
    "$MOCK_URL/api/e/_translationKeys?filter[Name]=new_key&filter[Module]=falckWebApp" | jq '.data[0].Id')"
  [[ "$key_id" =~ ^[0-9]+$ ]] || fail "new_key was not created (Id: $key_id)"
  grep -qF "POST /api/e/_translations {\"Module\":\"falckWebApp\",\"Language\":11,\"Key\":$key_id,\"Value\":\"Found {count} items\"}" <<<"$w" ||
    fail 'missing translation for new_key [en]' "$w"
  grep -qF "POST /api/e/_translations {\"Module\":\"falckWebApp\",\"Language\":12,\"Key\":$key_id,\"Value\":\"Fandt {count} varer\"}" <<<"$w" ||
    fail 'missing translation for new_key [da]' "$w"
  # Existing key without translations reuses its Id.
  grep -qF 'POST /api/e/_translations {"Module":"falckWebApp","Language":12,"Key":102,"Value":"Forældreløs"}' <<<"$w" ||
    fail 'missing translation for orphan [da]' "$w"
}

test_push_sends_special_characters_unchanged() {
  with_credentials
  run push --yes
  local value
  value="$(mock_log | jq -r '[.[] | select(.path == "/api/e/_translations" and .body.Language == 11
    and .body.Value != null and (.body.Value | startswith("Line 1")))][0].body.Value')"
  assert_eq "$value" $'Line 1\nLine "2" æøå'
}

test_push_fills_empty_but_keeps_different_values() {
  with_credentials
  run push --yes
  local w
  w="$(writes)"
  grep -qF 'PUT /api/e/_translations/4 {"Value":"Farvel"}' <<<"$w" || fail 'empty value not filled' "$w"
  ! grep -qF 'PUT /api/e/_translations/3' <<<"$w" || fail 'different value was overwritten without --update' "$w"
}

test_push_update_overwrites_different_values() {
  with_credentials
  run push --yes --update
  assert_contains 'update 2 translations (empty + different)'
  grep -qF 'PUT /api/e/_translations/3 {"Value":"Bye"}' <<<"$(writes)" || fail 'different value not overwritten'
}

test_push_reports_failed_key_and_skips_its_translations() {
  with_credentials
  run push --yes
  assert_status 1
  assert_contains 'fail_key: POST /api/e/_translationKeys → HTTP 412'
  assert_contains 'fail_key [da]: skipped, key could not be created'
  assert_contains 'fail_key [en]: skipped, key could not be created'
  assert_contains '✖ 3 operations failed:'
  [[ "$(writes)" != *'"Value":"Fejl"'* ]] || fail 'translation of a failed key was sent'
}

test_push_then_diff_is_in_sync_except_failures_and_different() {
  with_credentials
  run push --yes
  run
  assert_row fail_key en 'NO KEY'
  assert_row bye en DIFFERENT
  assert_no_row orphan en
  assert_no_row new_key da
  assert_no_row bye da
  assert_contains 'da   NO KEY: 1   OK: 5'
}

test_push_is_idempotent() {
  with_credentials
  reset_mock "$(state_with '.failKeyNames = []')"
  run push --yes --update
  assert_status 0
  assert_contains '✔ Done.'
  local first
  first="$(writes | wc -l)"
  run push --yes --update
  assert_status 0
  assert_contains '✔ Nothing to push.'
  assert_eq "$(writes | wc -l)" "$first"
}

test_push_with_token_needs_key_entity() {
  export AHA_TOKEN=test-token
  run push --yes
  assert_status 1
  assert_contains 'Unknown translation key entity'
  assert_no_writes
}

test_push_with_token_and_schema_discovers_key_entity() {
  export AHA_TOKEN=test-token
  run push --dry-run --schema=restock_schema
  assert_status 0
  assert_contains 'create 4 keys in _translationKeys'
}

test_push_discovers_key_entity_from_schema() {
  with_credentials
  reset_mock "$(state_with '.keyEntity = "TranslationKeys" | .schemas.TranslationKeys = .schemas._translationKeys
    | del(.schemas._translationKeys) | .schemas._translations.Key.ref = "TranslationKeys"')"
  run push --dry-run
  assert_status 0
  assert_contains 'create 4 keys in TranslationKeys'
}

test_push_aborts_when_schema_requires_unsent_fields() {
  with_credentials
  reset_mock "$(state_with '.schemas._translations.Description.required = true')"
  run push --yes
  assert_status 1
  assert_contains 'Schema mismatch, nothing written'
  assert_contains '_translations requires field(s) Description that this script does not send'
  assert_no_writes
}

test_push_aborts_when_schema_lacks_sent_fields() {
  with_credentials
  reset_mock "$(state_with 'del(.schemas._translationKeys.Module)')"
  run push --yes
  assert_status 1
  assert_contains '_translationKeys has no field(s) Module'
  assert_no_writes
}

test_push_nothing_to_do_mentions_different_values() {
  with_credentials
  reset_mock "$(state_with '.failKeyNames = []')"
  run push --yes
  run push --yes
  assert_status 0
  assert_contains '✔ Nothing to push.'
  assert_contains '1 different values were left untouched'
}

# ---------------------------------------------------------------------------
# Terminal
# ---------------------------------------------------------------------------

test_tty_table_fits_terminal_width() {
  command -v script >/dev/null || return 0
  with_credentials
  run_tty '' 70
  local widest
  widest="$(grep '│' <<<"$OUT" | sed 's/\x1b\[[0-9;]*m//g' | while IFS= read -r l; do echo "${#l}"; done | sort -n | tail -n 1)"
  ((widest <= 70)) || fail "table is $widest columns wide, terminal has 70"
  assert_contains '…'
}

test_tty_wide_does_not_truncate() {
  command -v script >/dev/null || return 0
  with_credentials
  run_tty '' 70 --wide
  assert_not_contains '…'
}

test_tty_confirmation_other_than_yes_aborts() {
  command -v script >/dev/null || return 0
  with_credentials
  run_tty 'no' 120 push
  assert_contains 'Type "yes" to write to test'
  assert_contains 'Aborted.'
  assert_no_writes
}

test_tty_confirmation_yes_writes() {
  command -v script >/dev/null || return 0
  with_credentials
  reset_mock "$(state_with '.failKeyNames = []')"
  run_tty 'yes' 120 push
  assert_contains '✔ Done.'
  [[ -n "$(writes)" ]] || fail 'expected writes after confirming'
}

test_tty_production_target_is_highlighted() {
  command -v script >/dev/null || return 0
  with_credentials
  run_tty 'no' 120 push --env=production
  assert_contains 'PRODUCTION'
  assert_no_writes
}

# ---------------------------------------------------------------------------
# translation command
# ---------------------------------------------------------------------------

# run_exec KEYS...: `translation exec` in a pseudo terminal with the project
# folder prompt prefilled (TRANSLATION_PROJECT) and accepted with Enter, then
# types each argument (printf %b escapes) after a pause.
run_exec() {
  run_exec_raw "TRANSLATION_PROJECT=$(printf '%q' "$PROJECT")" '' "$ENTER" "$@"
}

# run_exec_raw ENV_ASSIGNMENTS EXEC_ARGS KEYS...: `ENV_ASSIGNMENTS translation
# exec EXEC_ARGS` from / in a pseudo terminal, typing KEYS. Output without ANSI
# sequences in $OUT.
run_exec_raw() {
  local environment="$1" exec_args="$2"
  shift 2
  tty_session "stty cols 120; cd /; $environment $(printf '%q' "$TRANSLATION") exec $exec_args" "$@"
}

# Lines of the collapsed choice, e.g. "What do you want to do? Preview the upload".
assert_choice() {
  grep -qE "^$1 $2 *$" <<<"$OUT" || fail "expected choice: $1 $2"
}

ARROW_UP='\033[A'
ARROW_DOWN='\033[B'
ENTER='\r'
ESCAPE='\033'
CLEAR_LINE='\025' # Ctrl+U in the readline prompt

test_translation_help() {
  OUT="$("$TRANSLATION" help 2>&1)"
  STATUS=$?
  assert_status 0
  assert_contains 'translation exec'
}

test_translation_unknown_command_exits_64() {
  OUT="$("$TRANSLATION" nope 2>&1)"
  STATUS=$?
  assert_status 64
}

test_translation_diff_passes_options_through() {
  with_credentials
  OUT="$(cd / && TRANSLATION_PROJECT="$PROJECT" "$TRANSLATION" diff --env=test --locales=en 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_row orphan en MISSING
  assert_no_row orphan da
}

test_translation_uses_current_directory_as_project() {
  with_credentials
  OUT="$(cd "$PROJECT" && "$TRANSLATION" diff --env=test 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_contains "Local     $PROJECT/lib/l10n/arb"
}

test_translation_outside_a_project_asks_for_project_option() {
  with_credentials
  OUT="$(cd / && "$TRANSLATION" diff --env=test 2>&1 </dev/null)"
  STATUS=$?
  assert_status 1
  assert_contains 'Restock project not found'
  assert_contains '--project=<path>'
}

test_translation_project_option_expands_tilde() {
  with_credentials
  OUT="$(cd / && HOME="$WORK" "$TRANSLATION" diff --env=test --project='~/project/' 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_contains "Local     $PROJECT/lib/l10n/arb"
}

test_translation_leaves_no_files_behind() {
  with_credentials
  local before after
  before="$(find "$HERE/.." "$PROJECT" -newer "$WORK/mock.port" -type f 2>/dev/null | sort)"
  run push --yes
  after="$(find "$HERE/.." "$PROJECT" -newer "$WORK/mock.port" -type f 2>/dev/null | sort)"
  assert_eq "$after" "$before"
}

# A fresh HOME for the install tests, so the real ~/.bashrc is never touched.
fresh_home() {
  local home="$WORK/home-$RANDOM"
  mkdir -p "$home"
  printf '%s' "$home"
}

# run_install_typed HOME PATH KEYS...: `translation install` in a pseudo terminal.
run_install_typed() {
  local home="$1" path="$2"
  shift 2
  tty_session "HOME=$(printf '%q' "$home") PATH=$(printf '%q' "$path") SHELL=/bin/bash $(printf '%q' "$TRANSLATION") install" "$@"
}

test_translation_install_links_into_local_bin() {
  local home
  home="$(fresh_home)"
  OUT="$(HOME="$home" "$TRANSLATION" install 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_eq "$(readlink -f "$home/.local/bin/translation")" "$(readlink -f "$TRANSLATION")"
  # Works through the symlink (finds its files next to the real script).
  OUT="$("$home/.local/bin/translation" test no_test_has_this_name 2>&1)"
  assert_contains '0 passed'
}

test_translation_install_with_bin_on_path_is_ready() {
  local home
  home="$(fresh_home)"
  OUT="$(HOME="$home" PATH="$home/.local/bin:$PATH" "$TRANSLATION" install 2>&1 </dev/null)"
  assert_contains 'Ready: run translation exec.'
  [[ ! -e "$home/.bashrc" ]] || fail 'touched ~/.bashrc although the PATH was fine'
}

test_translation_install_without_terminal_only_prints_the_line() {
  local home
  home="$(fresh_home)"
  touch "$home/.bash_profile"
  OUT="$(HOME="$home" SHELL=/bin/bash "$TRANSLATION" install 2>&1 </dev/null)"
  STATUS=$?
  assert_status 0
  assert_contains 'is not in your PATH'
  assert_contains 'You have ~/.bash_profile, so bash does not read ~/.profile'
  assert_contains 'export PATH="$HOME/.local/bin:$PATH"'
  [[ ! -e "$home/.bashrc" ]] || fail 'wrote ~/.bashrc without asking'
}

test_translation_install_adds_path_to_bashrc_when_accepted() {
  local home
  home="$(fresh_home)"
  printf '# existing\n' >"$home/.bashrc"
  run_install_typed "$home" /usr/bin:/bin 'y\r' || return 0
  assert_contains "Added to $home/.bashrc"
  assert_eq "$(grep -cF 'export PATH="$HOME/.local/bin:$PATH"' "$home/.bashrc")" 1
  assert_eq "$(head -n 1 "$home/.bashrc")" '# existing'
  # Installing again does not ask nor duplicate the line.
  run_install_typed "$home" /usr/bin:/bin 'y\r'
  assert_contains 'already adds'
  assert_eq "$(grep -cF 'export PATH="$HOME/.local/bin:$PATH"' "$home/.bashrc")" 1
}

test_translation_install_leaves_bashrc_alone_when_declined() {
  local home
  home="$(fresh_home)"
  printf '# existing\n' >"$home/.bashrc"
  run_install_typed "$home" /usr/bin:/bin 'n\r' || return 0
  assert_contains 'add this line to'
  assert_eq "$(cat "$home/.bashrc")" '# existing'
}

test_translation_install_uses_zshrc_for_zsh() {
  local home
  home="$(fresh_home)"
  tty_session "HOME=$(printf '%q' "$home") PATH=/usr/bin:/bin SHELL=/usr/bin/zsh $(printf '%q' "$TRANSLATION") install" 'y\r' || return 0
  assert_contains "Added to $home/.zshrc"
  [[ ! -e "$home/.bashrc" ]] || fail 'wrote ~/.bashrc for a zsh user'
}

test_exec_requires_a_terminal() {
  OUT="$(TRANSLATION_PROJECT="$PROJECT" "$TRANSLATION" exec 2>&1 </dev/null)"
  STATUS=$?
  assert_status 1
  assert_contains 'needs an interactive terminal'
}

test_exec_shows_the_three_options() {
  run_exec q || return 0
  assert_contains '1. Show what is missing in Ahamatic'
  assert_contains '2. Preview the upload'
  assert_contains '3. Upload missing translations'
}

test_exec_quit_does_nothing() {
  with_credentials
  run_exec q || return 0
  assert_eq "$(mock_log | jq length)" 0
}

test_exec_escape_quits() {
  with_credentials
  run_exec "$ESCAPE" || return 0
  assert_eq "$(mock_log | jq length)" 0
  assert_not_contains 'Environment?'
}

test_exec_number_keys_run_diff() {
  with_credentials
  run_exec 1 1 q || return 0
  assert_choice 'What do you want to do\?' 'Show what is missing in Ahamatic'
  assert_choice 'Environment\?' 'development'
  assert_contains '(env: development, module: falckWebApp)'
  assert_row orphan en MISSING
  assert_no_writes
}

test_exec_arrows_select_preview_and_environment() {
  with_credentials
  run_exec "$ARROW_DOWN" "$ENTER" "$ARROW_UP" "$ENTER" q || return 0
  assert_choice 'What do you want to do\?' 'Preview the upload'
  # Up from the first option wraps to the last one.
  assert_choice 'Environment\?' 'production'
  assert_contains 'Dry run: nothing was written.'
  assert_no_writes
}

test_exec_vim_keys_move_the_selection() {
  with_credentials
  run_exec j j k "$ENTER" 2 q || return 0
  assert_choice 'What do you want to do\?' 'Preview the upload'
  assert_choice 'Environment\?' 'staging'
}

test_exec_upload_asks_before_writing() {
  with_credentials
  run_exec 3 1 'no\r' q || return 0
  assert_choice 'What do you want to do\?' 'Upload missing translations'
  assert_contains 'Type "yes" to write to development'
  assert_contains 'Aborted.'
  assert_no_writes
}

test_exec_upload_writes_after_yes() {
  with_credentials
  reset_mock "$(state_with '.failKeyNames = []')"
  run_exec 3 1 'yes\r' q || return 0
  assert_contains '✔ Done.'
  [[ -n "$(writes)" ]] || fail 'expected writes after confirming'
}

test_exec_returns_to_menu_after_running() {
  with_credentials
  run_exec 1 1 "$ENTER" 2 1 q || return 0
  assert_choice 'What do you want to do\?' 'Show what is missing in Ahamatic'
  assert_choice 'What do you want to do\?' 'Preview the upload'
}

test_exec_asks_for_missing_credentials_without_echoing_secrets() {
  run_exec 1 1 'svc@test.local\r' 'test-password\r' 'test-api-key\r' q || return 0
  assert_contains 'Ahamatic credentials'
  assert_row orphan en MISSING
  assert_not_contains 'test-password'
  assert_not_contains 'test-api-key'
}

test_exec_asks_for_the_project_folder() {
  with_credentials
  run_exec_raw '' '' "$PROJECT$ENTER" 1 1 q || return 0
  assert_contains 'Restock project folder'
  assert_contains "Restock translations ⇄ Ahamatic  $PROJECT"
  assert_row orphan en MISSING
}

test_exec_project_prompt_is_prefilled_with_current_restock_folder() {
  with_credentials
  run_exec_raw "cd $(printf '%q' "$PROJECT") &&" '' "$ENTER" 1 1 q || return 0
  assert_contains "Restock translations ⇄ Ahamatic  $PROJECT"
  assert_row orphan en MISSING
}

test_exec_rejects_a_folder_that_is_not_restock() {
  with_credentials
  run_exec_raw '' '' "/tmp$ENTER" "$CLEAR_LINE$PROJECT$ENTER" 1 1 q || return 0
  assert_contains '/tmp is not a Restock project (it has no lib/l10n/arb).'
  assert_row orphan en MISSING
}

test_exec_empty_project_folder_quits() {
  with_credentials
  run_exec_raw '' '' "$ENTER" || return 0
  assert_not_contains 'What do you want to do?'
  assert_eq "$(mock_log | jq length)" 0
}

test_exec_project_argument_skips_the_prompt() {
  with_credentials
  run_exec_raw '' "$(printf '%q' "$PROJECT")" 1 1 q || return 0
  assert_not_contains 'Restock project folder'
  assert_row orphan en MISSING
}

test_exec_project_argument_must_be_restock() {
  OUT="$(script -qec "$(printf '%q' "$TRANSLATION") exec /tmp" /dev/null </dev/null 2>&1 | tr -d '\r')"
  assert_contains '/tmp is not a Restock project'
}

test_exec_asks_again_after_rejected_credentials() {
  run_exec 1 1 'svc@test.local\r' 'wrong\r' 'test-api-key\r' "$ENTER" \
    1 1 'svc@test.local\r' 'test-password\r' 'test-api-key\r' q || return 0
  assert_contains 'Ahamatic rejected the credentials; they will be asked again.'
  assert_row orphan en MISSING
  assert_eq "$(mock_log | jq '[.[] | select(.path == "/api/auth/email")] | length')" 2
}

test_exec_remembers_credentials_between_runs() {
  run_exec 1 1 'svc@test.local\r' 'test-password\r' 'test-api-key\r' "$ENTER" 2 1 q || return 0
  assert_eq "$(grep -c 'Ahamatic credentials' <<<"$OUT")" 1
  assert_contains 'Dry run: nothing was written.'
}

test_exec_skips_credentials_prompt_when_available() {
  with_credentials
  run_exec 1 1 q || return 0
  assert_not_contains 'Ahamatic credentials'
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then OK=$'\033[32m✔\033[0m' KO=$'\033[31m✖\033[0m'; else OK='✔' KO='✖'; fi
passed=0
failed=()
while IFS= read -r test_name; do
  [[ -z "$FILTER" || "$test_name" == *"$FILTER"* ]] || continue
  reset_mock
  if (set +e; "$test_name") 2>"$WORK/test.err"; then
    printf '  %s %s\n' "$OK" "$test_name"
    passed=$((passed + 1))
  else
    printf '  %s %s\n' "$KO" "$test_name"
    cat "$WORK/test.err"
    failed+=("$test_name")
  fi
done < <(grep -oE '^test_[a-z0-9_]+' "${BASH_SOURCE[0]}")

echo
if ((${#failed[@]} == 0)); then
  echo "$passed passed"
else
  echo "$passed passed, ${#failed[@]} failed: ${failed[*]}"
  exit 1
fi
