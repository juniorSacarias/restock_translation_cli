# Field definitions of an entity (lib/jq/entity_fields.jq) -> problems found,
# one "\n  <message>" per problem, or "" when the fields we send are fine.
# Args: $entity, $sent (comma separated fields the script sends).

($sent | split(",")) as $sent
| ($sent - keys) as $unknown
| [ to_entries[]
    | select((.value.required == true or .value.required == "true")
        and .value.default == null and (.key | IN($sent[]) | not))
    | .key ] as $required
| (if $unknown != [] then "\n  \($entity) has no field(s) \($unknown | join(", "))" else "" end)
  + (if $required != [] then "\n  \($entity) requires field(s) \($required | join(", ")) that this script does not send" else "" end)
