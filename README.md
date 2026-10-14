# restock-translation-script

`translation` compares the translations of the Restock app with the ones stored in Ahamatic and uploads the missing ones.

The Restock source of truth is the ARB files (`lib/l10n/arb/app_<locale>.arb`). The app also reads its texts from Ahamatic (`_translations` of the `falckWebApp` module), looking them up by key name. That key name must be the ARB message id. When a new text is added to the ARB files and not to Ahamatic, the app cannot find it there. This tool shows those gaps in a table and fills them.

```
Restock translations ⇄ Ahamatic  ~/Documentos/Volenday/Restock

What do you want to do? ↑/↓ Enter · 1-3 · q quit
  ❯ 1. Show what is missing in Ahamatic   diff · read-only
    2. Preview the upload                 push --dry-run · read-only
    3. Upload missing translations        push · asks before writing
```

## Contents

- [Getting started](#getting-started)
- [Usage](#usage)
- [What the table means](#what-the-table-means)
- [Command and option reference](#command-and-option-reference)
- [How it works](#how-it-works)
- [Safety](#safety)
- [Troubleshooting](#troubleshooting)
- [Project structure](#project-structure)
- [Maintenance guide](#maintenance-guide)
- [Tests](#tests)
- [Known limitations](#known-limitations)

## Getting started

### 1. Install the requirements

| Tool | Version | Used for |
|---|---|---|
| bash | 4+ | the tool itself |
| curl | any recent | HTTP calls to Ahamatic |
| jq | 1.7+ (tested with 1.8.1) | JSON processing, comparison and the table |
| python3 | 3.9+ | only for the tests (mock server) |
| `script` (util-linux) | any | only for the terminal tests (skipped when missing) |

Ubuntu / Debian:

```sh
sudo apt install curl jq
jq --version   # Ubuntu 22.04 ships jq 1.6, which is untested; get 1.7+ from https://jqlang.org/download/ if needed
```

macOS (the system bash is 3.2, too old):

```sh
brew install bash jq
```

### 2. Get the tool

Copy or clone the `restock-translation-script` folder anywhere on your machine. It does not need to be next to Restock: you tell it where Restock is when you run it.

### 3. Install the `translation` command

```sh
cd <path to>/restock-translation-script
./translation install
```

This links the command into `~/.local/bin`. On Ubuntu that folder is added to the `PATH` by `~/.profile` at login. If `translation` is not found, open a new terminal or run `source ~/.profile`.

```sh
translation help
```

### 4. Have your Ahamatic credentials at hand

The tool asks for them every time it starts:

- **Email** and **password** of the Ahamatic service account that Restock uses.
- **App API key**: the Ahamatic application API key.

Ask the team lead if you do not have them. They are only kept in memory while the tool runs and are never written to disk. The password and API key are not shown while you type them.

### 5. Run it

```sh
translation exec
```

1. **Restock project folder.** Type the path of your Restock checkout; Tab completes paths. If you start the tool from inside Restock, the path is already filled in and you just press Enter. You can also pass it directly: `translation exec ~/Documentos/Volenday/Restock`.
2. Choose **1. Show what is missing in Ahamatic**, then **development**, and type your credentials. Nothing is written; you get the table.
3. Choose **2. Preview the upload** to see how many keys and translations would be created.
4. Choose **3. Upload missing translations** and type `yes` to write them.
5. Run **1** again: there should be nothing pending (except `DIFFERENT` values, see below).

Within the same menu session the credentials are asked only once. If Ahamatic rejects them, they are forgotten and asked again on the next action.

## Usage

### Interactive menu

```sh
translation exec                       # asks for the Restock folder
translation exec ~/path/to/Restock     # skips that question
```

| Key | Action |
|---|---|
| ↑ / ↓ or k / j | move |
| Enter | choose |
| 1–9 | choose that option directly |
| q or Esc | quit |

After the action you pick the environment (development, staging or production, shown with their API URL). When the run finishes, Enter goes back to the menu.

### Command line

Run it from the Restock folder, or pass `--project=<path>` (or set `TRANSLATION_PROJECT`). The credentials are asked in the terminal.

```sh
cd ~/Documentos/Volenday/Restock
translation diff                       # table of what is missing (development)
translation diff --all                 # also rows in sync and keys only in Ahamatic
translation diff --env=production --wide
translation push --dry-run             # plan, nothing written
translation push                       # upload (asks you to type "yes")
translation push --update              # also overwrite values that differ
translation push --yes                 # no prompt (CI / scripts)
translation diff --project=~/path/to/Restock
```

Without a terminal (CI, scripts) nothing can be asked: put the credentials in environment variables (`AHA_API_KEY`, `AHA_EMAIL`, `AHA_PASSWORD`, or `AHA_TOKEN`) and use `--yes` for `push`.

`diff` is the default command, so `translation --all` is the same as `translation diff --all`.

## What the table means

```
┌───┬─────────┬──────┬───────────┬─────────────────────┬──────────┐
│ # │ Key     │ Lang │ Status    │ Local               │ Ahamatic │
├───┼─────────┼──────┼───────────┼─────────────────────┼──────────┤
│ 1 │ bye     │ da   │ EMPTY     │ Farvel              │          │
│ 2 │ bye     │ en   │ DIFFERENT │ Bye                 │ Bye old  │
│ 3 │ new_key │ en   │ NO KEY    │ Found {count} items │ —        │
│ 4 │ orphan  │ da   │ MISSING   │ Forældreløs         │ —        │
└───┴─────────┴──────┴───────────┴─────────────────────┴──────────┘
```

| Status | Meaning | What `push` does |
|---|---|---|
| `NO KEY` | The key does not exist in Ahamatic | creates the key and its translation |
| `MISSING` | The key exists, but has no translation for that language | creates the translation |
| `EMPTY` | The translation exists with an empty value | fills it |
| `DIFFERENT` | The Ahamatic value differs from the local one | nothing, unless `--update` |
| `OK` | Same value (only with `--all`) | nothing |
| `ONLY AHAMATIC` | The key is in Ahamatic but not in the ARB files (only with `--all`) | nothing (it never deletes) |

`DIFFERENT` is not overwritten by default because the value may have been edited in Ahamatic on purpose.

There is one row per key and language. A locale without an `AppLanguages` row in the module (for example `sv`) is skipped with a warning. Line breaks in values are shown as `\n`, and long values are cut to fit the terminal (`--wide` disables that).

## Command and option reference

| Command | Description |
|---|---|
| `translation exec [<path>]` | Interactive menu (asks for the Restock folder unless given) |
| `translation [diff] [options]` | Compare and print the table (read-only) |
| `translation push [options]` | Compare, show the plan, confirm and upload |
| `translation test [filter]` | Run the test suite (optionally only tests whose name contains `filter`) |
| `translation install` | Link the command into `~/.local/bin` |
| `translation help` | Help |

| Option | Default | Description |
|---|---|---|
| `--project=<path>` | `$TRANSLATION_PROJECT`, else the current directory if it is Restock | Restock repo root (`~` allowed) |
| `--env=<name>` | `development` | Reads `AHA_API_URL` and `MODULE_NAME` from `<project>/.env.<name>` |
| `--env-file=<path>` | | Use this `.env` file instead |
| `--module=<name>` | `MODULE_NAME` | Ahamatic module |
| `--arb-dir=<path>` | `<project>/lib/l10n/arb` | ARB folder |
| `--locales=en,da` | all ARB files | Only these locales |
| `--all` | | Also show `OK` and `ONLY AHAMATIC` rows |
| `--wide` | | Do not truncate values |
| `--update` | | `push`: also overwrite `DIFFERENT` values |
| `--dry-run` | | `push`: show the plan and stop |
| `--yes` | | `push`: no confirmation prompt |
| `--key-entity=<id>` | from the schema | Entity referenced by `_translations.Key` |
| `--schema=<name>` | from the login | Application `SchemaName`, to discover the key entity when using `AHA_TOKEN` |

Optional environment variables (they are not needed in the terminal):

| Environment variable | Description |
|---|---|
| `AHA_API_KEY`, `AHA_EMAIL`, `AHA_PASSWORD` | Credentials without asking (CI) |
| `AHA_TOKEN` | Ahamatic JWT instead of the login (`Bearer ` prefix optional) |
| `TRANSLATION_PROJECT` | Restock repo root |
| `NO_COLOR` | Disable colors |

Exit codes: `0` success, `1` error or some upload failed, `3` Ahamatic rejected the credentials or the token, `64` wrong arguments.

## How it works

The calls are the same the app makes (`lib/src/data/apis/translation_api.dart` in Restock), plus the writes.

1. **Login.** `POST /api/auth/email` returns the token and the application `SchemaName`. With `AHA_TOKEN` this step is skipped.
2. **Languages.** `GET /api/e/AppLanguages?filter[Module]=<module>` maps each ARB locale to its `AppLanguages.Id`, matched on `Language.Code`. That Id is what `_translations.Language` stores.
3. **Key entity.** `GET /api/entities/_translations?collection=<SchemaName>` returns the schema. The `ref` of its `Key` field is the translation keys entity.
4. **Remote data.** `GET /api/e/_translations?filter[Module]=…&fields[]=…` returns the translations, with `Key` and `Language` populated. `GET /api/e/<key entity>?filter[Module]=…` returns the keys, including those without any translation yet.
5. **Compare.** Builds one row per key and language (`lib/jq/diff.jq`) and prints the table (`lib/jq/table.jq`).
6. **Push**, in this order:
   1. Check the schemas: abort if an entity requires a field the tool does not send.
   2. `POST /api/e/<key entity>` with `{Name, Module}` for every `NO KEY`. The response gives the new key `Id`.
   3. `POST /api/e/_translations` with `{Module, Language: <AppLanguages Id>, Key: <key Id>, Value}` for every `NO KEY` and `MISSING` row.
   4. `PUT /api/e/_translations/<id>` with `{Value}` for `EMPTY`, and for `DIFFERENT` when `--update` is given.

Things learnt from the aha-api code that the tool relies on:

- **Query encoding.** Query parameters are parsed with `qs`, so filters must use brackets (`filter[Module]=x`, `fields[]=Id`). A JSON-encoded filter is not an error: it silently returns an empty list.
- **Reference fields.** They are numeric Ids in create and update bodies (`"Key": 123`), not objects.
- **Uniqueness.** The API does not enforce it, and nothing is created automatically (creating a key creates no translations). The tool reads what exists before writing.
- **Auth header.** The `authorization` header accepts the raw token or `Bearer <token>`.

## Safety

- **Read-only by default.** `diff`, `push --dry-run` and menu options 1 and 2 never write.
- **Confirmation.** `push` asks you to type `yes`, and `production` is shown in red. Without a terminal it refuses unless `--yes` is given.
- **Schema check.** Before writing, it checks the fields against the Ahamatic schemas and aborts with nothing written if they do not match.
- **Nothing is deleted.** Values that differ are only overwritten with `--update`.
- **Partial failures.** If a key cannot be created, its translations are skipped. Every failure is listed at the end, and the exit code is 1. Running `push` again retries only what is still missing.
- **Nothing left on the computer.** Credentials are asked in the terminal and only kept in memory (exported to the running process) until it ends; the password and API key are not echoed and never printed. Temporary files are deleted on exit. The tool does not write any config or cache (only `translation install` creates the `~/.local/bin/translation` link).

## Troubleshooting

| Message | Cause / fix |
|---|---|
| `translation: command not found` | Open a new terminal or `source ~/.profile` after `./translation install`; check `~/.local/bin` is in `PATH`. |
| `Restock project not found` / `.../.env.development not found` | `cd` into Restock, pass `--project=<path>` or set `TRANSLATION_PROJECT`. |
| `<path> is not a Restock project` | The folder has no `lib/l10n/arb`: point to the repo root of Restock. |
| `No Ahamatic credentials: run it in a terminal…` | Running without a terminal: set the credentials as environment variables. |
| `POST /api/auth/email → HTTP 401` | Wrong email, password or API key, or the account needs 2FA. In the menu they are asked again. |
| `HTTP 401 Failed to authenticate token` | `AHA_TOKEN` expired (180 min by default). Get a new one or use email/password. |
| `No AppLanguages row for "xx"` | That ARB locale is not configured for the module in Ahamatic. Add it there, or ignore it. |
| `Could not find the Key reference ... pass --key-entity` | The schema could not be read. Pass `--key-entity=<entity>` (the translation keys entity). |
| `Unknown translation key entity` | You are using `AHA_TOKEN`: also pass `--schema=<SchemaName>` or `--key-entity=<entity>`. |
| `Schema mismatch, nothing written` | The Ahamatic schema changed (a new required field, or a renamed one). Update `lib/push.sh`. |
| `No terminal to confirm` | `push` in CI or a pipe: add `--yes`. |
| jq `syntax error` / `compile error` | jq is too old; install 1.7+. |
| The table wraps or looks misaligned | Make the terminal wider, or use `--wide` and scroll. |

## Project structure

```
restock-translation-script/
├── translation             Entry point: loads lib/*.sh and dispatches the command
├── lib/
│   ├── common.sh           Colors, warn/die, KEY=VALUE file reader, temp dir, jq_file
│   ├── config.sh           Restock project location, .env files
│   ├── credentials.sh      Asks for credentials (memory only)
│   ├── usage.sh            Help text
│   ├── args.sh             diff/push options → globals
│   ├── arb.sh              Reads the local ARB files
│   ├── ahamatic.sh         Ahamatic API client (login, list, create, update, schemas)
│   ├── diff.sh             Fetches remote data, compares, prints the table
│   ├── push.sh             Upload plan, schema check, confirmation, writes
│   ├── sync.sh             `translation diff|push` flow
│   ├── selector.sh         Arrow-key selector
│   ├── menu.sh             `translation exec` (project folder prompt + menu loop)
│   ├── install.sh          `translation install`
│   └── jq/
│       ├── local_translations.jq   ARB files → {locale: {key: value}}
│       ├── language_ids.jq         locale → AppLanguages.Id
│       ├── entity_fields.jq        Ahamatic schema → {field: definition}
│       ├── diff.jq                 Comparison rows and statuses
│       ├── table.jq                Table and summary rendering
│       └── schema_problems.jq      Required/unknown fields check
├── tests/
│   ├── run_tests.sh        Test runner and test cases
│   ├── mock_ahamatic.py    Stateful mock of the Ahamatic API
│   └── fixtures/           ARB files, .env and initial remote state
└── README.md
```

Each `lib/*.sh` file starts with a comment that lists the globals it reads or sets. The `diff`/`push` flow is in `lib/sync.sh`:

```
parse_sync_args → load_env_file → read_local_translations
  → aha_authenticate (asks for credentials in a terminal) → fetch_remote
  → compute_diff → print_diff → [run_push]
```

Intermediate data goes to JSON files in a temp dir (`$TMP`). The temp dir is removed on exit:

| File | Content |
|---|---|
| `local.json` | local translations |
| `language_ids.json` | locale → AppLanguages Id |
| `translations.json` | remote `_translations` rows |
| `keys.json` | remote translation keys |
| `diff.json` | comparison result |

## Maintenance guide

| To change… | Edit |
|---|---|
| A new option | `lib/usage.sh` (help) + `lib/args.sh` (parsing), then use the global where needed |
| How statuses are decided | `lib/jq/diff.jq` |
| Table columns, colors, summary | `lib/jq/table.jq` |
| An Ahamatic endpoint or header | `lib/ahamatic.sh` |
| The fields sent when creating keys or translations | `lib/push.sh` (`create_keys`, `create_translations`) and the field lists in `check_schemas` |
| Menu options or texts | `lib/menu.sh` |
| Selector keys or look | `lib/selector.sh` |
| Environments offered in the menu | `ENVIRONMENTS` in `lib/config.sh` |
| How the project folder is found or asked | `lib/config.sh`, `ask_project` in `lib/menu.sh` |
| How credentials are asked | `lib/credentials.sh` |

Conventions:

- **Bash style.** `set -euo pipefail` is set in `translation`. Use `local` in functions, quote every expansion, and use `die` for fatal errors and `warn` for warnings.
- **JSON in `.jq` files.** Put JSON processing in `lib/jq/*.jq` and run it with `jq_file <name> …`, instead of long jq strings in bash.
- **Reading from the terminal.** Interactive code reads keys from `/dev/tty`. Check `[[ -t 1 ]]` in the caller, not inside a `$(...)`: inside it, stdout is a pipe.
- **New modules.** Add them to the `for module in …` list in `translation`.
- **Tests.** Every behaviour change gets a test (see below).

## Tests

```sh
translation test              # whole suite
translation test push         # only tests whose name contains "push"
tests/run_tests.sh exec_      # same runner, called directly
```

The tests run the real `translation` command against `tests/mock_ahamatic.py`, a local stateful mock of the Ahamatic endpoints (python3, standard library only). The mock behaves like aha-api where the tool depends on it: bracket query parsing, populated references, numeric Ids in bodies, 401 on a bad token, 422 for an invalid reference. Nothing reaches a real server, and credentials from your shell are never used.

What is covered:

- **Arguments and configuration:** help, wrong arguments, `--project` (with `~`), outside a Restock folder, `.env` parsing (spaces, quotes, trailing slash), `--module`, API down, no files left behind.
- **Credentials:** asked in a terminal without echoing the secrets; not asked when they are in the environment; required without a terminal; wrong credentials and expired token exit with code 3.
- **Comparison:**
  - every status and the summary counts;
  - that it never writes;
  - query encoding and auth header like the app;
  - keys from other modules ignored;
  - locales without `AppLanguages`, duplicates in Ahamatic, `--locales`, `AHA_TOKEN` auth.
- **Push:**
  - dry run, and confirmation without a terminal;
  - keys before translations, and translations using the new key Ids;
  - special characters sent unchanged;
  - `EMPTY` filled and `DIFFERENT` kept, or overwritten with `--update`;
  - a failing key, idempotency (a second push writes nothing), key entity discovery;
  - schema mismatch aborts without writing.
- **Terminal:** the table fits the width, `--wide`, the confirmation prompt, and `PRODUCTION` highlighted.
- **`translation` command and menu:** subcommands and `install`. The `exec` menu is driven with real key presses in a pseudo terminal:
  - the project folder prompt (typed, prefilled, not Restock, empty to quit, given as argument);
  - arrows, j/k, numbers, q, Esc, back to the menu;
  - credentials asked once per session, without echo, and asked again after being rejected.

To add a test, add a `test_<name>()` function to `tests/run_tests.sh`. It runs in a subshell after the mock is reset. Helpers:

| Helper | Purpose |
|---|---|
| `with_credentials` | export the test credentials |
| `run [args…]` | run `translation --env=test …` from the fixture project; sets `$OUT` and `$STATUS` |
| `run_tty INPUT COLUMNS [args…]` | same, in a pseudo terminal, with INPUT piped at once |
| `run_typed KEY…` | `translation --env=test` in a pseudo terminal, typing each KEY after a pause (for prompts) |
| `run_exec KEY…` | drive `translation exec` with key presses (`$ARROW_DOWN`, `$ENTER`, `$ESCAPE`, `$CLEAR_LINE`, …); the project prompt is accepted first |
| `run_exec_raw ENV EXEC_ARGS KEY…` | same, without accepting the project prompt (`ENV`: shell assignments, `EXEC_ARGS`: arguments of `exec`) |
| `reset_mock "$(state_with '<jq filter>')"` | start from a modified copy of `fixtures/state.json` |
| `mock_log`, `writes` | requests received by the mock |
| `assert_status`, `assert_contains`, `assert_not_contains`, `assert_row KEY LANG STATUS`, `assert_no_row`, `assert_eq`, `assert_no_writes`, `assert_choice` | assertions |

## Known limitations

- **Speed.** Requests are sent one at a time. Uploading a few hundred translations takes a couple of minutes.
- **Concurrent runs.** Ahamatic does not prevent duplicates, so do not run two `push` at the same time against the same environment.
- **No deletions.** Keys that only exist in Ahamatic are listed with `--all`, but never removed.
- **Plural forms.** ICU plural/select messages are compared and uploaded as plain strings, exactly as written in the ARB file.
