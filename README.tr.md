<div align="center">

<img src="assets/logo.svg" alt="Claude Starter Kit" width="460">

**Claude Code için agentic çalışma kiti** — bir projeyi, hangi aşamada olursa olsun aynı mühendislik disipliniyle ilerleten, yeniden kullanılabilir bir iskelet.

*planla → üret → denetle → commit; her kritik kural bir hatırlatma değil, bir **kapı**.*

![Sürüm](https://img.shields.io/badge/s%C3%BCr%C3%BCm-1.10.1-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/lisans-MIT-16a34a?style=flat-square)
![Ajanlar](https://img.shields.io/badge/ajanlar-12-f59e0b?style=flat-square)
![Skiller](https://img.shields.io/badge/skiller-38-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

</div>

---

## Neden bu kit?

Çoğu "agent kurulumu" aslında bir öneri yığınıdır — kurallar bir dosyada durur, uyulup uyulmayacağı modele kalır. Bu kit farklı çalışır: Claude Code'un içine **disiplinli bir mühendislik ekibi** yerleştirir ve burada **önemli kurallar hatırlatma değil, kapıdır** — ajana kuralları söylemekle yetinmez, kritik olanları komut çalışmadan **önce** cevap veren bir araç-seviyesi kapının arkasına koyar; üstelik zaten elindeki repo'ya güvenle kurulur.

| Önemli olan | Tipik agent kiti / prompt koleksiyonu | Claude Starter Kit |
|---|---|---|
| **Kritik kurallar** | Bir `.md` dosyasında durur; yalnız model hatırlarsa uygulanır | **Kapı olarak zorlanır** — araç seviyesinde: git hook (`trace-scan`), `settings.json` izinleri, `guard-bash.sh` PreToolUse. Kapı komut çalışmadan önce cevap verir; kural modelin hatırlamasına bağlı değildir |
| **Yapı** | Tek bir dev prompt ya da senin yönettiğin gevşek bir agent listesi | **12 uzman agent'lık bir ekip**, 5 aşamada (Anla → Üret → Denetle → Kapat → Devret) ve **düz promptta gerçekten çalışıyorlar** — `UserPromptSubmit` hook'u isteğinin yanına sahibini yazıyor; dört turda **39/48** ölçüldü, hooksuz taban **0/24**. Fazladan bir şey yazmıyorsun; sabit bir sıra istediğinde komutlar (`/review-csk`) birden çok ajanı @-mention ile zincirler |
| **Güvenlik & gizlilik** | İsteğe bağlı tavsiye, atlaması kolay | **Zorunlu audit kapısı** — risk-kritik değişiklik, güvenlik/gizlilik denetimi geçmeden kapanamaz |
| **Commit'ler** | Model kendi başına commit atabilir | **Her commit senin onayına bağlı** — auto/bypass modda bile araç seviyesinde zorlanır |
| **Mevcut repoya uyarlama** | "Sıfırdan başla" varsayımı; elle taşıma | **`adopt` kiti bir branch'te devreder** — `main`'e dokunulmaz; sen inceleyip tutmaya karar verirsin |
| **"Nasıl" bilgisi nerede** | Kural + yöntem her agent prompt'una kopyalanır → çoğalma & tutarsızlık | **Agent = ince tetik** (kim/ne zaman); yöntem tek yerde, bir **skill**'te yaşar (tek doğruluk kaynağı), 38 skill'e yayılır |

---

## 🚀 Hızlı başlangıç

```bash
npx @byerlikaya/claude-starter-kit          # sıfırdan proje — kurulum sihirbazı
npx @byerlikaya/claude-starter-kit adopt    # mevcut proje — bir dalda güvenli devir
```

Ardından ilk Claude Code mesajın olarak **`.claude/FIRST_PROMPT.md`**'i yapıştır. Homebrew, release tarball ve plugin edisyonu aşağıdaki **Kurulum ve çalıştırma** bölümünde.

---

## 🧠 Ajanlar — kitin kalbi

**12 ajan** var; her biri bir **ince tetikleyici** — yalnızca *kim* ve *ne zaman* sorusunu yanıtlar, *nasıl* kısmını bir skill'e devreder. **Beş aşamaya** ayrılmışlardır; böylece commit'ten önce kalite kademe kademe yükselir:

<div align="center">

  🧭 **Anla** &nbsp;→&nbsp; 🔨 **Üret** &nbsp;→&nbsp; 🔍 **Denetle** &nbsp;→&nbsp; ✅ **Kapat** &nbsp;→&nbsp; 🤝 **Devret**

</div>

<details>
<summary><b>12 ajan ve her birinin ne zaman devreye girdiği</b></summary>

| Ajan | Aşama | Ne zaman devreye girer | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Anla | kapsam belirsiz olduğunda | `inherit` |
| **backend-expert-csk** | 🔨 Üret | sunucu / API / iş mantığı | `inherit` |
| **database-expert-csk** | 🔨 Üret | şema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Üret | UI, bileşen, istemci tarafı işi | `inherit` |
| **devops-expert-csk** | 🔨 Üret | dağıtım, CI hattı, olay müdahalesi | `inherit` |
| **security-expert-csk** | 🔍 Denetle | auth / IDOR / injection / secret · **güvenlik açısından kritikse zorunlu** | `inherit` · `effort: high` |
| **privacy-agent-csk** | 🔍 Denetle | kişisel veri (KVKK / GDPR) | `inherit` |
| **test-expert-csk** | 🔍 Denetle | test, kapsam, regresyon | `inherit` |
| **performance-expert-csk** | 🔍 Denetle | sıcak yol, sorgu/döngü, render, payload · ölçülmüş bulgu üretir | `inherit` |
| **review-agent-csk** | ✅ Kapat | commit öncesi kod sağlığı denetimi | `inherit` |
| **commit-agent-csk** | ✅ Kapat | commit'i önerir, onay bekler | `haiku` |
| **session-manager-csk** | 🤝 Devret | bağlam dolduğunda / faz sınırında | `inherit` |

</details>

> **Neden neredeyse her ajanda `inherit` yazıyor.** `model:` yazılmaması ya da `inherit` demek, alt-ajanın
> oturum için senin seçtiğin modelde koşması demek — ve bu bilinçli: bir pin, ajanı yalnızca etrafındaki işten
> *farklı* bir kademeye taşıyabilir. İki zorunlu denetim tam bu yüzden miras alıyor: bir değişikliği onaylayan
> inceleme, onu yazandan zayıf olmamalı. `security-expert-csk` ek titizliği farklı bir modelden değil,
> `effort: high` ile **senin** modelinde daha çok düşünerek alıyor. `commit-agent-csk`'de `haiku` kalıyor;
> staged diff'ten Conventional Commit üretmek mekanik bir iş ve §4.1/§4.4 zaten kapılı. `smoke-test.sh` iki
> yarıyı da zorluyor: `model:`/`effort:` değeri dokümanın tanımladığı kümeden olmalı, ve denetim ajanları
> pin'siz kalmalı.

> Her ajan, skill ve komut `-csk` ekiyle (Claude Starter Kit) biter; böylece hiçbiri kurulduğu projenin kendi bileşenleriyle çakışmaz ve yerleşik bir Claude Code komutunu gölgelemez. Her ajan incedir; asıl yöntem bir **skill**'de yaşar — tek bilgi kaynağı orasıdır.

> **Ajan devreye girmiyorsa garantiye alabilirsin.** Claude delegasyona göreve, ajanın `description` alanına ve
> mevcut bağlama bakarak karar verir — bu bir kural değil, bir yargıdır; bazen işi ana thread'de tutar. İki
> yükseltme yolu ([subagents dokümanı](https://code.claude.com/docs/en/sub-agents)): istekte ajanın adını yaz
> ("bunu frontend-expert-csk yapsın") ya da **`@agent-frontend-expert-csk`** — bu, o ajanın o görev için
> çalışmasını **garanti eder**. Hiçbir yerde delegasyon olmuyorsa `Agent` aracının `permissions.deny` içinde
> olmadığını kontrol et; `/doctor-csk` bunu raporlar.

---

## İçinde ne var?

<div align="center">
  <img src="assets/network-tr.svg" alt="Kitin ağı — 12 ajan ve 38 skill, her çizgi gerçek bir applies ilişkisi" width="820">
  <br><sub>Her ajan, her skill ve gerçek <code>applies</code> bağları — aşamaya göre gruplu, her ajan kendi renginde; merkez, hepsini orkestralayan ana thread.</sub>
</div>

- **12 ajan** — yukarıdaki tabloya bak.
- **38 skill** — "nasıl" sorusunun tek kaynağı, her alan için bir tane (tüm katalog aşağıda).
- **7 slash komut** — `/brainstorm-csk` · `/plan-csk` · `/review-csk` · `/ship-csk` · `/handoff-csk` · `/update-csk` (kurulu kiti güncelle) · `/doctor-csk` (kurulumu sağlık-kontrolü). Sadeleştirme için yerleşik `/simplify` kullanılır.
- **Hook'lar** — `route-hint.sh` (her isteğin yanına sahibi ajanı yazar; uzmanlar sen istemeden devreye girer), `guard-bash.sh` + `guard-write.sh` (araç seviyesi komut/yazma kapıları), `pre-commit` + `commit-msg` (iz + secret + bloat taraması), `context-usage.sh` ve `session-guard.sh` (oturum ölçümü), `session-rehydrate.sh` (/compact ya da /clear sonrası devir-notunu yeniden yüzeye çıkarır), `session-stats.sh` (oturumun gerçekte ne yaptığı — başarısız tool döngüleri, tekrarlanan promptlar, kesintiler, compaction'lar; `reflect` ve `handoff` bunu okur, böylece retro hatıraya değil kayda dayanır), `skill-trust.sh` (kitin göndermediği ve senin kabul etmediğin skill/agent'ı adlandırır), `guard-commit-scan.sh` (gerçek iz/sır tarayıcılarını `PreToolUse`'dan koşturur; böylece commit içerik kapısı `core.hooksPath` kurulamayan yerlerde de çalışır). Plugin edisyonu bu kapı hook'larını da taşır.
- **CLAUDE.md** — davranış, üç ilke, iş akışı, tamamlanma tanımı (DoD), token disiplini ve yasaklar.

<details>
<summary><b>Tüm skill kataloğu</b> — 38 skill, her birinden üretilir</summary>

<!-- SKILLS:START -->

| Beceri | Ne yapar |
|:--|:--|
| `a11y` | Frontend erişilebilirlik denetimi (WCAG): anlamsal HTML, klavye erişimi, odak yönetimi, kontrast, ARIA, ekran okuyucular. |
| `adr` | Mimari Karar Kaydı: bağlam-karar-sonuç; geri dönüşü pahalı kararlar için. |
| `api-design` | API sözleşme tasarımı: kaynak adlandırma, hata modeli, sürümleme, sayfalama, geriye dönük uyumluluk, OpenAPI. |
| `brainstorm` | Planlamadan ÖNCE ıraksak keşif: bulanık isteği 2–4 kapsamlı seçenek + adlandırılmış bilinmezlere çevir, bir yön seç, spec-planning'e devret. |
| `ci-pipeline` | CI hattı disiplini: lint→build→test→kalite→güvenlik, hızlı-başarısızlık, deterministik derleme, secret yönetimi, PR kapıları. |
| `code-review-csk` | Kod inceleme disiplini: önem sırasına dizili, gerekçeli geri bildirim — değişiklik sistemin genel kod sağlığını iyileştiriyor mu. |
| `commit-message` | Conventional Commits: staged diff'i okur, `type(scope): özet` önerir; gerektiğinde gövde/footer ekler. |
| `confidence-check` | Uygulamaya BAŞLAMADAN önce hazırlık kapısı: bu iş zaten var mı, mimariye uyuyor mu, dış API iddiası doğrulandı mı, çalışan bir referans var mı, kök neden biliniyor mu. Herhangi bir "hayır" durdurur. |
| `db-migration` | Şema göçlerini güvenle uygula: aracı sapta, değişikliği riske göre sınıfla, yıkıcı olanları onaya bağla, prod'da yedekle, önizle-uygula-doğrula, hatada geri al. |
| `dependency-audit` | Bağımlılık denetimi: bilinen CVE'ler, lisans uyumu, terk edilmiş/eski paketler, lockfile bütünlüğü ve her yeni bağımlılık için gerekçe. |
| `dependency-upgrade` | Bağımlılıkları build'i kırmadan güncele taşı: neyin açığı var, neyi deprecated, neyi geride belirle; her hedef sürümü riske göre sınıfla (patch/minor/major), güvenli olanı uygula, doğrula, kırmızıda geri al. |
| `devarch-module` | DevArchitecture backend deseni: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP zinciri, FluentValidation, i18n. |
| `docs-writer` | Dokümantasyonu kodla eşzamanlı tutar: public API veya davranış değişince README, kullanım ve ilgili dokümanlar. |
| `eval-grader` | Çıktı kalitesini ölç, sezgiye bırakma: bir üretken görevi iki katmanlı grader ile puanla — ucuz deterministik kod metrikleri + boyut-boyut LLM-yargıç — sabit görev kümesine karşı, sabitlenmiş baz çizgisine göre işaretli deltalarla. Doğruluğun yanında maliyeti de puanlar (pass-slow). |
| `frontend-design` | Arayüzler için görsel ve UX tasarım kalitesi: hiyerarşi, boşluk ritmi, tipografik ölçek, ölçülü renk sistemi, düzen ve cilalı durumlar. Mimari ve a11y üstündeki zevk katmanı. |
| `frontend-rn-expo` | OPSİYONEL, yığına özel: React Native + Expo (prebuild). |
| `frontend` | Yığından bağımsız frontend disiplini (web · mobil · masaüstü): bileşen yapısı, state, veri çekme, loading/empty/error durumları, i18n, erişilebilirlik, performans. |
| `handoff` | Oturum devri: bağlam dolunca, bir faz kapanınca veya konu değişince docs/SESSION_STATE.md'ye eyleme dönük devir yaz, sonra /clear öner. |
| `i18n-integrity` | Çeviri bütünlüğü: her anahtar her dilde mevcut, hardcoded metin yok, tutarlı yer tutucular ve çoğullar. |
| `incident-runbook` | Prod olay müdahalesi: teşhis → hafiflet → çöz, ardından suçlamasız postmortem ve tekrarlanabilir runbook. |
| `iterate` | Bitene-kadar-iyileştir döngüsü: testler yeşil + inceleme temiz + ertelenen yok olana dek tekrarla; sınırlı. |
| `mcp-builder` | Model Context Protocol (MCP) sunucusu kur: araç şemaları tasarla, taşıma seç, hataları yönet ve test et. Bir API/veritabanı/servisi Claude ve diğer istemcilere aç. |
| `observability` | Yığından bağımsız gözlemlenebilirlik: yapılandırılmış loglar, korelasyon id'leri, metrikler ve trace'ler; loglarda PII/secret yok. |
| `performance` | Yığından bağımsız performans: önce ölç, darboğazı bul, sonra optimize et. |
| `privacy-compliance` | KVKK/GDPR denetim yöntemi: veri envanteri, amaç/dayanak/saklama, minimizasyon, açık rıza, şeffaflık, ilgili kişi hakları, sınır ötesi aktarım. |
| `red-team` | LLM/ajan savunmalarına saldırgan gözüyle test: talimat ele geçirme, veri sızdırma ve güvenilmez içerikle araç istismarı; savunmanın gerçekten tutup tutmadığını doğrular. |
| `reflect` | Önemli işten sonra retrospektif öz-denetim: doğrulanmamış varsayımlar, atlanan maddeler, doğru-yaklaşım-mı — kod değil, bulgular. |
| `release` | Sürümleme ve CHANGELOG: Conventional Commits'ten türetilen SemVer, Keep a Changelog biçimi, etiketleme, ön-sürüm kapıları. |
| `security-scan` | Yığından bağımsız güvenlik denetimi: saldırı yüzeyini haritala, güvenilmez girdiyi tehlikeli çağrılara kadar izle, bağımlılık ve yapılandırma açıklarını çıkar. |
| `sonarqube-check` | SonarQube kalite kapısı (dilden bağımsız, yerel-öncelikli): 0 Bug/Zafiyet/Hotspot/Code Smell, 0 derleme uyarısı. Analyzer yoksa dile göre yerel/sunucusuz kurulup çalıştırılır. |
| `spec-planning` | Spec-öncelikli planlama: görev ayrıştırma, ölçülebilir kabul kriterleri, bağımlılık sırası, risk önceliği. |
| `systematic-debugging` | Bir hatayı düzeltmeden önce kök nedeni bul: yeniden üret, izole et, hipotez kurup test et, nedeni doğrula, sonra düzelt ve doğrula. Tahmine dayalı yamayı durdurur. |
| `testing` | Testin nasıl'ı: piramit, AAA, izolasyon, risk kapsamı, determinizm. |
| `threat-model` | Güvenlik denetimini taramadan ÖNCE kapsamla (false-positive kesici): varlıklar, giriş noktaları, güven sınırları ve 5-8 alana özgü saldırı sınıfını parse edilebilir THREAT_MODEL.md'ye çıkar. Tehdit patch'i aşar; zafiyet yalnızca kanıttır. security-scan'i besler. |
| `token-budget` | Bağlam/token disiplini: subagent izolasyonu, çıktı = özet, dosyaya-taşı, delege eşiği, yalın skill'ler. |
| `trace-scan` | İz taraması (§4.1/§4.2): commit'ten önce staged değişiklikleri ve mesajı AI izlerine (co-author trailer, footer, robot emoji, araç adları) ve vendor şablon adlarına karşı tarar. |
| `vps-deploy` | Bir VPS'e güvenli dağıtım: runtime saptama, ters proxy + SSL, atomik geçiş, önceki sürümü koru, dağıtım sonrası sağlık kapısı, hatada otomatik geri alma. |
| `worktree` | Riskli ya da paralel dosya-değiştiren işi bir git worktree'de izole et; ana ağacın commit'lenmemiş değişiklikleri asla ezilmez. Fan-out ajanlar, tek-kullanımlık deneyler için. |

<!-- SKILLS:END -->

</details>

---

## Üç ilke

1. **Ajan = ince tetikleyici.** Bir ajan yalnızca "kim, ne zaman" der; kısa kalır ve işin nasıl yapılacağını skill'e bırakır.
2. **Skill = tek bilgi kaynağı.** Asıl yöntem ve kural skill'de yaşar; ajana kopyalanmaz.
3. **Kural → kapı.** Önemli olan kural araç seviyesinde zorunlu kılınır (hook · permission · eval). Modelin bunu aklında tutması beklenmez.

---

## Oturum ve token yönetimi

Bir asistan `/context` komutunu kendisi çalıştıramaz; bu yüzden çoğu kurulum oturum doluluğunu **tahmin eder**. Bu kit ise ölçer. `context-usage.sh`, transcript'teki son turun API kullanımından gerçek token sayısını okur — `/context`'in gösterdiği değerin tam olarak aynısını. `UserPromptSubmit` hook'u bu değeri her tur enjekte eder; `Stop` hook'u (`session-guard.sh`) ise doluluk **%75'i ilk aştığında**, bir kez daha da **%90'da** seni uyarır — eşik başına tek uyarı, ve turunu asla bloklamaz. Oturum sağlığı satırı bir tahmine değil, bir ölçüme dayanır.

### Token maliyeti

`DISCIPLINE.md` ile ajan ve skill tarifleri her oturumun bağlamına yüklenir. Bu sabit yük bugün **~24 KB** (`DISCIPLINE.md` + 12 ajan + 38 skill tarifi) — gerçek bir turda **~10 bin token** mertebesinde; tahmin değil, gerçek bir `claude -p` turuyla kalibre edildi. Eklenen her skill tüm oturumlara kalıcı ~100 token vergisidir; bu yüzden aşağıdaki bayt bütçesi bir kılavuz değil, kapıdır.

`smoke-test.sh` bileşen başına byte bütçesi uygular (disiplin · ajan tarifleri · skill tarifleri); maliyet fark edilmeden yukarı kaymaz. Bütçe yükseltilebilir, ama `smoke-test.sh` içinde açıkça düzenlenerek.

> **Profil budaması token kazandırmaz.** `--backend` (11 ajan, 34 skill), `--fullstack`'ten (12 ajan, 38 skill) yalnızca birkaç yüz token ucuz. Profili işin kapsamını daraltmak için seç.

---

## Kural → kapı

| Kural | Zorlayan mekanizma |
|---|---|
| Commit/push yalnızca onayla — her izin modunda | `guard-bash.sh` (PreToolUse), yalnız senin cevaplayabileceğin bir onay istemi çıkarır; bir kez onayla, commit'i Claude atar. `bypassPermissions`'ta kapalı tarafa düşer; `CLAUDE_GIT_OK=1` headless koşuları önceden yetkilendirir |
| Yıkıcı işlem (`reset --hard` · `checkout -- .` / `restore .` · force push · `rm -rf` · `clean -f` · `--no-verify` · rebase · amend) | `guard-bash.sh` (araç seviyesinde bloklanır). Ağaç-geneli geri alma listede, çünkü commit'lenmemiş her değişikliği reflog bırakmadan siler — `reset --hard` ile aynı kayıp, ama rutin bir temizlik gibi okunan bir komutla |
| Uzaktan-kod-çalıştırma / izin-yıkımı (`curl…\|bash` · dünyaya-yazılabilir `chmod` · `dd of=`) | `guard-bash.sh` (her modda sert blok). `chmod` kuralı bir yazımı değil ortaya çıkan **izni** eşler — `777`, `1777`, `666`, `o+w` ve `a+w` aynı yere varır; birini bloklayıp diğerinin aynı duruma ulaşmasına izin veren bir kapı hiçbir şeyi korumamıştır |
| Kapıları sökme (`core.hooksPath` yönlendirme ya da bir hook script'ini düzenleme/silme) | `guard-bash.sh` (shell tarafı) + `guard-write.sh` (Write/Edit tarafı) — sökülebilen kapı, kapı değildir |
| Doğrudan varsayılan branch'e commit | `guard-bash.sh` bunu onay istemine yazar (blok değil, uyarı — sıfırdan proje meşru olarak `main`'de yaşar) |
| Build/vendored çıktı ya da aşırı büyük dosya stage'lenmiş | `pre-commit` repo-şişme taraması (`node_modules/`, `dist/`, `>5 MiB`, …; `CSK_MAX_FILE_BYTES` ile ayarlanır) |
| Sır **dosyası** stage'lenmiş (içerik taramasının kaçırabileceği tüm-dosya sırrı) | `pre-commit` sır-dosyası kapısı (`.env`, `id_rsa`, `*.pem/.key/.p12`, `.npmrc`, …; `.env.example`/`.sample`/`.template` commit'lenebilir kalır) |
| `.gitignore`'u atlayan zorla-ekleme (`git add -f`) · lockfile silme | `guard-bash.sh` (araç seviyesinde bloklanır) |
| Commit'te yapay zekâ izi ya da dış vendor adı bulunmaz | `pre-commit` + `commit-msg` git hook — senin proje dosyalarını tarar; kitin kendi `.claude/` ağacı muaftır (yapılandırdığı aracın adını taşır), sırlar asla muaf değildir |
| Commit'e API key / token / private key girmez | `pre-commit` secret taraması (`secret-blocklist.txt` + `.secret-allowlist.txt`); bu listelerdeki her desen kendi test vakasını taşır ve `smoke-test.sh` onları gerçek hook'tan geçirir |
| Bağlama kimlik dosyası **okunmaz** (`~/.ssh/id_rsa`, `~/.aws/credentials`, `*.pem`, `.netrc`, kubeconfig) | `settings.json` Read-deny + kabuk tarafı için `guard-bash.sh`. Commit taraması sırrı *çıkarken* yakalar; yalnızca okunan sırrı hiçbir şey yakalamaz, ve okunmuş bir sır tek bir özetle makineden çıkabilir. Açık anahtarlar ve `.example` yolları okunabilir kalır |
| `.claude/` içine kimsenin incelemediği skill/agent düşmez | `skill-trust.sh` (SessionStart) onu tedarik-zinciri tarayıcısının hükmüyle birlikte adlandırır; kabul bilinçlidir ve özet (digest) olarak kaydedilir, kabulden sonraki bir düzenleme yeniden bildirilir |
| Oturum eşiği | `context-usage.sh` + `session-guard.sh` (Stop hook) |
| Sabit bağlam yükü şişmesin | `smoke-test.sh` bileşen başına byte bütçesi (disiplin · ajan tarifleri · skill tarifleri) |
| Çalışan oturum bayat kurala uymasın | `context-usage.sh`, `.claude/VERSION`'ı oturumun başladığı sürümle karşılaştırır ve söyler |
| Kalite kapısı (SonarQube kullanan projeler — dilden bağımsız) | `sonarqube-check` + `/ship-csk` |

Kapılar `settings.json` ve git `core.hooksPath` üzerinden devreye alınır; `smoke-test.sh` her değişiklikten sonra hazır olduklarını doğrular — ve her kural **iki** yarısıyla vakalanır: bloklaması gerekeni blokluyor mu, ve komşularını rahat bırakıyor mu (`chmod 755`, `rm -rf build`, `git checkout -- src/app.js`). Kanıtlanmamış bir kapı kapı değildir; rutin işte ateşleyen bir kapının ise etrafından dolanılır.

> **Dürüst kapsam.** Bunlar derinlemesine savunmadır, bir kum havuzu değil — guard script'inin kendi kullandığı
> ifade bu. Shell Turing-tamdır; kararlı bir yeniden yazım her deseni dolanabilir. Kapıların kaldırdığı şey
> **kazadır**: teslim tarihi baskısıyla uzanılan kaba alet, rutin temizlik gibi okunan yıkıcı komut. Sert bir
> sınır istiyorsan Claude Code'u devcontainer ya da VM içinde çalıştır — `/doctor-csk` böyle bir şeyin olup
> olmadığını raporluyor.

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
brew upgrade byerlikaya/tap/claude-starter-kit && claude-starter-kit update   # kit'in kurulu olduğu projeyi tazele
```

**Release tarball** — paket yöneticisi olmadan:
```bash
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # sıfırdan proje
bash adopt.sh               # mevcut proje — kurulu bir projeyi tazelemek için tekrar çalıştır (update)
```

> Sadece ajan ve skill'leri mevcut Claude Code'una eklemek mi istiyorsun (iskele kurmadan)? `/plugin marketplace add byerlikaya/claude-starter-kit` ardından `/plugin install claude-starter-kit@byerlikaya`.
>
> **Plugin güncellemesi otomatik değil.** Kurulu bir plugin, sen yenisini istemedikçe kurduğun sürümde kalır;
> yani bir kapı düzeltmesi kendiliğinden sana ulaşmaz. İki adım, ikincisi yeniden başlatma gerektirir:
>
> ```bash
> claude plugin marketplace update byerlikaya   # kataloğu GitHub'dan yenile
> claude plugin update claude-starter-kit       # sonra yeni sürümü kur (uygulamak için yeniden başlat)
> ```
>
> Hangi sürümde olduğunu `claude plugin list` gösterir. Diğer üç kanalın kendi yolu var — `npm i -g
> @byerlikaya/claude-starter-kit`, `brew upgrade claude-starter-kit`, ya da iskeleli bir projede `/update-csk`.

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

Projenin kökünde çalıştır — her kanalda aynı iş; `update`, `adopt`'ın takma adıdır.

```bash
npx @byerlikaya/claude-starter-kit@latest update                              # npx
brew upgrade byerlikaya/tap/claude-starter-kit && claude-starter-kit update   # Homebrew
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz && bash adopt.sh   # tarball
```

<details>
<summary><b>Güncelleme mekaniği</b> — ne tazelenir, kit.conf, değişiklik nereye iner</summary>

Kit, kurulum anında `.claude/kit.conf` dosyasına profili, backend yığınını ve hangi kurucunun çalıştığını damgalar; yanına da `.claude/VERSION` düşer. Güncelleyici bu damgayı okur ve projeyi **kurulduğu biçimde** tazeler: `--backend` bir projeye frontend ajanları geri yapıştırılmaz, `--dotnet` bir proje `devarch-module` kalıp skill'ini korur. Damga yoksa güncelleyici şekli kurulu dosyalardan çıkarsar ve yazar. Güncelleme var mı diye bakmak için `cat .claude/VERSION` çıktısını `npm view @byerlikaya/claude-starter-kit version` ile karşılaştır.

Çalışan bir Claude Code oturumunun içinde **`/update-csk`** de çalıştırabilirsin — sürüm kontrolünü yapar, yeni sürüm varsa güncelleyiciyi koşar, sonucu `/doctor-csk` ile doğrular ve tazelenmiş disiplini aynı oturumda yeniden yüklemen için `/compact` önerir. Canlı bir kurulumun sağlığını dilediğin an **`/doctor-csk`** ile bak (hook'lar çalıştırılabilir mi · `core.hooksPath` kurulu mu · kapılar bağlı mı · `CLAUDE.md` disiplini gerçekten import ediyor mu). Ayrıca projenin kendisi için tavsiye niteliğinde bir **hazırlık** skoru basar: proje bölümü doldurulmuş mu, kitin geneline ek bir proje skill'i var mı, ajan komutlarını kumlayacak bir devcontainer ve bir MCP sunucusu var mı, `CLAUDE.md` kodun gerisinde kalmış mı.

| | Güncellemede |
|---|---|
| `.claude/` ajanlar · skiller · komutlar · hook'lar · eval | yeni sürümden tazelenir |
| `.claude/DISCIPLINE.md` | **üzerine yazılır** — kite ait bir dosyadır, kendi kurallarını buraya koyma |
| `./CLAUDE.md` | hiç dokunulmaz — proje kuralların yazdığın gibi kalır |
| `.claude/settings.json` | şema farkındalığıyla birleştirilir; kendi hook ve izinlerin korunur |
| kendi ajan ve skill'lerin (`-csk` eki olmayanlar) | el değmeden kalır |

`adopt` gibi güncelleme de bir git deposu ister. Değişikliğin nereye ineceği artık bir seçim: ilk devir `kit-adopt-<zaman damgası>` inceleme dalı açar (ana hattın temiz kalır); `.claude/` gitignore'lu rutin bir güncelleme **mevcut** dalına uygulanır (ayrı dal boş olurdu); `.claude/` **izlenen** bir güncelleme sorar. Nereye ineceğini `--here` ya da `--new-branch` ile zorla; oturum-içi `/update-csk` ve CI'nin yaptığı gibi `--yes` ile de sormadan koştur. Her hâlükârda değişiklik staged ve commit'siz — diff'i incele, sonra commit'le ya da reset'le.

> Bir projenin `CLAUDE.md`'si disiplini import etmek yerine **içinde taşıyorsa**, disiplin güncellemeleri o projeye ulaşamaz. Güncelleyici bunu tespit eder, gömülü bloğun hangi satırlar olduğunu gösterir ve onu tek satırlık `@.claude/DISCIPLINE.md` import'uyla değiştirmeyi teklif eder — önce yedek alarak, incelediğin bir dalın üzerinde. Reddedersen hiçbir şeye dokunulmaz; her iki durumda da proje bölümün ve kendi kuralların yerinde kalır.

</details>

---

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek bir prompt doğru ajana/skill'e gidiyor mu
```

**Kapıların ateşlendiğini görmek.** `CSK_GATE_LOG=<yol>` verirsen guard hook'ları her karar için bir satır
yazar — `BLOCK`/`ASK`/`ALLOW`, kural ve kapıyı tetikleyen komut. Sen ayarlamadıkça yoktur, yalnız yazar ve
kararı verdikten SONRA kaydeder; yani kararı etkileyemez. Bir kapının gerçekten bir şeyi durdurup durdurmadığını
merak ettiğinde işe yarar: "kapı durdurdu" ile "model oraya hiç gitmedi" geriye birebir aynı izi bırakır.

## İş akışı

`/plan-csk` (belirsiz kapsam) → uzman ajanlar üretir → `/review-csk` (güvenlik · kalite · test) → `/ship-csk` (DoD kapısı; commit'i önerir, onay bekler) → bağlam dolduğunda `/handoff-csk` → `/clear`.

## Genişletme

Yeni bir ajan ya da skill eklerken `AGENT_TEMPLATE.md` sözleşmesini izle: frontmatter (name · description + Trigger phrases · en az yetki ilkesiyle tools · model kademesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl/skill → Koordinasyon → DoD → Çıktı ve bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Lisans ve atıf

MIT — bkz. [LICENSE](LICENSE).

- **[google/eng-practices](https://github.com/google/eng-practices)** — `code-review-csk` skill'i, damıtılıp yeniden ifade edildi (CC-BY 3.0).
