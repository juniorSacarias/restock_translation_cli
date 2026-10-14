# Compares local and Ahamatic translations.
# Args (--slurpfile): $local (locale -> key -> value), $languageIds (locale ->
# AppLanguages.Id), $translations (_translations rows, Key/Language populated),
# $keys (translation key rows).
# Output: {duplicates, keyIds: {name: Id}, rows: [...], renames: [...]}, see
# lib/diff.sh.

include "text";

def refId: if type == "object" then .Id elif type == "number" then . else null end;

$local[0] as $local | $languageIds[0] as $languageIds
| ($translations[0] | map(select((.Language | refId) != null and (.Key | type) == "object" and (.Key.Name // "") != ""))) as $valid
| ($valid | group_by([(.Language | refId), .Key.Name])) as $groups
# First translation per language + key name, in API order (_id DESC: the
# newest), which is also the one the app picks with firstWhere.
| ($groups | map(.[0] | {key: "\(.Language | refId)|\(.Key.Name)", value: .}) | from_entries) as $index
| ([$valid[].Key | {key: .Name, value: .Id}] + [$keys[0][] | select((.Name // "") != "") | {key: .Name, value: .Id}]
   | reverse | from_entries) as $keyIds
| ([$local[] | keys[]] | unique) as $localKeys
| ($localKeys | map({key: ., value: true}) | from_entries) as $isLocal
| ($languageIds | to_entries | map({key: (.value | tostring), value: .key}) | from_entries) as $localeOf

# Every local key in every language.
| [ $localKeys[] as $key
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
      } ] as $localRows

# Keys that only exist in Ahamatic (with a translation in a local language).
| [ $languageIds | to_entries[] | .key as $locale | .value as $languageId
    | [ $index[] | select((.Language | refId) == $languageId and $isLocal[.Key.Name] == null) ]
    | sort_by(.Key.Name)[]
    | {key: .Key.Name, locale: $locale, languageId: $languageId, local: null,
       remote: .Value, translationId: .Id, status: "extra"} ] as $extraRows

# Ahamatic-only keys -> {locale: value}, including keys without translations.
| ( reduce $extraRows[] as $row ({}; .[$row.key][$row.locale] = $row.remote)
    | reduce ($keys[0][] | select((.Name // "") != "" and $isLocal[.Name] == null)) as $k (.; .[$k.Name] //= {})
  ) as $remoteOnly

# Possible renames: a new local key and an Ahamatic-only key with the same
# name (ignoring case and separators), or with the same text in every
# language both have (at least one). Up to 3 candidates per key.
| [ [ $localRows[] | select(.status == "missingKey") | .key ] | unique[] as $localKey
    | [ $remoteOnly | to_entries[] | .key as $remoteKey | .value as $remoteValues
        | [ $languageIds | keys[] as $locale
            | select($local[$locale][$localKey] != null and $remoteValues[$locale] != null)
            | {locale: $locale,
               same: (($local[$locale][$localKey] | sameTextKey) == ($remoteValues[$locale] | sameTextKey))} ] as $compared
        | (($localKey | sameNameKey) == ($remoteKey | sameNameKey)) as $sameName
        | [ $compared[] | select(.same) | .locale ] as $sameText
        | select($sameName or (($sameText | length) > 0 and ($compared | all(.same))))
        | {key: $remoteKey, sameName: $sameName, sameText: $sameText} ]
    | sort_by([(if .sameName then 0 else 1 end), (0 - (.sameText | length)), .key])
    | select(length > 0)
    | {key: $localKey, candidates: .[0:3]} ] as $renames

| {
    duplicates: ($groups | map(length - 1) | add // 0),
    keyIds: $keyIds,
    rows: ($localRows + $extraRows),
    renames: $renames
  }
