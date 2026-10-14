# One DIFFERENT row (diff.json) -> the lines shown by `push --review`.
# Args: $index, $total, $color.

include "text";

def paint($code): if $color then "\u001b[\($code)m\(.)\u001b[0m" else . end;

"\("(\($index)/\($total))" | paint(2)) \(.key | paint(1)) [\(.locale)]"
  + (if (.local | strip) == (.remote | strip) then "  " + ("only spaces at the start/end differ" | paint(33)) else "" end),
"  Local     \(.local | oneLine | visible)",
"  Ahamatic  \(.remote | oneLine | visible)"
