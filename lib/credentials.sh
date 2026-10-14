# Ahamatic credentials. They are asked in the terminal and only kept in
# memory (exported for the current process and its children); nothing is
# written to disk. AHA_TOKEN or AHA_API_KEY/AHA_EMAIL/AHA_PASSWORD from the
# environment are used as they are (for CI).

has_credentials() {
  [[ -n "${AHA_TOKEN:-}" ]] || [[ -n "${AHA_API_KEY:-}" && -n "${AHA_EMAIL:-}" && -n "${AHA_PASSWORD:-}" ]]
}

# Asks for the missing ones in /dev/tty. Password and API key are not echoed.
prompt_credentials() {
  has_credentials && return 0
  echo
  bold 'Ahamatic credentials'; echo " $(dim '(only kept in memory while this runs)')"
  local value
  if [[ -z "${AHA_EMAIL:-}" ]]; then
    read -rp '  Email: ' value </dev/tty
    export AHA_EMAIL="$value"
  fi
  if [[ -z "${AHA_PASSWORD:-}" ]]; then
    read -rsp '  Password: ' value </dev/tty
    echo
    export AHA_PASSWORD="$value"
  fi
  if [[ -z "${AHA_API_KEY:-}" ]]; then
    read -rsp '  App API key: ' value </dev/tty
    echo
    export AHA_API_KEY="$value"
  fi
}

forget_credentials() {
  unset AHA_TOKEN AHA_API_KEY AHA_EMAIL AHA_PASSWORD
}
