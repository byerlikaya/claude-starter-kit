<div align="center">

# 🛠️ Claude Starter Kit

**Claude Code için agentic çalışma kiti** — bir projeyi, hangi aşamada olursa olsun aynı mühendislik disipliniyle ilerleten, yeniden kullanılabilir bir iskelet.

*planla → üret → denetle → commit; her kritik kural bir hatırlatma değil, bir **kapı**.*

![Sürüm](https://img.shields.io/badge/s%C3%BCr%C3%BCm-1.1.12-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/lisans-MIT-16a34a?style=flat-square)
![Ajanlar](https://img.shields.io/badge/ajanlar-11-f59e0b?style=flat-square)
![Skiller](https://img.shields.io/badge/skiller-28-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

</div>

---

## Neden bu kit?

Çoğu "agent kurulumu" aslında bir öneri yığınıdır — kurallar bir dosyada durur, uyulup uyulmayacağı modele kalır. Bu kit farklı çalışır: Claude Code'un içine **disiplinli bir mühendislik ekibi** yerleştirir ve burada **önemli kurallar hatırlatma değil, kapıdır** — ajana kuralları söylemekle yetinmez, kritik olanları çiğnemeyi baştan imkânsız kılar; üstelik zaten elindeki repo'ya güvenle kurulur.

| | |
|---|---|
| 👥 | **Bir prompt değil, bir ekip** — 11 uzman ajan, planla → üret → denetle → gönder hattı boyunca kendiliğinden zincirlenir; onları sen bağlamazsın, ana thread halleder. |
| 🛡️ | **Güvenlik ve gizlilik bir seçenek değil, kapıdır** — risk taşıyan değişiklikler kapanmadan önce güvenlik/gizlilik denetiminden geçmek zorundadır. |
| 🚦 | **Her commit senin onayından geçer** — `commit`/`push`, sen açıkça onaylamadan çalışmaz; otomatik/bypass modda bile bu, araç seviyesinde zorunlu tutulur. |
| 🌿 | **Mevcut repo'da güvenli** — `adopt`, kiti ayrı bir dala devreder; `main`'e asla dokunulmaz, sen inceleyip onaylamadan hiçbir şey kalıcı olmaz. |

---

## 🧠 Ajanlar — kitin kalbi

**11 ajan** var; her biri bir **ince tetikleyici** — yalnızca *kim* ve *ne zaman* sorusunu yanıtlar, *nasıl* kısmını bir skill'e devreder. Ana thread onları **beş aşamada** seçip zincirler ve commit'ten önce kaliteyi kademe kademe yükseltir:

<div align="center">
  <img src="assets/orchestration-tr.svg" alt="Bes asamada ajan orkestrasyonu" width="740">

  🧭 **Anla** &nbsp;→&nbsp; 🔨 **Üret** &nbsp;→&nbsp; 🔍 **Denetle** &nbsp;→&nbsp; ✅ **Kapat** &nbsp;→&nbsp; 🤝 **Devret**

</div>

| Ajan | Aşama | Ne zaman devreye girer | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Anla | kapsam belirsiz olduğunda | `inherit` |
| **backend-expert-csk** | 🔨 Üret | sunucu / API / iş mantığı | `inherit` |
| **database-expert-csk** | 🔨 Üret | şema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Üret | UI, bileşen, istemci tarafı işi | `inherit` |
| **devops-expert-csk** | 🔨 Üret | dağıtım, CI hattı, olay müdahalesi | `inherit` |
| **security-expert-csk** | 🔍 Denetle | auth / IDOR / injection / secret · **güvenlik açısından kritikse zorunlu** | `sonnet` |
| **privacy-agent-csk** | 🔍 Denetle | kişisel veri (KVKK / GDPR) | `sonnet` |
| **test-expert-csk** | 🔍 Denetle | test, kapsam, regresyon | `inherit` |
| **review-agent-csk** | ✅ Kapat | commit öncesi kod sağlığı denetimi | `haiku` |
| **commit-agent-csk** | ✅ Kapat | commit'i önerir, onay bekler | `haiku` |
| **session-manager-csk** | 🤝 Devret | bağlam dolduğunda / faz sınırında | `haiku` |

> Ajan adları `-csk` ekiyle (Claude Starter Kit) biter; böylece kurulduğu projenin kendi ajanlarıyla asla çakışmaz. Her ajan incedir; asıl yöntem bir **skill**'de yaşar — tek bilgi kaynağı orasıdır.

---

## Üç ilke

1. **Ajan = ince tetikleyici.** Bir ajan yalnızca "kim, ne zaman" der; kısa kalır ve işin nasıl yapılacağını skill'e bırakır.
2. **Skill = tek bilgi kaynağı.** Asıl yöntem ve kural skill'de yaşar; ajana kopyalanmaz.
3. **Kural → kapı.** Önemli olan kural araç seviyesinde zorunlu kılınır (hook · permission · eval). Modelin bunu aklında tutması beklenmez.

---

## Kurulum ve çalıştırma

**İki giriş noktası var:** `start.sh` **sıfırdan** bir projeyi kurar; **`adopt`** (`adopt.sh`) ise kiti **mevcut** bir projeye devreder. Hangi kanalı seçersen seç, hepsi aynı iki komutu çalıştırır.

**npx** — kurulum gerektirmez:
```bash
npx @byerlikaya/claude-starter-kit          # sıfırdan proje
npx @byerlikaya/claude-starter-kit adopt    # mevcut proje
npx @byerlikaya/claude-starter-kit@latest update   # kit'in kurulu olduğu projeyi tazele
```

**Homebrew:**
```bash
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit          # sıfırdan proje
claude-starter-kit adopt    # mevcut proje
```

**Release tarball** — paket yöneticisi olmadan:
```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # sıfırdan proje
bash adopt.sh              # mevcut proje
```

> Sadece ajan ve skill'leri mevcut Claude Code'una eklemek mi istiyorsun (iskele kurmadan)? `/plugin marketplace add byerlikaya/claude-starter-kit` ardından `/plugin install claude-starter-kit@byerlikaya`.

> **Windows:** kit bash tabanlıdır — en sorunsuz deneyim için **Git Bash** ([git-scm.com](https://git-scm.com)) içinde çalıştır; WSL de yedek olarak çalışır.

### 🌱 Sıfırdan proje — `start.sh`

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic] [-h]
```

Bir kurulum sihirbazıdır. Bayrak vermezsen her adımı tek tek sorar (profil → backend yığını → özet ve onay); bayraklar sessiz/CI kullanımı içindir, `-h` / `--help` ise kullanım bilgisini basar. Her seçenek, ne kuracağını **kurmadan önce** gösterir.

> Kurulumdan sonra ilk Claude Code mesajın olarak **`.claude/FIRST_PROMPT.md`**'yi yapıştır — ajanları/skilleri doğrulayan ve ilk sprint'i planlayan opsiyonel bir başlatıcı. (`CLAUDE.md` her oturumda zaten yüklendiği için bu tek seferlik bir kolaylık, zorunluluk değil.)

| Profil | Uzman ajanlar | Öne çıkan skiller |
|---|---|---|
| `--backend` | backend · database | db-migration · api-design · observability |
| `--frontend` | frontend | frontend · a11y · i18n-integrity |
| `--mobile` | frontend (+ React Native/Expo katmanı) | frontend-rn-expo · a11y |
| `--fullstack` | hepsi | tüm skiller — backend **ve** web **ve** mobil (RN/Expo) |

Ayrı bir mobil ajanı yok: web'i de mobili de masaüstünü de `frontend-expert-csk` üstlenir, mobilin "nasıl"ı ise `frontend-rn-expo` skill'inde durur. `--fullstack` bu skill'i de kurar; yani `--mobile` seçmene gerek kalmadan fullstack bir proje mobile hazırdır.

Backend yığını yalnızca `--backend`/`--fullstack` için sorulur: **`--dotnet`**, .NET / DevArchitecture kalıbını (MediatR CQRS · IResult · AOP) bir onay kapısının ardından getirir; **`--generic`** ise aynı uzmanı onsuz kurar — Node, Go, Python ya da farklı bir kalıp kullanan bir .NET projesi için.

> **.NET'te sıfırdan değil, kanıtlanmışla başla.** `--dotnet`, üretime hazır **[DevArchitecture](https://github.com/DevArchitecture/DevArchitecture)** temelini (CQRS · IResult · AOP · auth) klonlar *ve* bu temeli zaten bilen ajanları kurar — böylece **bir ajanın standart bir mimariyi yeniden üretirken yakacağı token'ları boşa harcamazsın**; o token'lar boilerplate'e değil, senin iş mantığına gider. Varsayılan olarak opinionated, zorla değil: backend uzmanı projenin **kalıp skill'ini** uygular — kutudan DevArchitecture, ya da kendi kalıbın (Clean Architecture, Vertical Slice, Minimal API, düz katmanlı) `.claude/skills/`'e bırakılır. `--generic` yığından bağımsız kalır.

> **`--fullstack` + `--dotnet`** seçildiğinde DevArchitecture backend'i `./backend` altına konur, `./frontend` senin frontend'ine ayrılır ve çözüm dosyası projenin adıyla yeniden adlandırılır — böylece proje kökü, çıplak bir backend gibi görünmek yerine tertemiz kalır.

### 🔄 Mevcut projeye devir — `adopt.sh`

```bash
bash adopt.sh          # hedef projenin kökünde
```

Kiti, hâlihazırda ilerleyen bir projeye, tıpkı **bir ekibin projeyi başka bir ekibe devretmesi** gibi uygular — proje bozulmaz, verilmiş kararlar kaybolmaz, kit de kenarda pasif durmaz.

<div align="center">
  <img src="assets/handover-tr.svg" alt="adopt.sh devir akisi" width="900">
</div>

Tüm değişiklikler ayrı bir git dalına **staged olarak (commit'lenmeden)** düşer — yani eklenen ve değişen her dosya, editörünün Source Control / Changes panelinde görünür; oradan inceler, sonra `git commit` ile kabul edersin (ya da reset ile geri alırsın). `main` el değmeden kalır. Kit ajanları yan yana, hiç çakışmadan kurulur; disiplin tek bir `@import` ile bağlanır; `settings.json` şema farkındalığıyla birleştirilir; mevcut husky/lefthook zincirleri de bir shim üzerinden kitle birlikte çalışmaya devam eder. İşin sonunda kalıcı bir `docs/HANDOVER.md` ve bir ADR bırakır — böylece kararlar bir sohbette değil, versiyon kontrolünde yaşar.

### 🔁 Kurulu bir projeyi güncelleme

```bash
npx @byerlikaya/claude-starter-kit@latest update    # `update`, `adopt`'ın takma adıdır; projenin kökünde çalıştır
```

Kit, kurulum anında `.claude/kit.conf` dosyasına profili, backend yığınını ve hangi kurucunun çalıştığını damgalar; yanına da `.claude/VERSION` düşer. Güncelleyici bu damgayı okur ve projeyi **kurulduğu biçimde** tazeler: `--backend` bir projeye frontend ajanları geri yapıştırılmaz, `--dotnet` bir proje `devarch-module` kalıp skill'ini korur. Damga yoksa güncelleyici şekli kurulu dosyalardan çıkarsar ve yazar. Güncelleme var mı diye bakmak için `cat .claude/VERSION` çıktısını `npm view @byerlikaya/claude-starter-kit version` ile karşılaştır.

| | Güncellemede |
|---|---|
| `.claude/` ajanlar · skiller · komutlar · hook'lar · eval | yeni sürümden tazelenir |
| `.claude/DISCIPLINE.md` | **üzerine yazılır** — kite ait bir dosyadır, kendi kurallarını buraya koyma |
| `./CLAUDE.md` | hiç dokunulmaz — proje kuralların yazdığın gibi kalır |
| `.claude/settings.json` | şema farkındalığıyla birleştirilir; kendi hook ve izinlerin korunur |
| kendi ajan ve skill'lerin (`-csk` eki olmayanlar) | el değmeden kalır |

`adopt` gibi güncelleme de bir git deposu ister ve `kit-adopt-<zaman damgası>` dalına staged olarak düşer — diff'i incele, sonra commit'le ya da reset'le.

> Bir projenin `CLAUDE.md`'si disiplini import etmek yerine **içinde taşıyorsa**, disiplin güncellemeleri o projeye ulaşamaz. Güncelleyici bunu tespit eder, gömülü bloğun hangi satırlar olduğunu gösterir ve onu tek satırlık `@.claude/DISCIPLINE.md` import'uyla değiştirmeyi teklif eder — önce yedek alarak, incelediğin bir dalın üzerinde. Reddedersen hiçbir şeye dokunulmaz; her iki durumda da proje bölümün ve kendi kuralların yerinde kalır.

---

## İçinde ne var?

- **11 ajan** — yukarıdaki tabloya bak.
- **28 skill** — "nasıl" sorusunun tek kaynağı, her alan için bir tane (tüm katalog aşağıda).
- **5 slash komut** — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hook'lar** — `guard-bash.sh` (araç seviyesi kapı), `pre-commit` + `commit-msg` (iz + secret taraması), `context-usage.sh` ve `session-guard.sh` (oturum ölçümü).
- **CLAUDE.md** — davranış, üç ilke, iş akışı, tamamlanma tanımı (DoD), token disiplini ve yasaklar.

<details>
<summary><b>Tüm skill kataloğu</b> — 28 skill, her birinden üretilir</summary>

<!-- SKILLS:START -->

| Skill | What it does |
|:--|:--|
| `a11y` | Frontend accessibility audit (WCAG): semantic HTML, keyboard access, focus management, contrast, ARIA, screen readers. |
| `adr` | Architecture Decision Record: context-decision-consequences, for decisions that are expensive to reverse. |
| `api-design` | API contract design: resource naming, error model, versioning, pagination, backward compatibility, OpenAPI. |
| `ci-pipeline` | CI pipeline discipline: lint→build→test→quality→security, fail-fast, deterministic build, secret handling, PR gates. |
| `code-review` | Code review discipline: severity-ranked, reasoned feedback on whether a change improves the system's overall code health. |
| `commit-message` | Conventional Commits: reads the staged diff and proposes `type(scope): summary`, with body/footer when needed. |
| `db-migration` | Apply schema migrations safely: detect the tool, classify the change by risk, gate destructive ones behind approval, back up in prod,… |
| `dependency-audit` | Dependency audit: known CVEs, licence compliance, abandoned/outdated packages, lockfile integrity, and a justification for every new… |
| `devarch-module` | DevArchitecture backend pattern: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP chain, FluentValidation, i18n. |
| `docs-writer` | Keeps documentation in sync with the code: README, usage and related docs when a public API or behavior changes. |
| `frontend-rn-expo` | OPTIONAL, stack-specific: React Native + Expo (prebuild). |
| `frontend` | Stack-agnostic frontend discipline (web · mobile · desktop): component structure, state, data fetching, loading/empty/error states,… |
| `handoff` | Session handover: when context fills, a phase closes, or the topic changes, write an action-oriented handover to docs/SESSION_STATE.md,… |
| `i18n-integrity` | Translation integrity: every key present in every language, no hardcoded strings, consistent placeholders and plurals. |
| `incident-runbook` | Production incident response: diagnose → mitigate → resolve, then a blameless postmortem and a repeatable runbook. |
| `iterate` | Refine-to-Done loop: repeat until tests green + review clean + nothing deferred; bounded. |
| `observability` | Stack-agnostic observability: structured logs, correlation ids, metrics and traces; no PII or secrets in logs. |
| `performance` | Stack-agnostic performance: measure first, find the bottleneck, then optimise. |
| `privacy-compliance` | KVKK/GDPR audit method: data inventory, purpose/basis/retention, minimisation, consent, transparency, data-subject rights, cross-border… |
| `red-team` | Attacker's-eye test of LLM/agent defenses: instruction hijacking, data exfiltration and tool abuse through untrusted content; verifies… |
| `release` | Versioning and CHANGELOG: SemVer mapped from Conventional Commits, Keep a Changelog format, tagging, pre-release gates. |
| `security-scan` | Stack-agnostic security audit: map the attack surface, trace untrusted input to dangerous calls, surface dependency and configuration flaws. |
| `sonarqube-check` | SonarQube quality gate (language-agnostic): 0 Bugs · 0 Vulnerabilities · 0 Security Hotspots · 0 Code Smells, build 0 warnings / 0… |
| `spec-planning` | Spec-first planning: task breakdown, measurable acceptance criteria, dependency order, risk priority. |
| `testing` | The how of testing: pyramid, AAA, isolation, risk coverage, determinism. |
| `token-budget` | Context/token discipline: subagent isolation, output = summary, move-to-file, delegation threshold, lean skills. |
| `trace-scan` | Trace scan (§4.1/§4.2): before a commit, scans the staged changes and the message for AI traces (co-author trailers, footers, robot… |
| `vps-deploy` | Deploy to a VPS safely: runtime detection, reverse proxy + SSL, atomic swap, keep the previous version, post-deploy health gate,… |

<!-- SKILLS:END -->

</details>

---

## Oturum ve token yönetimi

Bir asistan `/context` komutunu kendisi çalıştıramaz; bu yüzden çoğu kurulum oturum doluluğunu **tahmin eder**. Bu kit ise ölçer. `context-usage.sh`, transcript'teki son turun API kullanımından gerçek token sayısını okur — `/context`'in gösterdiği değerin tam olarak aynısını. `UserPromptSubmit` hook'u bu değeri her tur enjekte eder; `Stop` hook'u (`session-guard.sh`) ise doluluk **%75'i ilk aştığında**, bir kez daha da **%90'da** seni uyarır — eşik başına tek uyarı, ve turunu asla bloklamaz. Oturum sağlığı satırı bir tahmine değil, bir ölçüme dayanır.

### Token maliyeti

`DISCIPLINE.md` ile ajan ve skill tarifleri her oturumun bağlamına yüklenir. Bu sabit yük gerçek bir turda **9.198 token** ölçülür — disiplin katmanının, 11 ajanın ve 28 skill'in tamamının bedeli.

`smoke-test.sh` bileşen başına byte bütçesi uygular (disiplin · ajan tarifleri · skill tarifleri); maliyet fark edilmeden yukarı kaymaz. Bütçe yükseltilebilir, ama `smoke-test.sh` içinde açıkça düzenlenerek.

> **Profil budaması token kazandırmaz.** `--backend` (10 ajan, 25 skill), `--fullstack`'ten (11 ajan, 28 skill) yalnızca ~640 token ucuz. Profili işin kapsamını daraltmak için seç.

---

## Kural → kapı

| Kural | Zorlayan mekanizma |
|---|---|
| Commit/push yalnızca onayla — her izin modunda | `guard-bash.sh` (PreToolUse), yalnız senin cevaplayabileceğin bir onay istemi çıkarır; bir kez onayla, commit'i Claude atar. `bypassPermissions`'ta kapalı tarafa düşer; `CLAUDE_GIT_OK=1` headless koşuları önceden yetkilendirir |
| Yıkıcı işlem (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (araç seviyesinde bloklanır) |
| Commit'te yapay zekâ izi ya da dış vendor adı bulunmaz | `pre-commit` + `commit-msg` git hook — senin proje dosyalarını tarar; kitin kendi `.claude/` ağacı muaftır (yapılandırdığı aracın adını taşır), sırlar asla muaf değildir |
| Commit'e API key / token / private key girmez | `pre-commit` secret taraması (`secret-blocklist.txt` + `.secret-allowlist.txt`) |
| Oturum eşiği | `context-usage.sh` + `session-guard.sh` (Stop hook) |
| Sabit bağlam yükü şişmesin | `smoke-test.sh` bileşen başına byte bütçesi (disiplin · ajan tarifleri · skill tarifleri) |
| Çalışan oturum bayat kurala uymasın | `context-usage.sh`, `.claude/VERSION`'ı oturumun başladığı sürümle karşılaştırır ve söyler |
| Kalite kapısı (SonarQube kullanan projeler — dilden bağımsız) | `sonarqube-check` + `/ship` |

Kapılar `settings.json` ve git `core.hooksPath` üzerinden devreye alınır; `smoke-test.sh` her değişiklikten sonra hazır olduklarını doğrular.

---

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek bir prompt doğru ajana/skill'e gidiyor mu
```

## İş akışı

`/plan` (belirsiz kapsam) → uzman ajanlar üretir → `/review` (güvenlik · kalite · test) → `/ship` (DoD kapısı; commit'i önerir, onay bekler) → bağlam dolduğunda `/handoff` → `/clear`.

## Genişletme

Yeni bir ajan ya da skill eklerken `AGENT_TEMPLATE.md` sözleşmesini izle: frontmatter (name · description + Trigger phrases · en az yetki ilkesiyle tools · model kademesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl/skill → Koordinasyon → DoD → Çıktı ve bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Lisans ve atıf

MIT — bkz. [LICENSE](LICENSE). Disiplin katmanı şu üst kaynakların üzerine kurulur:

- **[DevArchitecture](https://github.com/DevArchitecture/DevArchitecture)** — backend kalıbı (MediatR CQRS / IResult / AOP); yalnızca kalıp olarak referans alınır.
- **[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)** — disiplinin çekirdeğindeki dört çalışma ilkesi.
- **[google/eng-practices](https://github.com/google/eng-practices)** — `code-review` skill'i, damıtılıp yeniden ifade edildi (CC-BY 3.0).
