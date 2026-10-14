# diff.json -> table and per-locale summary (raw output lines).
# Args: $all (show ok/extra rows), $wide (no truncation), $cols (terminal
# width, 0 = unknown), $color (ANSI colors).

def labels: {missingKey: "NO KEY", missing: "MISSING", empty: "EMPTY", different: "DIFFERENT", ok: "OK", extra: "ONLY AHAMATIC"};
def pending: IN("missingKey", "missing", "empty", "different");
def paint($code): if $color then "\u001b[\($code)m\(.)\u001b[0m" else . end;
def paintStatus($status):
  if $status | IN("missingKey", "missing") then paint(31)
  elif $status | IN("empty", "different") then paint(33)
  elif $status == "ok" then paint(32)
  else paint(2) end;
def spaces($n): if $n > 0 then " " * $n else "" end;
def truncate($w): if length <= $w then . else .[0:$w - 1] + "…" end;
def oneLine: gsub("\r"; "") | gsub("\n"; "\\n");

.rows as $rows
| ($rows | map(select($all or (.status | pending)))) as $visible
| (if $visible == [] then
    "\("✔ Ahamatic has every local translation." | paint(32))"
  else
    ["#", "Key", "Lang", "Status", "Local", "Ahamatic"] as $headers
    | [ $visible | to_entries[] | .value as $r
        | ["\(.key + 1)", $r.key, $r.locale, labels[$r.status], ($r.local // "—" | oneLine), ($r.remote // "—" | oneLine)] ] as $cells
    | [ range(6) as $c | [$headers[$c], $cells[][$c]] | map(length) | max ] as $natural
    # Shrink the two value columns so the table fits the terminal.
    | (if $wide or $cols <= 0 then $natural
       else ($cols - ($natural[0:4] | add) - 19) as $available
       | ([20, ($available / 2 | floor)] | max) as $perValue
       | $natural[0:4] + [([$natural[4], $perValue] | min), ([$natural[5], $perValue] | min)]
       end) as $w
    | def border($l; $m; $r): $l + ($w | map("─" * (. + 2)) | join($m)) + $r;
      def line($values; $status; $header):
        "│ " + ([ range(6) as $c
                  | ($values[$c] | truncate($w[$c])) as $text
                  | (if $c == 0 then spaces($w[$c] - ($text | length)) + $text else $text + spaces($w[$c] - ($text | length)) end)
                  | if $header then paint(1) elif $c == 3 then paintStatus($status) else . end ]
                | join(" │ ")) + " │";
    border("┌"; "┬"; "┐"),
    line($headers; null; true),
    border("├"; "┼"; "┤"),
    ($cells | to_entries[] | line(.value; $visible[.key].status; false)),
    border("└"; "┴"; "┘")
  end),
  "",
  ("Summary" | paint(1)),
  ( $rows | map(.locale) | unique[] as $locale
    | [ $rows[] | select(.locale == $locale) ] as $ofLocale
    | "  \($locale)\(spaces(4 - ($locale | length))) "
      + ([ labels | keys_unsorted[] as $status
           | ($ofLocale | map(select(.status == $status)) | length) as $count
           | select($count > 0)
           | "\(labels[$status]): \($count)" | paintStatus($status) ] | join("   ")) ),
  "",
  "  NO KEY = key does not exist in Ahamatic · MISSING = key exists, no translation for that language",
  "  EMPTY = translation exists with empty value · DIFFERENT = value differs (only pushed with --update)"
