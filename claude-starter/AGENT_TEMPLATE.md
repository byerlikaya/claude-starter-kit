# Agent Şablon Kontratı (Claude Code)

Tüm uzman agent'lar bu iskelete uyar. Kanonik referans: **`backend-expert-cck`**.
İlke: **agent = ince tetikleyici** ("kim / ne zaman"), **skill = "nasıl"**. Bilgi skill'de, tetik agent'ta.

## Frontmatter (zorunlu alanlar)
- `name`: kebab-case, dosya adıyla birebir aynı.
- `description`: Claude Code delegasyon kararını **buna bakarak** verir. Üçünü içer:
  (1) ne yaptığı, (2) **NE ZAMAN** devreye gireceği, (3) `Trigger phrases:` satırı (TR anahtar ifadeler).
- `tools`: en az yetki ilkesi. Salt-okunur denetçi → `Read, Grep, Glob (+Bash)`; yazan uzman → `+ Edit, Write`.
- `model`: maliyet yönlendirmesi (aşağıdaki tablo). Alan yoksa ana oturum modeli miras alınır (inherit).

## Gövde bölümleri (sabit sıra)
1. **Ne zaman** — tetikleyici bağlam.
2. **Uzmanlık duruşu — önerilir.** O rolün en iyisinin farklı yaptığı 3-5 **role-özel** somut davranış (jenerik "uzman ol" değil). Kararı/tavrı yükseltir; mekanik "nasıl" skill'de kalır.
3. **Nasıl (skill'ini izle)** — hangi skill + o skill'in bu agent'a özel çıkış noktaları. Skill **tek bilgi kaynağıdır**; ajana "nasıl"ı kopyalama — en fazla hızlı-hatırlatma, çelişkide skill kazanır (§2 "tekrar yok").
4. **Koordinasyon (cross-agent) — yazan uzmanlar için önerilir.** Bu iş kime devredilir: güvenlik→security-expert-cck, şema→database-expert-cck, test→test-expert-cck, mesaj→i18n, kişisel veri→privacy-agent-cck, kapanışta bulgu→review-agent-cck. Ajanı orkestratöre çevirir; salt-okunur denetçilerde çoğu zaman gereksiz.
5. **DoD** — kapanış sorumluluğu: `/simplify` + testler yeşil + `sonarqube-check` (0/0/0/0, build 0/0).
6. **Çıktı & bağlam (token)** — ana thread'e ne döner: **kısa özet**, ham log/döküm değil; ağır çıktı `docs/*.md`'ye (token-budget skill).
7. **Hata/eskalasyon** — tıkanınca/emin olmayınca **dur-raporla** veya ilgili uzmana devret; tahminle ilerleme.
8. **Örnek delegasyon** — 1 ✅ tetikler / 1 ❌ tetiklemez satırı (delegasyon isabeti).
9. **Kısıtlar** — salt-okunur mu, neyi yapmaz, platform/politika sınırları.

## Model yönlendirmesi (maliyet kalibrasyonu)
**Tarihli model ID değil, tier ALIAS kullan** (`haiku`/`sonnet`/`opus`/`inherit`). Alias güncel
tier'a otomatik çözülür; model rename/deprecate olunca ajanlar sessizce kırılmaz. Tam ID
(`claude-sonnet-…`) yalnız belirli bir sürüme pinlemek şartsa.

| Agent | Rol | model | Neden |
|---|---|---|---|
| session-manager-cck | değerlendirme | `haiku` | hafif, kod yazmaz |
| security-expert-cck | denetim | `sonnet` | karar-yoğun (auth/IDOR) |
| review-agent-cck | denetim | `haiku` | salt-okunur bulgu |
| commit-agent-cck | mesaj üretimi | `haiku` | hafif, kod yazmaz |
| privacy-agent-cck | denetim | `sonnet` | karar-yoğun (KVKK) |
| planner-cck | planlama | `inherit` | kararlı akıl yürütme ister |
| backend-expert-cck | yazım | `inherit` | karmaşık kod, ana model |
| database-expert-cck | yazım | `inherit` | migration/şema riski |
| test-expert-cck | yazım | `inherit` | davranış doğruluğu |
| frontend-expert-cck | yazım | `inherit` | UI + native köprü |

Salt-okunur üçlüyü Haiku'ya çekmek token/maliyet düşürür; yazan uzmanlar tam güçte kalır.
(Alias'lar Claude Code frontmatter'ında geçerlidir; alan boşsa `inherit` varsayılır.)

## Yerleşim
- Proje-local (10): `./.claude/agents/` — session-manager-cck, backend/database/security/test/frontend-expert-cck, review-agent-cck, commit-agent-cck, planner-cck, privacy-agent-cck. Her şey repo içinde durur; home'a (`~/.claude`) bağımlılık yok (devir §3).
- Ekstra agent gerekmez; stack-özel "nasıl"lar `./.claude/skills/` altında (frontend'in "nasıl"ı projenin frontend skill'inde / CLAUDE.md'sinde).

## Referans örnek
`backend-expert-cck.md` bu kontratın birebir uygulanmış hali; yeni agent açarken onu kopyala, doldur.

