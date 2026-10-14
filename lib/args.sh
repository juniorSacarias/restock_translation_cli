# Options of `translation diff|push`.
#
# Globals set by parse_sync_args: COMMAND, PROJECT_DIR, ENV_NAME, ENV_FILE,
# MODULE, ARB_DIR, LOCALES, SHOW_ALL, WIDE, UPDATE, DRY_RUN, YES, KEY_ENTITY,
# SCHEMA_NAME, PAGE_SIZE, REQUEST_TIMEOUT, REVIEW.

bad_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
}

parse_sync_args() {
  COMMAND=diff
  PROJECT_DIR="$(default_project_dir)"
  ENV_NAME=development
  ENV_FILE=''
  MODULE=''
  ARB_DIR=''
  LOCALES=''
  SHOW_ALL=false
  WIDE=false
  UPDATE=false
  REVIEW=false
  DRY_RUN=false
  YES=false
  KEY_ENTITY=''
  SCHEMA_NAME=''
  PAGE_SIZE=100
  REQUEST_TIMEOUT=60

  local arg name value
  while (($#)); do
    arg="$1"
    case "$arg" in
      diff | push) COMMAND="$arg" ;;
      -h | --help) usage; exit 0 ;;
      --all) SHOW_ALL=true ;;
      --wide) WIDE=true ;;
      --update) UPDATE=true ;;
      --review) REVIEW=true ;;
      --dry-run) DRY_RUN=true ;;
      --yes) YES=true ;;
      --project | --env | --env-file | --module | --arb-dir | --locales | --key-entity | --schema | \
        --page-size | --timeout | \
        --project=* | --env=* | --env-file=* | --module=* | --arb-dir=* | --locales=* | --key-entity=* | --schema=* | \
        --page-size=* | --timeout=*)
        name="${arg%%=*}"
        if [[ "$arg" == *=* ]]; then
          value="${arg#*=}"
        else
          (($# > 1)) || bad_usage "Missing value for $name"
          shift
          value="$1"
        fi
        [[ -n "$value" ]] || bad_usage "Missing value for $name"
        case "$name" in
          --project) PROJECT_DIR="${value%/}" ;;
          --env) ENV_NAME="$value" ;;
          --env-file) ENV_FILE="$value" ;;
          --module) MODULE="$value" ;;
          --arb-dir) ARB_DIR="$value" ;;
          --locales) LOCALES="$value" ;;
          --key-entity) KEY_ENTITY="$value" ;;
          --schema) SCHEMA_NAME="$value" ;;
          --page-size | --timeout)
            [[ "$value" =~ ^[1-9][0-9]*$ ]] || bad_usage "$name must be a positive number"
            if [[ "$name" == --page-size ]]; then PAGE_SIZE="$value"; else REQUEST_TIMEOUT="$value"; fi
            ;;
        esac
        ;;
      *) bad_usage "Unknown argument $arg" ;;
    esac
    shift
  done

  if $UPDATE && $REVIEW; then
    bad_usage '--update and --review cannot be used together (--update overwrites every different value).'
  fi
  if [[ -z "$PROJECT_DIR" && (-z "$ENV_FILE" || -z "$ARB_DIR") ]]; then
    die 'Restock project not found. Run from the Restock repo root or pass --project=<path>.'
  fi
  PROJECT_DIR="$(expand_path "$PROJECT_DIR")"

  # With --env-file the label shown is the file name.
  [[ -z "$ENV_FILE" ]] || ENV_NAME="$(basename "$ENV_FILE")"
  ENV_FILE="${ENV_FILE:-$PROJECT_DIR/.env.$ENV_NAME}"
  ARB_DIR="${ARB_DIR:-$PROJECT_DIR/lib/l10n/arb}"
}
