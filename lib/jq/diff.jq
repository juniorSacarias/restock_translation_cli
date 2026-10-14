# Compares local and Ahamatic translations.
# Args (--slurpfile): $local (locale -> key -> value), $languageIds (locale ->
# AppLanguages.Id), $translations (_translations rows, Key/Language populated),
# $keys (translation key rows).
# Output: {duplicates, keyIds: {name: Id}, rows: [...]}, see lib/diff.sh.

def refId: if type == "object" then .Id elif type == "number" then . else null end;

$local[0] as $local | $languageIds[0] as $languageIds
| ($translations[0] | map(select((.Language | refId) != null and (.Key | type) == "object" and (.Key.Name // "") != ""))) as $valid
| ($valid | group_by([(.Language | refId), .Key.Name])) as $groups
# First translation per language + key name.
| ($groups | map(.[0] | {key: "\(.Language | refId)|\(.Key.Name)", value: .}) | from_entries) as $index
| ([$valid[].Key | {key: .Name, value: .Id}] + [$keys[0][] | select((.Name // "") != "") | {key: .Name, value: .Id}]
   | reverse | from_entries) as $keyIds
| ([$local[] | keys[]] | unique) as $localKeys
| ($localKeys | map({key: ., value: true}) | from_entries) as $isLocal
| {
    duplicates: ($groups | map(length - 1) | add // 0),
    keyIds: $keyIds,
    rows: (
      # Every local key in every language.
      [ $localKeys[] as $key
        | $languageIds | to_entries[] | .key as $locale | .value as $languageId
        | $local[$locale][$key] as $localValue | select($localValue != null)
        | $index["\($languageId)|\($key)"] as $translation
        | {
            key: $key, locale: $locale, languageId: $languageId,
            local: $localValue, remote: $translation.Value, translationId: $translation.Id,
            status: (
              if $translation == null then (if $keyIds[$key] != null then "missing" else "missingKey" end)
              elif ($translation.Value // "") == "" then "empty"
              elif $translation.Value != $localValue then "different"
              else "ok" end)
          } ]
      # Keys that only exist in Ahamatic.
      + [ $languageIds | to_entries[] | .key as $locale | .value as $languageId
          | [ $index[] | select((.Language | refId) == $languageId and $isLocal[.Key.Name] == null) ]
          | sort_by(.Key.Name)[]
          | {key: .Key.Name, locale: $locale, languageId: $languageId, local: null,
             remote: .Value, translationId: .Id, status: "extra"} ]
    )
  }
