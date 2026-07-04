# Agentik Çalışma Kiti (Claude Code)

Herhangi bir projede aynı disiplinle ilerleten, yeniden kullanılabilir bir Claude Code iskeleti:
**planla → üret → denetle → commit'le**, her adımda kalite ve iz-temizliği kapılarıyla.
Yığın-bağımsızdır; hangi projeye kurulursa kurulsun aynı disiplin geçerlidir.

**Sürüm:** 1.0.0 · Lisans: MIT · [Değişiklik günlüğü](CHANGELOG.md)

## Felsefe (üç ilke)

1. **Ajan = ince tetikleyici** ("kim / ne zaman"). Kısa; hangi işte devreye gireceğini ve dayandığı skill'i söyler.
2. **Skill = nasıl** (tek bilgi kaynağı). Asıl yöntem/kural skill'de durur, ajana kopyalanmaz.
3. **Kural → kapı.** Kritik kurallar modelin hatırlamasına değil, **araç seviyesinde** zorlanır (hook + permission + eval).

## Kurulum

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic]
```

`start.sh` bir **kurulum sihirbazıdır**: bayrak vermezsen adımları interaktif sorar (profil → backend yığını → özet + onay). Bayraklar sessiz/CI modu içindir. Core ajan/skiller her profilde kurulur; yalnız stack-özel olanlar profile göre eklenir/çıkarılır:

| Profil | Ekstra ajan | Ekstra skiller | Backend temeli |
|---|---|---|---|
| `--backend` | backend-expert · database-expert | db-migration · api-design (+ yığına göre) | yığın seçimine bağlı |
| `--frontend` | frontend-expert | frontend · i18n-integrity · a11y | — atlanır |
| `--mobile` | frontend-expert | frontend · frontend-rn-expo · i18n-integrity · a11y | — atlanır |
| `--fullstack` | üçü birden | hepsi (+ yığına göre) | yığın seçimine bağlı |

*(Core skiller — observability · docs-writer dahil — her profilde kurulur; tablo yalnız stack-özel farkları gösterir.)*

**Backend yığını** (yalnız `--backend`/`--fullstack`; varsayılan `--dotnet`):

| Yığın | Backend ajanı | Ekstra backend skilleri | DevArchitecture |
|---|---|---|---|
| `--dotnet` | backend-expert (.NET/DevArchitecture) | devarch-module · sonarqube-check | ✅ onay kapısı |
| `--generic` | backend-expert (yığın-bağımsız varyant) | — (yalnız db-migration) | — kurulmaz |

> **Mobil için ayrı ajan yoktur** — mobil, `frontend-expert` üzerine `frontend-rn-expo` **skill katmanı** olarak gelir (ajan = tetik, skill = nasıl). **Jenerik backend** de ayrı ajan değil: `backend-expert`'in DevArchitecture'sız, yığın-bağımsız varyantı kurulur (Node/Go/Python için); derin backend skilleri (`db-migration` hariç) .NET'e özel olduğundan gelmez.

> **Amaç & sınır:** Bu kit, **sıfırdan** bir projeyi DevArchitecture backend temeli üzerine kurmak
> için tasarlandı. `start.sh` ilk adımda bunu bir **onay kapısıyla** ele alır: temel projede yoksa
> ve onay verirseniz DevArchitecture'ı depodan çekip projeye birebir dahil eder. Temel zaten varsa
> bu adımı atlar. **Mevcut** bir projede temel yoksa, eklemenin yapıyı bozabileceğine dair ciddi bir
> uyarı verir ve yalnız açık onayla ilerler. (Disiplin katmanı + frontend yığın-bağımsızdır; yalnız
> backend opinionated'dır.)

`./.claude/` (agents · skills · commands · hooks · eval · settings.json) ve kök `./CLAUDE.md` kurulur;
`.gitignore`'a `docs/ · .claude/ · CLAUDE.md` eklenir; git deposu varsa `core.hooksPath` ayarlanır;
kurulum artıkları (`claude-starter/` + `start.sh`) temizlenir. Sonra Claude Code'u repo kökünde açıp
`ILK_PROMPT.md` içeriğini yapıştır.

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # statik yapı
bash .claude/eval/routing-eval.sh    # davranışsal routing
```

- **smoke-test:** frontmatter, trigger phrase, ajan sayısı, sahipsiz-skill referansı, stub kalıntısı, hook/settings hazırlığı.
- **routing-eval:** örnek prompt'lar beklenen ajan/skill'e trigger ile yönleniyor mu (golden routing) + iki ajan aynı trigger'ı paylaşıyor mu (çakışma). Türkçe diyakritiği normalize eder; budanmış kurulumda eksik hedefi atlar. Claude Code çalıştırmaz.

## İçindekiler

- **10 ajan** (`.claude/agents/`): planner · backend-expert · database-expert · security-expert ·
  privacy-agent · test-expert · frontend-expert · review-agent · commit-agent · session-manager.
  Her ajan: uzmanlık duruşu · koordinasyon · çıktı sözleşmesi · hata/eskalasyon · örnek delegasyon.
- **27 skill** (`.claude/skills/`): disiplin katmanı — code-review, security-scan, db-migration,
  vps-deploy, devarch-module, sonarqube-check, commit-message, spec-planning, privacy-compliance,
  ci-pipeline, dependency-audit, adr, release, i18n-integrity, handoff, testing, frontend,
  frontend-rn-expo, trace-scan, token-budget, observability, docs-writer, a11y, api-design,
  performance, incident-runbook, red-team.
- **5 slash komut** (`.claude/commands/`): `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hook'lar** (`.claude/hooks/`): `pre-commit` + `commit-msg` (iz-denetçisi), `guard-bash.sh` (destrüktif blok), `trace-blocklist.txt`, **`context-usage.sh`** (gerçek context ölçümü — aşağı).
- **settings.json**: izin (ask/deny) + PreToolUse guard + **UserPromptSubmit** (her tur gerçek context enjekte eder).

### Gerçek context ölçümü (özellik)
Asistan `/context` komutunu çalıştıramaz — bu yüzden çoğu setup oturum doluluğunu **tahmin eder**. Bu kit etmez: `context-usage.sh`, transcript'teki son turun API `usage`'ından (`input + cache_read + cache_creation`) **gerçek** token sayısını okur (= `/context`'in gösterdiği). `UserPromptSubmit` hook'u bunu her tur otomatik context'e enjekte eder, böylece oturum-sağlığı satırı (`🔋 %.. → devam/handoff`) **ölçüme** dayanır, tahmine değil. Elle: `bash .claude/hooks/context-usage.sh` (pencere farklıysa `CONTEXT_WINDOW=...`).
- **CLAUDE.md** (kök): davranış · dört ilke · iş akışı · DoD · token disiplini · güvenilmeyen içerik · §4 yasaklar.
- **AGENT_TEMPLATE.md**: yeni ajan/skill açma kontratı.

## Kullanım (iş akışı)

`/plan` (belirsiz kapsam) → uzman ajanlar üretir → `/review` (güvenlik + kalite + test) →
`/ship` (DoD kapısı + commit önerisi, onay bekler) → context dolunca `/handoff` → `/clear`.

## Zorlama katmanları (kural → kapı)

| Kural | Mekanizma |
|---|---|
| §4.1 yapay zeka izi yok · §4.2 vendor adı yok | git `pre-commit` + `commit-msg` hook (`trace-scan`) |
| §4.4 commit/push yalnız onayla | `settings.json` `permissions.ask` |
| §4.5 destrüktif işlem (reset --hard, force push, --no-verify, rm -rf…) | `guard-bash.sh` PreToolUse hook (exit 2 blok) |
| DoD (test/kalite) | `sonarqube-check` + `/ship` kapısı |

## §4 Yasaklar (özet)

- **4.1** Commit/kod/config'te yapay zeka izi yok (co-author, "Generated with", 🤖, "yapay zeka/asistan/model/copilot").
- **4.2** Üçüncü-taraf şablon/vendor adı hiçbir artefakta geçmez.
- **4.3** `docs/` ve `.claude/` gitignore'da; adları artefakta geçmez.
- **4.4** Commit/push yalnız açık onayla ("tamamlandı" onay değildir).
- **4.5** Destrüktif işlem (reset --hard / force push / clean -f / --no-verify / amend) açık talep ister.

## Genişletme

Yeni ajan/skill için `AGENT_TEMPLATE.md` kontratını izle: frontmatter (name · description +
Trigger phrases · tools en-az-yetki · model tier alias/inherit) → gövde (Ne zaman → Uzmanlık duruşu →
Nasıl/skill → Koordinasyon → DoD → Çıktı & bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Notlar

- Her şey **proje-local** (`./.claude`), home'a bağımlılık yok.
- `.claude` ve `CLAUDE.md` gitignore'da — lokal kalır, repoya gitmez.
- Varsayılan backend `.NET + DevArchitecture` opinionated'dır; frontend yığın-bağımsızdır (RN+Expo bir seçenek).

## Lisans

MIT — bkz. [LICENSE](LICENSE).

## Kaynaklar & Atıf

Bu kit bazı disiplinleri üst kaynaklardan uyarlar (code-review → google/eng-practices, CC-BY 3.0;
devarch-module → DevArchitecture kalıbı). Ayrıntı için bkz. [ATTRIBUTION.md](ATTRIBUTION.md).
