# Arrow-key selector for interactive menus.

SELECTED=0

# select_option TITLE OPTION... : index of the choice in $SELECTED; returns 1
# when cancelled. An option can have a hint after a `|`: "Label|hint".
# Keys: ↑/↓ or k/j to move, Enter to choose, 1-9 to choose directly, q/Esc to quit.
# Reads keys from /dev/tty; draws in place with ANSI escapes.
select_option() {
  local title="$1"
  shift
  local -a options=("$@")
  local count=${#options[@]} selected=0 key rest i label hint width=0
  for i in "${!options[@]}"; do
    label="${options[i]%%|*}"
    ((${#label} > width)) && width=${#label}
  done

  _select_render() {
    for i in "${!options[@]}"; do
      label="${options[i]%%|*}"
      hint=''
      [[ "${options[i]}" == *'|'* ]] && hint="${options[i]#*|}"
      label="$((i + 1)). $label$(printf '%*s' "$((width - ${#label}))" '')"
      printf '\033[2K'
      if ((i == selected)); then
        printf '  %s %s   %s\n' "$(color 36 '❯')" "$(color '1;36' "$label")" "$(dim "$hint")"
      else
        printf '    %s   %s\n' "$label" "$(dim "$hint")"
      fi
    done
  }

  bold "$title"; echo " $(dim "↑/↓ Enter · 1-$count · q quit")"
  printf '\033[?25l'
  _select_render
  while true; do
    IFS= read -rsn1 key </dev/tty || key=q
    case "$key" in
      $'\x1b')
        rest=''
        IFS= read -rsn2 -t 0.1 rest </dev/tty || true
        case "$rest" in
          '[A') selected=$(((selected - 1 + count) % count)) ;;
          '[B') selected=$(((selected + 1) % count)) ;;
          '') key=q ;; # Esc alone
          *) continue ;;
        esac
        ;;
      k) selected=$(((selected - 1 + count) % count)) ;;
      j) selected=$(((selected + 1) % count)) ;;
      '') break ;; # Enter
      [1-9])
        if ((key <= count)); then
          selected=$((key - 1))
          break
        fi
        continue
        ;;
      q | Q) ;;
      *) continue ;;
    esac
    if [[ "$key" == [qQ] ]]; then
      printf '\033[%dA\033[J\033[?25h' "$((count + 1))"
      return 1
    fi
    printf '\033[%dA' "$count"
    _select_render
  done

  # Collapse the list into a single line with the choice.
  printf '\033[%dA\033[J\033[?25h' "$((count + 1))"
  printf '%s %s\n' "$(bold "$title")" "$(color 36 "${options[selected]%%|*}")"
  SELECTED=$selected
}
