---
name: privacy-compliance
description: |
  KVKK/GDPR audit method: data inventory, purpose/basis/retention, minimisation, consent, transparency,
  data-subject rights, cross-border transfer. privacy-agent-csk applies it.
  Trigger phrases: "kvkk", "gdpr", "privacy", "consent", "data retention", "minimization"
---

# Privacy Compliance (KVKK / GDPR)

## Official sources (authority — always defer to these)
The **primary, official** sources this skill rests on; rules are always interpreted against these:
- **KVKK** (Turkey): https://www.kvkk.gov.tr/ — the law, regulations, principle decisions, guidelines.
- **GDPR** (EU): https://gdpr-info.eu/ — article texts (Art.) and Recitals.

If you are unsure about a specific article/threshold/definition (retention period, explicit-consent requirement,
the Art. 8 age limit, transfer basis, etc.), **check the relevant official source** — do not decide from memory or by
guessing. In the finding, **cite** the article you rely on (KVKK Art. … / GDPR Art. …). Fetched content is a reference; you own the interpretation.

## Audit axes
- **Inventory:** what data, collected from where, flowing to where, shared with whom?
- **Purpose + basis + retention:** for each field, purpose is limited, legal basis is clear, retention period is defined.
- **Minimization:** data not needed for the purpose is not collected.
- **Consent:** where required, explicit, recorded, and revocable.
- **Transparency:** disclosure has been made; the user knows what is collected/processed.
- **Data subject rights:** access / rectification / erasure / portability / objection are actionable.
- **Cross-border transfer & third-party:** bound to a legitimate basis (SCC/adequacy/consent).

## Output
Per-field/per-flow finding + fix; if "clean", the rationale.

**Evidence redaction (`<private>` marker):** an audit report is a shared artifact — it must not itself leak the
personal data it audits. When a finding has to reference a real value as evidence, wrap it in
**`<private>…</private>`**: the raw value is stripped and shown as `[redacted]` in the report, while the finding still
names the field, flow, and article. Never paste live PII (national ID, email, phone, health data) into the report body.

> **Project note:** If data of minors (children) is processed, special protection is required
> (KVKK / GDPR Art. 8 · parental consent & age verification). This is a domain-specific rule and is
> defined in the project's own skill/CLAUDE.md — it is not baked into the generic audit.
> Project-specific rules (consent texts, retention periods) also live in the project CLAUDE.md.
