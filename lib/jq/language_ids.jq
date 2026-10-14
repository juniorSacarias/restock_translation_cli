# ARB locale -> AppLanguages.Id, the value _translations.Language references
# (null when the module has no AppLanguages row for that locale).
# Args (--slurpfile): $local (locale -> key -> value), $languages (AppLanguages rows).

def code: (.Language.Code // ((.LanguageTag // "") | split("-")[0] | split("_")[0])) | ascii_downcase;

[ $local[0] | keys[] as $locale
  | ($languages[0] | map(select(code == $locale)) | first) as $language
  | {key: $locale, value: $language.Id} ]
| from_entries
