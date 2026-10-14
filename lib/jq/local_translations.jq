# ARB files (inputs) -> {locale: {key: value}}.
# The locale comes from @@locale or from the app_<locale>.arb file name.
# Metadata entries (@key) and non-string values are left out.
# Args: $locales, comma separated filter ("" = all).

($locales | split(",") | map(select(. != ""))) as $only
| reduce inputs as $arb ({};
    ($arb["@@locale"] // (input_filename | capture("app_(?<l>\\w+)\\.arb$").l // "")) as $locale
    | if $locale == "" or ($only != [] and ($only | index($locale)) == null) then .
      else .[$locale] = ($arb | with_entries(select((.key | startswith("@") | not) and (.value | type) == "string")))
      end)
