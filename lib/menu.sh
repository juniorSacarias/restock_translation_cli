# `translation exec [<path>]`: interactive menu. Asks for the Restock folder
# (unless given), then loops: action, environment, credentials (first time),
# run `translation diff|push`, back to the menu.

PROJECT=''

# ask_project: asks for the Restock folder (Tab completes, prefilled with the
# current directory when it is one). Sets $PROJECT; returns 1 on empty input.
ask_project() {
  local path default
  default="$(default_project_dir)"
  echo "$(bold 'Restock project folder') $(dim '(Tab completes · empty to quit)')"
  while true; do
    IFS= read -rep '  Path: ' -i "$default" path </dev/tty || return 1
    [[ -n "${path// /}" ]] || return 1
    path="$(expand_path "$path")"
    if is_project "$path"; then
      PROJECT="$(cd "$path" && pwd)"
      return 0
    fi
    warn "$path is not a Restock project (it has no lib/l10n/arb)."
    default="$path"
  done
}

cmd_exec() {
  [[ -t 0 && -t 1 ]] || die 'translation exec needs an interactive terminal; use translation diff|push instead.'
  trap 'printf "\033[?25h"' EXIT
  trap 'printf "\033[?25h\n"; exit 130' INT

  # The folder can be given as `exec <path>` or `exec --project=<path>`.
  local given=''
  case "${1:-}" in
    '') ;;
    --project=*) given="${1#*=}" ;;
    --project) given="${2:-}" ;;
    -*) bad_usage "Unknown argument $1" ;;
    *) given="$1" ;;
  esac
  if [[ -n "$given" ]]; then
    given="$(expand_path "$given")"
    is_project "$given" || die "$given is not a Restock project (it has no lib/l10n/arb)."
    PROJECT="$(cd "$given" && pwd)"
  else
    echo
    ask_project || return 0
  fi

  # Environments with a .env file, labelled with their API URL.
  local -a environments=() labels=()
  local name url
  for name in "${ENVIRONMENTS[@]}"; do
    [[ -f "$PROJECT/.env.$name" ]] || continue
    url="$(file_value AHA_API_URL "$PROJECT/.env.$name")"
    environments+=("$name")
    labels+=("$name|${url%/}")
  done
  ((${#environments[@]})) || die "No .env.development/.env.staging/.env.production in $PROJECT."

  local -a args
  local action key status
  while true; do
    echo
    printf '%s  %s\n\n' "$(bold 'Restock translations ⇄ Ahamatic')" "$(dim "$PROJECT")"

    select_option 'What do you want to do?' \
      'Show what is missing in Ahamatic|diff · read-only' \
      'Preview the upload|push --dry-run · read-only' \
      'Upload missing translations|push · asks before writing' \
      'Review values that differ|push --review · one by one, asks before writing' || return 0
    action=$SELECTED

    select_option 'Environment?' "${labels[@]}" || return 0
    name="${environments[SELECTED]}"

    # Asked once and kept in memory for the next runs of this menu.
    prompt_credentials
    case "$action" in
      0) args=(diff) ;;
      1) args=(push --dry-run) ;;
      2) args=(push) ;;
      3) args=(push --review) ;;
    esac

    # A separate process: an error there ends that run, not the menu. Ctrl+C
    # stops that run (it gets the SIGINT) and comes back to the menu.
    echo
    status=0
    trap 'status=130' INT
    "$TOOL_DIR/translation" "${args[@]}" --project="$PROJECT" --env="$name" || status=$?
    trap 'printf "\033[?25h\n"; exit 130' INT
    if ((status == 130)); then
      printf '\r\033[2K'
      warn 'Cancelled.'
    elif ((status == EXIT_AUTH)); then
      forget_credentials
      warn 'Ahamatic rejected the credentials; they will be asked again.'
    fi

    echo
    printf '%s ' "$(dim 'Enter: back to the menu · q: quit')"
    IFS= read -rsn1 key </dev/tty || key=q
    echo
    [[ "$key" == [qQ] ]] && return 0
  done
}
