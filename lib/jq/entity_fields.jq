# GET /api/entities/<entity> response -> {slug: field definition}, or null.
# `Schema` is a JSON string or an object (keyed by field) or a list; a field
# can be wrapped in an array (multiple references). Definitions have tempType,
# required, ref (referenced entity), default, ...

def field: if type == "array" then .[0] else . end;

(.lists[0].Schema // null)
| if type == "string" then fromjson else . end
| if type == "object" then
    to_entries | map((.value | field) as $f | select($f | type == "object")
      | {key: ($f.slug // .key), value: $f}) | from_entries
  elif type == "array" then
    map(field | select(type == "object" and .slug) | {key: .slug, value: .}) | from_entries
  else null end
