<div align="center">

# 🛠️ Claude Starter Kit

**Claude Code için agentik çalışma kiti** — bir projeyi, hangi aşamada olursa olsun, aynı mühendislik disipliniyle ilerleten yeniden kullanılabilir bir iskelet.

*planla → üret → denetle → commit'le; her kritik kural bir **hatırlatma değil, kapı**.*

![Sürüm](https://img.shields.io/badge/s%C3%BCr%C3%BCm-1.0.5-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/lisans-MIT-16a34a?style=flat-square)
![Ajanlar](https://img.shields.io/badge/ajanlar-11-f59e0b?style=flat-square)
![Skiller](https://img.shields.io/badge/skiller-27-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentik_kit-8b5cf6?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

</div>

---

## Neden bu kit?

Çoğu "agent kurulumu" bir öneriler yığınıdır — kurallar bir dosyada durur, uyulup uyulmaması modele kalır. Bu kit farklı: Claude Code'a **disiplinli bir mühendislik ekibi** yerleştirir; burada **önemli kurallar hatırlatma değil, kapıdır.**

| | |
|---|---|
| 👥 | **Bir prompt değil, bir ekip** — 11 uzman ajan planla → üret → denetle → gönder boyunca kendiliğinden zincirlenir; sen bağlamazsın, ana thread yapar. |
| 🛡️ | **Güvenlik & gizlilik seçenek değil, kapı** — risk-kritik değişiklikler kapanmadan önce güvenlik/gizlilik denetiminden geçmek zorundadır. |
| 🚦 | **Her commit senin onayınla** — `commit`/`push` senin açık onayın olmadan çalışmaz; otomatik/bypass modda bile araç seviyesinde zorlanır. |
| 🌿 | **Mevcut repoda güvenli** — `adopt` kiti bir dala devreder; `main`'e asla dokunulmaz, saklamadan önce incelersin. |

---

## 🧠 Ajanlar — kitin kalbi

**11 ajan**; her biri bir **ince tetikleyici** — yalnızca *kim* ve *ne zaman*'ı söyler, *nasıl*'ı bir skill'e bırakır. Ana thread onları **beş aşamada** seçip zincirler ve commit'ten önce kaliteyi kademe kademe yükseltir:

<div align="center">
  <img src="assets/orchestration-tr.svg" alt="Bes asamada ajan orkestrasyonu" width="740">

  🧭 **Anla** &nbsp;→&nbsp; 🔨 **Üret** &nbsp;→&nbsp; 🔍 **Denetle** &nbsp;→&nbsp; ✅ **Kapat** &nbsp;→&nbsp; 🤝 **Devret**

</div>

| Ajan | Aşama | Ne zaman devreye girer | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Anla | kapsam belirsizse | `inherit` |
| **backend-expert-csk** | 🔨 Üret | sunucu / API / iş mantığı | `inherit` |
| **database-expert-csk** | 🔨 Üret | şema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Üret | UI, bileşen, istemci işi | `inherit` |
| **devops-expert-csk** | 🔨 Üret | dağıtım, CI hattı, olay | `inherit` |
| **security-expert-csk** | 🔍 Denetle | auth / IDOR / injection / secret · **güvenlik-kritikse zorunlu** | `sonnet` |
| **privacy-agent-csk** | 🔍 Denetle | kişisel veri (KVKK / GDPR) | `sonnet` |
| **test-expert-csk** | 🔍 Denetle | test, kapsam, regresyon | `inherit` |
| **review-agent-csk** | ✅ Kapat | commit öncesi kod-sağlığı denetimi | `haiku` |
| **commit-agent-csk** | ✅ Kapat | commit'i önerir, onay bekler | `haiku` |
| **session-manager-csk** | 🤝 Devret | bağlam dolunca / faz sınırında | `haiku` |

> Ajan adları `-csk` ekiyle isimlenir (Claude Starter Kit); böylece kurulduğu projenin kendi ajanlarıyla asla çakışmaz. Her ajan incedir; asıl yöntem bir **skill**'de yaşar — tek bilgi kaynağı.

---

## Üç ilke

1. **Ajan = ince tetikleyici.** Bir ajan yalnızca "kim, ne zaman"ı söyler; kısa kalır ve işin nasılını skill'e bırakır.
2. **Skill = tek bilgi kaynağı.** Asıl yöntem ve kural skill'de yaşar; ajana kopyalanmaz.
3. **Kural → kapı.** Önemli olan kural araç seviyesinde zorlanır (hook · permission · eval). Modelin onu anımsaması beklenmez.

---

## Kurulum & çalıştırma

**İki giriş noktası** var: `start.sh` **sıfırdan** projeyi kurar; **`adopt`** (`adopt.sh`) kiti **mevcut** projeye devreder. Hangi kanalı seçersen seç — her biri aynı iki komutu çalıştırır.

**npx** — kurulum gerektirmez:
```bash
npx @byerlikaya/claude-starter-kit          # sıfırdan proje
npx @byerlikaya/claude-starter-kit adopt    # mevcut proje
```

**Homebrew:**
```bash
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit          # sıfırdan proje
claude-starter-kit adopt    # mevcut proje
```

**Release tarball** — paket yöneticisi yok:
```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # sıfırdan proje
bash adopt.sh              # mevcut proje
```

> Sadece ajan & skill'leri mevcut Claude Code'una istiyorsan (scaffold yok)? `/plugin marketplace add byerlikaya/claude-starter-kit` sonra `/plugin install claude-starter-kit@byerlikaya`.

### 🌱 Sıfırdan proje — `start.sh`

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic] [-h]
```

Bir kurulum sihirbazı. Bayrak vermezseniz adımları tek tek sorar (profil → backend yığını → özet ve onay); bayraklar sessiz/CI kullanımı içindir ve `-h` / `--help` kullanımı basar. Her seçenek ne kuracağını **kurmadan önce** gösterir.

| Profil | Uzman ajanlar | Öne çıkan skiller |
|---|---|---|
| `--backend` | backend · database | db-migration · api-design · observability |
| `--frontend` | frontend | frontend · a11y · i18n-integrity |
| `--mobile` | frontend (+ React Native/Expo katmanı) | frontend-rn-expo · a11y |
| `--fullstack` | hepsi | tüm skiller |

Backend yığını yalnız `--backend`/`--fullstack` için sorulur: **`--dotnet`** .NET / DevArchitecture kalıbını (MediatR CQRS · IResult · AOP) bir onay kapısıyla getirir; **`--generic`** ise Node, Go, Python ve benzeri için yığın-bağımsız bir backend uzmanı kurar.

> **`--fullstack` + `--dotnet`** seçilince DevArchitecture backend `./backend`'e konur, `./frontend` frontend'in için ayrılır ve çözüm dosyası proje adına yeniden adlandırılır — kök, çıplak bir backend gibi görünmek yerine tertemiz kalır.

### 🔄 Mevcut projeye devir — `adopt.sh`

```bash
bash adopt.sh          # hedef projenin kökünde
```

Kiti, zaten ilerleyen bir projeye **bir ekibin projeyi başka bir ekibe devretmesi** gibi uygular — proje bozulmaz, alınmış kararlar kaybolmaz, kit de pasif kalmaz.

<div align="center">
  <img src="assets/handover-tr.svg" alt="adopt.sh devir akisi" width="900">
</div>

Tüm değişiklik ayrı bir git dalına **staged (commit'siz)** düşer — böylece eklenen/değişen her dosya editörünün Source Control / Changes panelinde görünür; oradan inceler, sonra `git commit` ile kabul (ya da reset ile iptal) edersiniz. `main` el değmez. Kit ajanları yan yana kurulur (çakışmadan), disiplin tek `@import` ile bağlanır, `settings.json` şema-farkında birleştirilir ve mevcut husky/lefthook zincirleri kitle bir köprü üzerinden birlikte çalışır. Kapanışta kalıcı bir `docs/HANDOVER.md` ve bir ADR bırakır — kararlar sohbette değil, versiyon kontrolünde yaşar.

---

## İçindekiler

- **11 ajan** — yukarıdaki tabloya bakın.
- **27 skill** — "nasıl"ın tek kaynağı: kod gözden geçirme, güvenlik taraması, migration, dağıtım, gözlemlenebilirlik, performans, erişilebilirlik, çeviri bütünlüğü, sürümleme, olay müdahalesi ve daha fazlası.
- **5 slash komut** — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hook'lar** — `guard-bash.sh` (araç seviyesi kapı), `pre-commit` + `commit-msg` (iz-denetimi), `context-usage.sh` ve `session-guard.sh` (oturum ölçümü).
- **CLAUDE.md** — davranış, üç ilke, iş akışı, tamamlanma tanımı (DoD), token disiplini ve yasaklar.

---

## Oturum & token yönetimi

Bir asistan `/context` komutunu kendisi çalıştıramaz; bu yüzden çoğu kurulum oturum doluluğunu **tahmin eder**. Bu kit ölçer. `context-usage.sh`, transcript'teki son turun API kullanımından gerçek token sayısını okur — `/context`'in gösterdiği değerin aynısı. `UserPromptSubmit` hook'u bunu her tur enjekte eder; `Stop` hook'u (`session-guard.sh`) doluluk **%75'i aştığında** devir önerisini yüzeye çıkarır. Oturum-sağlığı satırı bir ölçüme dayanır, tahmine değil.

---

## Kural → kapı

| Kural | Zorlayan mekanizma |
|---|---|
| Commit/push yalnız onayla — otomatik/bypass modda bile | `guard-bash.sh` (PreToolUse); `CLAUDE_GIT_OK` ile açılır |
| Destrüktif işlem (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (araç seviyesinde blok) |
| Commit'te yapay-zeka izi / dış vendor adı yok | `pre-commit` + `commit-msg` git hook (iz-denetimi) |
| Oturum eşiği | `context-usage.sh` + `session-guard.sh` (Stop hook) |
| Kalite kapısı (SonarQube kullanan projeler — dil-bağımsız) | `sonarqube-check` + `/ship` |

Kapılar `settings.json` ve git `core.hooksPath` üzerinden silahlanır; `smoke-test.sh` her değişiklikten sonra hazır olduklarını doğrular.

---

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek prompt doğru ajan/skill'e mi gidiyor
```

## İş akışı

`/plan` (belirsiz kapsam) → uzman ajanlar üretir → `/review` (güvenlik · kalite · test) → `/ship` (DoD kapısı; commit'i önerir, onay bekler) → bağlam dolunca `/handoff` → `/clear`.

## Genişletme

Yeni bir ajan veya skill eklerken `AGENT_TEMPLATE.md` sözleşmesini izleyin: frontmatter (name · description + Trigger phrases · en-az-yetki tools · model kademesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl/skill → Koordinasyon → DoD → Çıktı & bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Lisans & atıf

MIT — bkz. [LICENSE](LICENSE). Disiplin katmanı şu üst kaynaklara dayanır:

- **[DevArchitecture](https://github.com/DevArchitecture/DevArchitecture)** — backend kalıbı (MediatR CQRS / IResult / AOP). Yalnız kalıp referans alınır; burada DevArchitecture kaynak kodu barındırılmaz.
- **[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)** — disiplinin çekirdeğindeki dört çalışma ilkesi.
- **[google/eng-practices](https://github.com/google/eng-practices)** — `code-review` skill'i, damıtılıp yeniden ifade edildi. **CC-BY 3.0** lisanslı; atıf zorunludur.
