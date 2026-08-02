<div align="center">

<img src="assets/logo.svg" alt="Claude Starter Kit" width="460">

**Claude Code için eksiksiz bir mühendislik düzeni.**

12 uzman agent, 38 skill ve bir `CLAUDE.md`'nin yalnızca rica edebildiği kuralları *zorunlu kılan* araç seviyesinde kapılar.

![Sürüm](https://img.shields.io/badge/version-1.10.1-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)
![Ajanlar](https://img.shields.io/badge/agents-12-f59e0b?style=flat-square)
![Skiller](https://img.shields.io/badge/skills-38-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

</div>

---

## Sorun

`CLAUDE.md` bir ricadır. İşin nasıl yapılmasını istediğinizi yazarsınız, model okur ve aklında tuttuğu sürece uyar. Denetleyen bir şey yoktur. Dosya uzadıkça uyum zayıflar, üstelik bunu size kimse söylemez: ya inceleme sırasında fark edersiniz, ya commit'ten sonra.

Eksik olan bilgi değil, yaptırım.

## Claude Starter Kit ne yapıyor

Önemli kuralları dosyadan alıp araçların içine koyuyor, çevresine de bir ekip kuruyor.

**Kurallar kapıya dönüşüyor.** Yıkıcı bir komutu, kabuk görmeden önce bir `PreToolUse` hook'u reddediyor. Commit, `bypassPermissions` modunda bile onayınız için duruyor. Sızmış bir API anahtarını ya da yapay zekâ imzasını bir git hook'u yakalıyor. Hiçbiri modelin hatırlamasına bırakılmıyor.

**İşi uzmanlar yapıyor.** 12 agent'ın her biri tek bir alanın sahibi ve beş aşamada çalışıyorlar: planla, üret, denetle, kapat, devret. Riskli bir değişiklik, güvenlik incelemesi temize çıkmadan kapanamıyor. Her agent ince kalıyor: yalnızca *kim* ve *ne zaman* diyor, yöntemin kendisi bir skill'de bir kez yazılıyor.

**Elinizdeki repoya da kuruluyor.** `adopt`, Claude Starter Kit'i ayrı bir dala commit'lenmemiş hâlde bırakıyor; yani değişikliğin tamamı, hiçbiri kalıcı olmadan önce editörünüzün diff ekranında duruyor. `main` dalına hiç dokunulmuyor.

## Hızlı başlangıç

```bash
npx @byerlikaya/claude-starter-kit          # yeni proje — kurulum sihirbazı
npx @byerlikaya/claude-starter-kit adopt    # mevcut proje — ayrı bir dalda devir
```

Ardından ilk Claude Code mesajınız olarak `.claude/FIRST_PROMPT.md` dosyasını yapıştırın. Homebrew, sürüm arşivi ve plugin sürümü [Kurulum](#kurulum) başlığında.

## İçindekiler

- [İddialar ve dayanakları](#i̇ddialar-ve-dayanakları)
- [Ne değildir](#ne-değildir)
- [Ajanlar](#ajanlar)
- [İçerik](#i̇çerik)
- [Nasıl çalışıyor](#nasıl-çalışıyor)
- [Kural → kapı](#kural--kapı)
- [Kurulum](#kurulum)
- [Oturum ve token maliyeti](#oturum-ve-token-maliyeti)
- [Doğrulama](#doğrulama)
- [Genişletme](#genişletme)
- [Lisans ve kaynaklar](#lisans-ve-kaynaklar)

---

## İddialar ve dayanakları

Bu sayfada üç iddia var. Her birinin arkasında bir sayı ve açıp bakabileceğiniz bir dosya duruyor.

| İddia | Ölçüm | Nereden bakılır |
|:--|:--|:--|
| **Uzmanlar gerçekten devreye giriyor** | Yönlendirme hook'u olmadan 24 oturumda **0** devir. Claude Starter Kit'in hook'uyla dört turda **48'de 39** | [`evals/`](evals/) · `route-hint.sh` |
| **Kritik kurallar araç seviyesinde tutuyor** | Her kapı iki yönlü test ediliyor: engellemesi gerekeni engelliyor mu, komşusuna dokunmuyor mu | `smoke-test.sh` |
| **Claude Starter Kit fark çıkmayan ölçümleri de yayımlıyor** | Bugüne kadar 7 A/B vakası; **6'sı başa baş bitti** — hepsi yayında, disiplin metninin işi yaptığı ve kapının hiç ateşlenmediği vaka dahil | [`evals/README.md`](evals/README.md) |

Birincisi bir cümleyi hak ediyor, çünkü Claude Starter Kit'in var olma sebebi. Agent kurmuş olmanız onların çalışacağı anlamına gelmiyor. Tek alana odaklı bir istekte — bütün ajanlar kurulu, devir aracı açık, iş tam olarak bir agent'ın alanında — Claude Code işi ana akışta tutuyor ve **24 oturum boyunca hiç devretmiyor**. Claude Starter Kit'in `UserPromptSubmit` hook'u ise isteğinizin yanına o işin sahibi olan agent'ın adını yazıyor ve aynı ölçüm **48'de 39** veriyor. Sizin fazladan bir şey yazmanız gerekmiyor.

Üçüncüsü ise güveni asıl hak eden madde. Bir A/B düzeneği aynı isteği hem kit kurulu bir projede hem de çıplak bir projede çalıştırıp diskte ne kaldığına puan veriyor. Vakaların çoğu **başa baş** bitti; yani kit bir üstünlük göstermedi. Yine de gerekçesiyle birlikte yayımlandılar.

## Ne değildir

Sınırı açıkça söylemek de iddianın bir parçası.

- **Kum havuzu değildir.** Kapılar katmanlı savunmadır. Kabuk Turing-tamdır; yeterince kararlı bir yeniden yazım her kalıbın etrafından dolaşabilir. Kapıların önlediği şey **kazadır** — teslim baskısı altında seçilen kaba komut. Sert bir sınır istiyorsanız Claude Code'u bir devcontainer ya da sanal makinede çalıştırın; `/doctor-csk` bunun olup olmadığını söyler.
- **Devir garantisi değildir.** Claude devri; işe, agent'ın tarifine ve o anki bağlama bakarak karar verir. Bu bir kural değil, bir yargı. Bir agent'ın kesinlikle çalışması gerektiğinde `@agent-<ad>` bunu garantiler.
- **Ölçülmüş bir verimlilik kazancı değildir.** Yedi A/B vakasının altısı başa baş bitti. Claude Starter Kit'in kanıtı *kuralların tutması* ve *uzmanların devreye girmesi* üzerine; daha hızlı teslim üzerine değil.
- **Tek bir teknolojiye bağlı değildir.** Backend uzmanı, projenizin hangi kalıbı beyan ettiyse onu uygular. .NET/DevArchitecture varsayılandır, zorunluluk değil.

---

## Ajanlar

**12 uzman agent**, beş aşamaya dağılmış; böylece hiçbir şey commit'lenmeden önce kalite kademe kademe yükseliyor.

<div align="center">
  <img src="assets/orchestration-tr.svg" alt="Beş aşama: Anla, Üret, Denetle, Kapat, Devret" width="820">
</div>

<details>
<summary>🧭&nbsp; <b>12 agent'ın tamamı — hangisi neyin sahibi, ne zaman devreye girer</b> &nbsp;<sub>açmak için tıklayın</sub></summary>

| Agent | Aşama | Ne zaman | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Anla | kapsam belirsizse | `inherit` |
| **backend-expert-csk** | 🔨 Üret | sunucu / API / iş kuralı | `inherit` |
| **database-expert-csk** | 🔨 Üret | şema, migration, index, cache | `inherit` |
| **frontend-expert-csk** | 🔨 Üret | arayüz, bileşen, istemci işi | `inherit` |
| **devops-expert-csk** | 🔨 Üret | dağıtım, CI hattı, olay | `inherit` |
| **security-expert-csk** | 🔍 Denetle | auth / IDOR / injection / sır · **güvenlik kritikse zorunlu** | `inherit` · `effort: high` |
| **privacy-agent-csk** | 🔍 Denetle | kişisel veri (KVKK / GDPR) | `inherit` |
| **test-expert-csk** | 🔍 Denetle | test, kapsam, regresyon | `inherit` |
| **performance-expert-csk** | 🔍 Denetle | sıcak yol, sorgu/döngü, render, payload | `inherit` |
| **review-agent-csk** | ✅ Kapat | commit öncesi kod sağlığı incelemesi | `inherit` |
| **commit-agent-csk** | ✅ Kapat | commit'i önerir, onayı bekler | `haiku` |
| **session-manager-csk** | 🤝 Devret | bağlam dolduğunda / faz bittiğinde | `inherit` |

</details>

**Neredeyse her agent neden `inherit` diyor?** Modeli sabitlenmemiş bir alt agent, oturum için seçtiğiniz modelde çalışır. Bu bilinçli bir tercih: bir sabitleme yalnızca agent'ı çevresindeki işten *farklı* bir seviyeye çekebilir, oysa bir değişikliği temize çıkaran inceleme, o değişikliği yazan şeyden asla zayıf olmamalı. `security-expert-csk` fazladan titizliği `effort: high` ile satın alır — başka bir modelle değil, *sizin* modelinizde daha çok düşünerek. `commit-agent-csk` ise `haiku` kalır; çünkü hazırlanmış bir diff'i Conventional Commit'e çevirmek mekanik bir iştir ve commit kuralları zaten kapılıdır.

Her agent, skill ve komut `-csk` ekiyle gelir; böylece ne projenizin kendi bileşenleriyle çakışır ne de bir Claude Code yerleşiğinin üstünü örter.

## İçerik

<div align="center">
  <img src="assets/network-tr.svg" alt="12 agent ve 38 skill, gerçek uygular ilişkileriyle" width="820">
  <br><sub>Her agent, her skill ve aralarındaki gerçek <code>uygular</code> ilişkileri — aşamalara göre gruplanmış, her agent kendi renginde; merkezde hepsini yöneten ana akış.</sub>
</div>

| Bileşen | Adet | Nedir |
|:--|:--:|:--|
| **Ajanlar** | 12 | İnce tetikleyiciler — bir alanın *sahibi kim* ve *ne zaman* devreye girer |
| **Skiller** | 38 | Yöntemin kendisi; bir kez yazılır, ihtiyacı olan uygular |
| **Slash komutları** | 7 | `/brainstorm-csk` · `/plan-csk` · `/review-csk` · `/ship-csk` · `/handoff-csk` · `/update-csk` · `/doctor-csk` |
| **Hook'lar** | 8 | Kapılar, ayrıca oturum ölçümü ve yönlendirme |
| **Disiplin** | 1 | İlkeler, akış, Bitti Tanımı, yasaklar — `CLAUDE.md`'nizin içe aktardığı dosya |

<details>
<summary>🪝&nbsp; <b>8 hook'un tamamı — hangi kapı neyi tutuyor</b> &nbsp;<sub>açmak için tıklayın</sub></summary>

| Hook | Görevi |
|:--|:--|
| `route-hint.sh` | Her isteğin yanına o işin sahibi agent'ın adını yazar; uzmanlar siz istemeden devreye girer |
| `guard-bash.sh` | Araç seviyesinde komut kapısı: commit/push onayı, yıkıcı işlemler, uzaktan kod çalıştırma, hook kurcalama |
| `guard-write.sh` | Aynı korumanın Write/Edit tarafı — sessizce silinebilen bir kapı, kapı değildir |
| `guard-commit-scan.sh` | Gerçek iz ve sır tarayıcılarını `PreToolUse`'dan çalıştırır; `core.hooksPath` kurulamayan yerde bile commit kapısı çalışır |
| `context-usage.sh` | Gerçek token sayısını transcript'ten okur ve her turda bağlama enjekte eder |
| `session-guard.sh` | Bağlam %75 dolunca bir, %90'da bir daha uyarır — turu asla bloklamaz |
| `session-rehydrate.sh` | `/compact` ya da `/clear` sonrası devir notunu yeniden yüzeye çıkarır |
| `skill-trust.sh` | Claude Starter Kit'in göndermediği ve sizin kabul etmediğiniz her skill ya da agent'ı adıyla bildirir |

İki git hook'u — `pre-commit` ve `commit-msg` — iz, sır ve depo şişkinliği taramalarını çalıştırır. Plugin sürümü de kapı hook'larını taşır.

</details>

<details>
<summary>📚&nbsp; <b>38 skill'in tamamı — katalog, her skill'in kendi dosyasından üretilir</b> &nbsp;<sub>açmak için tıklayın</sub></summary>

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

## Nasıl çalışıyor

Tasarımı ayakta tutan üç kural var.

1. **Agent ince bir tetikleyicidir.** Yalnızca *kim* ve *ne zaman* der, fazlası yok. Kısa kalır, çünkü tarifi her oturumun bağlamına yüklenir.
2. **Skill tek doğruluk kaynağıdır.** Yöntemin kendisi orada bir kez yazılır ve asla agent'a kopyalanmaz.
3. **Önemli kural kapıya dönüşür.** Yaptırım araç seviyesinde durur — bir hook, bir izin, bir test vakası. Modelden hatırlaması istenmez.

Günlük hâli şöyle görünür:

```
/plan-csk        →  uzman ajanlar üretir  →  /review-csk       →  /ship-csk          →  /handoff-csk
belirsiz kapsam     alanın sahibi işi        güvenlik · kalite    Bitti Tanımı kapısı;  bağlam doldu;
planlamaya gider    yapar                    · test denetimi      commit'i önerir,      devret, sonra
                                                                  onayı bekler          /clear
```

## Kural → kapı

Tek bir tablo okuyacaksanız bu olsun. Solda kural, sağda o kuralın esnemesine izin vermeyen şey.

| Kural | Neyle zorlanıyor |
|:--|:--|
| Commit ve push her izin modunda onayınızı ister | `guard-bash.sh` yalnızca sizin cevaplayabileceğiniz bir onay sorar. `bypassPermissions` altında kapalı tarafa düşer |
| Yıkıcı işlemler: `reset --hard`, `checkout -- .`, force push, `rm -rf`, `clean -f`, `--no-verify`, amend | `guard-bash.sh`, araç seviyesinde engeller |
| Uzaktan kod çalıştırma ve izin patlatma: `curl…\|bash`, herkese yazılabilir `chmod`, `dd of=` | `guard-bash.sh`, her modda kesin engel |
| Kapıyı etkisizleştirme — `core.hooksPath` yönlendirme, hook düzenleme ya da silme | `guard-bash.sh` (kabuk) + `guard-write.sh` (dosya düzenleme) |
| Hiçbir API anahtarı, token ya da özel anahtar commit'e girmez | `pre-commit` sır taraması; her kalıbın kendi test vakası var |
| Hiçbir kimlik bilgisi bağlama *okunmaz* — `~/.ssh/id_rsa`, `~/.aws/credentials`, `*.pem`, kubeconfig | `settings.json` okuma reddi + `guard-bash.sh` |
| Commit'te yapay zekâ imzası ya da satıcı şablonu adı bulunmaz | `pre-commit` + `commit-msg` git hook'ları |
| Build çıktısı, vendor ağacı ya da aşırı büyük dosya hazırlanmaz | `pre-commit` depo şişkinliği taraması |
| `.claude/` içinde beliren doğrulanmamış skill ya da agent, tarayıcı kararıyla bildirilir | Oturum başında `skill-trust.sh` |
| Sabit yüklenen bağlam yalın kalır | `smoke-test.sh` bileşen başına bayt bütçesi |
| Çalışan bir oturum, güncellemeden sonra eski kuralları izlemez | `context-usage.sh` sürüm karşılaştırması |

Her kural **iki yönlü** test edilir: engellemesi gerekeni engelliyor mu, ve komşusuna dokunuyor mu — `chmod 755`, `rm -rf build`, `git checkout -- src/app.js`. Kanıtlanmamış kapı kapı değildir; rutin işte ateşlenen kapının ise etrafından dolanılır.

**Kapıyı ateşlerken görmek.** `CSK_GATE_LOG=<yol>` verirseniz her guard, her karar için tek satır yazar: `BLOCK` / `ASK` / `ALLOW`, kural ve komut. İstemedikçe kapalıdır, yalnızca yazar ve kararı verdikten *sonra* yazar; yani kararı etkileyemez. "Kapı mı durdurdu, yoksa model oraya hiç uzanmadı mı?" sorusunda işe yarar — bu iki durum geriye birebir aynı izi bırakır.

---

## Kurulum

İki giriş noktası: yeni proje için **`start.sh`**, hâlihazırda ilerleyen proje için **`adopt.sh`**. Hangi kanaldan giderseniz gidin aynı iki komut çalışır.

```bash
# npx — kurulum gerektirmez
npx @byerlikaya/claude-starter-kit                  # yeni proje
npx @byerlikaya/claude-starter-kit adopt            # mevcut proje
npx @byerlikaya/claude-starter-kit@latest update    # kurulu kiti tazele

# Homebrew
brew install byerlikaya/tap/claude-starter-kit
claude-starter-kit          # yeni proje
claude-starter-kit adopt    # mevcut proje

# Sürüm arşivi — paket yöneticisi olmadan
gh release download --repo byerlikaya/claude-starter-kit -p '*.tgz' && tar xzf claude-starter-kit-*.tgz
bash start.sh               # yeni proje
bash adopt.sh               # mevcut proje (tazelemek için tekrar çalıştırın)
```

**Windows:** Claude Starter Kit bash tabanlıdır. **Git Bash** içinde çalıştırın ([git-scm.com](https://git-scm.com)); WSL de alternatif olarak çalışır.

**Plugin sürümü** — iskele kurmadan, yalnızca ajanlar, skiller ve kapı hook'ları mevcut Claude Code'unuzun içinde:

```bash
/plugin marketplace add byerlikaya/claude-starter-kit
/plugin install claude-starter-kit@byerlikaya
```

Kurulu bir plugin, siz yenisini istemedikçe kurduğunuz sürümde kalır; bu yüzden `claude plugin marketplace update byerlikaya` ve ardından `claude plugin update claude-starter-kit` çalıştırın, uygulanması için de Claude Code'u yeniden başlatın.

### Yeni proje

```bash
bash start.sh [--dotnet|--generic] [-h]
```

İki adım: backend kalıbı, sonra hiçbir şey yazılmadan önce onayladığınız bir özet.

**Her kurulum aynı kurulumdur** — 12 ajanın ve 38 skill'in tamamı; backend, web ve mobil (React Native/Expo) bir arada. API olarak başlayıp sonradan web istemcisi kazanan bir proje, ikisi için de baştan donanımlıdır.

| Kurulumda sorulan | Seçenekler | Neyi değiştirir |
|:--|:--|:--|
| Backend kalıbı | `--dotnet` · `--generic` | `devarch-module` skill'i ve DevArchitecture tabanı |
| DevArch tabanı — yalnız `--dotnet` | onayla · atla | `./backend` iskelesinin kurulup kurulmayacağı |

**`--dotnet`**, üretime hazır [DevArchitecture](https://github.com/DevArchitecture/DevArchitecture) temelini (CQRS · IResult · AOP · kimlik doğrulama) bir onay kapısının ardından klonlar ve onu zaten bilen ajanları kurar; böylece token'lar standart bir mimariyi yeniden üretmeye değil, sizin iş mantığınıza gider. Backend `./backend` altına yerleşir, yanına `./frontend` ayrılır ve çözüm dosyası projenizin adıyla yeniden adlandırılır.

**`--generic`** ise aynı uzmanı o kalıp olmadan kurar — Node, Go, Python ya da farklı bir kalıp kullanan bir .NET projesi için. Hiçbir şey DevArchitecture'ı dayatmaz: backend uzmanı, projenizin beyan ettiği kalıp skill'ini uygular.

### Mevcut proje

```bash
bash adopt.sh    # hedef projenin kökünde
```

<div align="center">
  <img src="assets/handover-tr.svg" alt="adopt.sh kiti nasıl devrediyor" width="900">
</div>

Claude Starter Kit, bir ekibin projeyi başka bir ekibe devretmesi gibi gelir: hiçbir şey bozulmaz, verilmiş kararlar kaybolmaz ve kit kenarda pasif durmaz.

Bütün değişiklikler ayrı bir dala, **commit'lenmeden** düşer; yani eklenen ve değişen her dosya editörünüzün Source Control panelinde görünür. Oradan inceler, `git commit` ile kabul eder ya da `reset` ile atarsınız. `main` el değmeden kalır. Ajanları çakışmadan yan yana kurulur, disiplin tek bir `@import` ile bağlanır, `settings.json` şema farkındalığıyla birleştirilir ve mevcut husky ya da lefthook zincirleri bir shim üzerinden çalışmaya devam eder. İş, kalıcı bir `docs/HANDOVER.md` ve bir ADR ile kapanır; böylece kararlar bir sohbet kaydında değil, versiyon kontrolünde yaşar.

### Güncelleme

```bash
npx @byerlikaya/claude-starter-kit@latest update    # ya da oturum içinde /update-csk
```

<details>
<summary>🔁&nbsp; <b>Güncelleme mekaniği — ne tazelenir, değişiklik nereye düşer</b> &nbsp;<sub>açmak için tıklayın</sub></summary>

Claude Starter Kit, kurulum anında `.claude/kit.conf` dosyasına backend kalıbını ve hangi kurucunun çalıştığını damgalar; yanına `.claude/VERSION` düşer. Tazeleme **kalıbı korur**: `--dotnet` bir proje `devarch-module` skill'ini korur, bir Node reposuna ise asla verilmez. Damga yoksa güncelleyici kalıbı kurulu dosyalardan geri okur. Eksik kalan her bileşen tamamlanır ve eklenen her şey sessizce belirmek yerine **adıyla listelenir**.

| | Güncellemede |
|:--|:--|
| `.claude/` ajanlar · skiller · komutlar · hook'lar · eval | yeni sürümden tazelenir |
| `.claude/DISCIPLINE.md` | **üzerine yazılır** — kite aittir, kendinize ait hiçbir şeyi burada tutmayın |
| `./CLAUDE.md` | hiç dokunulmaz — proje kurallarınız yazdığınız gibi kalır |
| `.claude/settings.json` | şema farkındalığıyla birleştirilir; kendi hook'larınız ve izinleriniz korunur |
| kendi ajanlarınız ve skilleriniz (`-csk` eki olmayanlar) | dokunulmaz |

Değişikliğin nereye düşeceği bir tercihtir. İlk devir `kit-adopt-<zaman>` adında bir inceleme dalı açar. `.claude/` dizini gitignore'lu rutin bir güncelleme mevcut dalınızda uygulanır. `.claude/` dizini **takip ediliyorsa** güncelleme size sorar. `--here` ya da `--new-branch` ile zorlayabilir, `--yes` ile soruları atlayabilirsiniz. Her hâlükârda değişiklik commit'lenmeden bırakılır.

Oturum içinde **`/update-csk`** sürüm kontrolünü yapar, güncelleyiciyi çalıştırır, sonucu `/doctor-csk` ile doğrular ve tazelenmiş disiplinin aynı oturumda yüklenmesi için `/compact` önerir. **`/doctor-csk`** kurulu bir kiti istediğiniz an denetler — hook'lar çalıştırılabilir mi, `core.hooksPath` ayarlı mı, kapılar bağlı mı, disiplin gerçekten içe aktarılmış mı — ve projenin kendisi için tavsiye niteliğinde bir hazırlık puanı basar.

Bir projenin `CLAUDE.md` dosyası disiplini içe aktarmak yerine **satır içinde** taşıyorsa güncellemeler oraya ulaşamaz. Güncelleyici bunu saptar, hangi satırların etkilendiğini gösterir ve onları tek bir `@.claude/DISCIPLINE.md` satırıyla değiştirmeyi önerir — önce yedek alarak, incelediğiniz bir dalda. Reddederseniz hiçbir şeye dokunulmaz.

</details>

---

## Oturum ve token maliyeti

Claude kendi üzerinde `/context` çalıştıramaz; bu yüzden çoğu kurulum oturumun ne kadar dolduğunu **tahmin eder**. Claude Starter Kit ölçer. `context-usage.sh`, son turun API kullanımından gerçek token sayısını transcript'ten okur — `/context`'in verdiği sayının aynısını — ve her turda bağlama enjekte eder. Doluluk %75'i geçince bir uyarı, %90'da bir uyarı daha alırsınız. İkisi de turunuzu bloklamaz.

Disiplin ile agent ve skill tarifleri her oturuma yüklenir. Bu sabit yük bugün **~24 KB** — gerçek bir turda **~10 bin token** mertebesinde; tahmin değil, gerçek bir `claude -p` çalıştırmasıyla kalibre edildi. Eklenen her skill bütün oturumlara kalıcı ~100 token'lık bir vergidir; `smoke-test.sh` bu yüzden bileşen başına bayt bütçesi uygular. Bütçe yükseltilebilir, ama yalnızca testi açıkça düzenleyerek.

**Neden daha az bileşen kurulmuyor?** Çünkü kazancı yok denecek kadar az. Kümenin tamamı tarif olarak ~3,3k token tutar; dört UI skill'ini ve frontend agent'ını dışarıda bırakmak ~400 token kazandırır — 200k'lık bir pencerenin yaklaşık %0,2'si. Maliyeti proje başına değil, bayt bütçesinin yaptığı gibi bileşen başına denetlemek anlamlıdır.

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek bir istek doğru agent ya da skill'e gidiyor mu
bash .claude/eval/doctor.sh          # bu kurulum sağlıklı mı, proje hazır mı
```

## Genişletme

Bir agent ya da skill eklerken `AGENT_TEMPLATE.md` sözleşmesine uyun: frontmatter (ad · tetikleyici ifadeleri içeren tarif · en az yetkili araç listesi · model seviyesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl → Koordinasyon → Bitti Tanımı → Çıktı → Yükseltme → Örnek → Kısıtlar). `smoke-test.sh`, hiçbir şeyin yönlendirmediği bir bileşeni kabul etmez; yani uyuyan bir bileşen yayımlanamaz.

## Lisans ve kaynaklar

MIT — [LICENSE](LICENSE) dosyasına bakın.

- **[NIST SP 800-218 (SSDF)](https://csrc.nist.gov/pubs/sp/800/218/final)** PW.7 ve **[OpenSSF Scorecard](https://github.com/ossf/scorecard)** `Code-Review` denetimi — `code-review-csk`'nin yönetişim katmanı: incelemenin yapılması ve bulguların kaydedilip triyaj edilmesi.
- **[Conventional Comments](https://conventionalcomments.org/)** — `code-review-csk`'nin yorumlarını yazdığı etiket sözlüğü (CC BY 3.0).
- **[google/eng-practices](https://github.com/google/eng-practices)** — `code-review-csk`'deki inceleme öncelik sırası ve "kod sağlığı" ölçütü, damıtılıp yeniden ifade edildi (CC-BY 3.0).
