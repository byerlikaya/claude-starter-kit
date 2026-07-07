---
name: commit-message
description: |
  Conventional Commits kurallarıyla commit mesajı üretir/denetler. Staged diff'i okuyup
  type(scope): özet formatında, gerektiğinde gövde + footer'lı mesaj önerir. commit-agent-cck
  bu skill'i uygular. Özet Türkçe; tek mantıksal değişiklik = tek commit.
  Trigger phrases: "commit mesajı", "commit at", "conventional commit", "commit yaz", "git commit"
---

# Commit Mesajı (Conventional Commits v1.0.0)

Format: `type(scope): özet` + (opsiyonel boş satır + gövde) + (opsiyonel footer).

## Type (zorunlu)
- `feat` — yeni özellik            · `fix` — hata düzeltme
- `docs` — sadece döküman          · `refactor` — davranış değişmeden yeniden yapı
- `perf` — performans              · `test` — test ekleme/düzeltme
- `build` — derleme/bağımlılık     · `ci` — CI yapılandırma
- `chore` — bakım/oto işler        · `revert` — önceki commit'i geri alma
- `style` — biçim (mantık yok)

### Hangi type? (belirsizde karar)
- Kullanıcıya yeni yetenek mi? → `feat`. Var olan yanlışı mı düzeltiyor? → `fix`.
- Davranış aynı, yapı mı değişti? → `refactor` (davranış değiştiyse `feat`/`fix`, refactor değil).
- Yalnız test/döküman/biçim dokundu? → `test`/`docs`/`style` (kod mantığına dokunma).

## Scope (opsiyonel, tercih edilir)
Etkilenen alan/modül: `auth`, `api`, `backend`, `db`, `frontend`, `session`, `agent` vb.
Tek kelime, projenin modül adıyla tutarlı.

## Özet satırı
- **Türkçe**, emir/özet kip, küçük harfle başla, sonunda nokta YOK, ≤ ~72 karakter.
- **Ne yaptığını** söyle, nasıl yaptığını değil; belirsiz kelimelerden kaçın ("düzeltme", "güncelleme", "wip").
  ✅ `feat(auth): tek-kullanımlık kod TTL + brute-force limiti`
  ❌ `fix: bug` · ❌ `update` · ❌ `değişiklikler`

## Gövde (opsiyonel — anlamlı değişiklikte önerilir)
Boş satırdan sonra: **NEDEN** (motivasyon) + belirgin sonuçlar/tradeoff'lar. ~72 karakterde sar.
git-blame'i açan gelecekteki okuyucu için bağlam bırak — "ne"yi diff zaten gösterir, sen "neden"i yaz.

## Footer (opsiyonel)
- `BREAKING CHANGE: <açıklama>` — geriye dönük kırıcı değişiklik (SemVer MAJOR tetikler, `release` skill).
- `Refs: #<issue>` / `Closes #<issue>`.

## Atomik commit — karışık diff'i bölme
Bir diff birden çok mantıksal değişiklik içeriyorsa **böl**, tek commit'e tıkma:
```bash
git add -p            # hunk hunk seç; ilgili değişiklikleri ayrı stage'le
git add <belirli/dosya>
```
Her commit tek konuya odaklı; "feat + fix + refactor" tek commit'te olmaz.

## İyi / kötü
| ✅ İyi | ❌ Kötü |
|---|---|
| `fix(db): IDOR'da 403 yerine 404 dön (varlık sızıntısını engelle)` | `fix: db sorunu` |
| `refactor(api): sorgu handler'larını tek sözleşmeye topla` | `refactor stuff` |
| `feat(session): oturum-sağlığı satırı + eşik kuralı` | `feat: yeni şeyler eklendi` |
| `revert: "feat(auth): kod TTL"` (sha) | `geri aldım` |

## Kurallar
- **Atomik:** tek mantıksal değişiklik = tek commit.
- **DoD'siz commit yok:** `/simplify` + testler yeşil + (.NET'te) `sonarqube-check` 0/0/0/0 geçmeden mesaj önerme.
- Staged diff yoksa uyar; `git add` kapsamını kullanıcıya SEÇMELİ sor.
- Sessiz `git commit` çalıştırma; mesajı öner, **onay bekle**.

## Yasaklar (mutlak — bkz. CLAUDE.md §4)
- **Yapay zeka izi yok:** subject/body'de `Co-Authored-By: …`, "Generated with …", 🤖 yok;
  "yapay zeka / asistan / model / copilot" ve `.claude` adı mesajda geçmez.
- **Vendor adı yok:** üçüncü-taraf şablon/iskelet adı ve "vendor copy / temizlik" ifşası mesaja yazılmaz (§4.2).
- **İnsansı Türkçe:** mesaj doğal, teknik, Türkçe.
- **Onay:** commit yalnız kullanıcı "commit et" dediğinde; "tamamlandı" onay değildir (§4.4).
- **Destrüktif:** amend / reset / force / `--no-verify` yalnız açık taleple; hook atlanmaz (§4.5).
