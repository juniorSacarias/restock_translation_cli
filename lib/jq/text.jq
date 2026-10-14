# Text helpers shared by the jq programs (`include "text";`, run with -L lib/jq).

# Line breaks shown as \n so a value fits one table line.
def oneLine: gsub("\r"; "") | gsub("\n"; "\\n");

# Makes invisible differences visible: leading/trailing spaces as ␣,
# no-break spaces as ⍽ and tabs as →.
def visible:
  gsub(" "; "⍽") | gsub("\t"; "→")
  | sub("^(?<s> +)"; "\(.s | gsub(" "; "␣"))")
  | sub("(?<s> +)$"; "\(.s | gsub(" "; "␣"))");

# Without whitespace (including no-break spaces) at the start and end.
def strip: sub("^[\\s ]+"; "") | sub("[\\s ]+$"; "");

# For "same text" comparisons: stripped and lowercase.
def sameTextKey: strip | ascii_downcase;

# For "same name" comparisons: lowercase letters and digits only.
def sameNameKey: ascii_downcase | gsub("[^a-z0-9]"; "");
