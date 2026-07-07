---
name: i18n-integrity
description: |
  Translation integrity audit: is every text key present in all project languages, are there
  hardcoded strings, are placeholders/plurals consistent. Runs when user-facing text changes.
  Trigger phrases: "i18n", "translation", "language file", "missing translation", "localization", "translate"
---

# Translation Integrity (i18n)

Goal: no missing/broken text in any language. Default languages: **TR / EN / DE / RU** (the project sets these).

## Audit dimensions
- **Key parity:** every key has a counterpart in ALL languages; a missing/extra key = a finding.
- **No hardcoded strings:** user-facing text is not embedded in code, it comes from the language file.
- **Placeholder consistency:** `{name}`, `%s`, ICU `{count, plural, ...}` are identical in every language.
- **Plural rules:** language-specific plural forms (especially RU) are correct.
- **Empty/identical value:** an untranslated (identical to the source) placeholder value is flagged.

## Check (key-set comparison)
```bash
# Example: compare the key sets of JSON language files
for f in locales/*.json; do echo "== $f =="; jq -r 'keys[]' "$f" | sort > "/tmp/$(basename $f).keys"; done
diff /tmp/tr.json.keys /tmp/en.json.keys   # differences = missing/extra keys
```

## DoD
- Key sets are equal across all languages; no hardcoded user text; placeholders are consistent.
- **Missing translation = red** (no deferral).
