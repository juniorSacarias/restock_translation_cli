# `translation install`: links the command into ~/.local/bin and, when that
# folder is not on the PATH, offers to add it to the shell rc file (asks
# first; without a terminal it only prints the line to add).

INSTALL_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

# Shell rc file where the PATH line goes.
shell_rc_file() {
  if [[ "${SHELL##*/}" == zsh ]]; then
    printf '%s' "$HOME/.zshrc"
  else
    printf '%s' "$HOME/.bashrc"
  fi
}

cmd_install() {
  local bin="$HOME/.local/bin" rc answer
  mkdir -p "$bin"
  ln -sfn "$TOOL_DIR/translation" "$bin/translation"
  echo "Linked $bin/translation -> $TOOL_DIR/translation"

  case ":$PATH:" in
    *":$bin:"*)
      echo "Ready: run $(bold 'translation exec')."
      return 0
      ;;
  esac

  rc="$(shell_rc_file)"
  if [[ -f "$rc" ]] && grep -qF "$INSTALL_PATH_LINE" "$rc"; then
    echo "$rc already adds $bin to the PATH. Open a new terminal or run: source $rc"
    return 0
  fi

  echo
  warn "$bin is not in your PATH, so the shell cannot find \`translation\`."
  if [[ -f "$HOME/.bash_profile" && "${SHELL##*/}" != zsh ]]; then
    echo "  (You have ~/.bash_profile, so bash does not read ~/.profile, which is where Ubuntu adds it.)"
  fi

  if [[ -t 0 ]]; then
    read -rp "Add it to $rc? [y/N] " answer
    if [[ "${answer,,}" == y || "${answer,,}" == yes ]]; then
      printf '\n# Added by restock-translation-script (translation install)\n%s\n' "$INSTALL_PATH_LINE" >>"$rc"
      echo "Added to $rc. Open a new terminal or run: source $rc"
      return 0
    fi
  fi
  echo "To use it, add this line to $rc and open a new terminal:"
  echo "  $INSTALL_PATH_LINE"
  echo "Or run it with its full path: $bin/translation exec"
}
