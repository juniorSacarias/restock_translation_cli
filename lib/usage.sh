# Help text of the `translation` command.

usage() {
  cat <<'TEXT'
Restock translations ⇄ Ahamatic

Compares the local ARB translations of Restock with Ahamatic and uploads the
missing ones.

Usage:
  translation exec [<path>]        Interactive menu: asks for the Restock folder (unless
                                   given), what to do and the environment.
  translation [diff] [options]     Table of what is missing in Ahamatic (read-only).
  translation push [options]       Upload the missing keys/translations (asks first).
  translation test [filter]        Run the test suite.
  translation install              Link this command into ~/.local/bin.
  translation help                 Show this help.

Options (diff/push):
  --project=<path>   Restock repo root (where .env.* and lib/l10n/arb are).
                     Default: $TRANSLATION_PROJECT, else the current directory
                     when it is a Restock project.
  --env=<name>       .env.<name> file to read AHA_API_URL and MODULE_NAME from
                     (development | staging | production). Default: development
  --env-file=<path>  Use this .env file instead of .env.<name>.
  --module=<name>    Override MODULE_NAME.
  --arb-dir=<path>   Default: <project>/lib/l10n/arb
  --locales=en,da    Only these locales. Default: every app_<locale>.arb
  --all              Also show rows that are in sync and keys that only exist
                     in Ahamatic.
  --wide             Do not truncate values in the table.
  --update           push: also overwrite Ahamatic values that differ from the
                     local ones (by default only missing/empty are written).
  --review           push: ask for each value that differs whether to overwrite
                     it with the local one or keep Ahamatic's.
  --dry-run          push: show the plan and stop before writing.
  --yes              push: skip the confirmation prompt.
  --key-entity=<id>  Ahamatic entity referenced by _translations.Key. Discovered
                     from the schema when logging in with credentials.
  --schema=<name>    Application SchemaName, to discover --key-entity when
                     authenticating with a token.
  --page-size=<n>    Rows per request when reading from Ahamatic. Default: 100
  --timeout=<s>      Seconds before a request to Ahamatic is given up. Default: 60
  -h, --help         Show this help.

Credentials:
  Asked in the terminal (email, password, app API key) and only kept in
  memory. For non-interactive use, set them in the environment:
  AHA_TOKEN                               An Ahamatic JWT, or
  AHA_API_KEY + AHA_EMAIL + AHA_PASSWORD  POST /api/auth/email login.

Exit codes: 0 ok, 1 error or failed uploads, 3 credentials rejected, 64 bad arguments.

Examples:
  translation exec ~/Documentos/Volenday/Restock
  cd ~/Documentos/Volenday/Restock && translation diff --all
  translation push --dry-run
  translation push --review
  translation push --env=production
TEXT
}
