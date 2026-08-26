<div align="center">

<img src="assets/logo.svg" alt="Claude Starter Kit" width="460">

**Tek bir asistan değil. Gerçekten işleyen bir mühendislik ekibi.**

12 uzman agent işi planlar, yazar, güvenlik ve test incelemesinden geçirir, sonra kapatır

Paylaşılan bir depoda bir işi üstlenmek atomik bir git iddiasıdır — aynı işe iki kişi başlayamaz

![Sürüm](https://img.shields.io/badge/version-2.6.0-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)
![Agent](https://img.shields.io/badge/agents-12-f59e0b?style=flat-square)
![Skill](https://img.shields.io/badge/skills-40-f59e0b?style=flat-square)
![Claude Code](https://img.shields.io/badge/Claude_Code-agentic_kit-8b5cf6?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

</div>

---

## Claude Starter Kit ne yapıyor?

Claude Code'da her iş tek bir yerde olup biter: siz söylersiniz, model yazar. Claude Starter Kit araya bir ekip ve bir sıra koyar.

**İşin bir yolu oluyor.** 12 agent'ın her biri tek bir alanın sahibi ve beş aşamada çalışıyorlar: planla, üret, denetle, kapat, devret. Kapsamı belirsiz bir istek, tek satır yazılmadan planlamaya düşer; sunucu işi backend sahibine, şema işi veritabanı sahibine gider. Riskli bir değişiklik güvenlik incelemesinden **geçmeden** kapanamaz, commit önerilmeden önce de kod sağlığı incelemesi koşar. Bunu bir şemadan ibaret olmaktan çıkaran şey, isteğinizin yanına o işin sahibini yazan yönlendirme hook'u.

**Yöntem bir kez yazılıyor.** 40 skill *nasıl* sorusunu taşıyor: test, migration, API sözleşmesi, gözlemlenebilirlik, erişilebilirlik, çeviri bütünlüğü, bağımlılık yükseltme, olay müdahalesi, dağıtım. Agent'lar ince kalıyor; yalnızca *kim* ve *ne zaman* diyor, gerisini ilgili skill'e bırakıyorlar. Standartlarınızı her oturumda baştan anlatmıyorsunuz.

**Kritik kurallar hatırlanmıyor, uygulanıyor.** Yıkıcı bir komut çalışmadan reddedilir, commit onayınızı bekler, sızmış bir anahtar veya yapay zekâ imzası geçmişe hiç girmez. Bunlar kitin amacı değil, yukarıdaki düzeni gözünüzü ayırmadan bırakabilmenizin sebebi.

**Ekip arkadaşlarınızın işi görünür oluyor.** Her kit kendi makinesinde koşar; üç kişi aynı depoyu paylaştığında "Ali 1. maddeye bir saat önce başladı" bilgisi diğer ikisinin bakabileceği hiçbir yerde durmaz — ve aynı iş iki kez yapılır. Pano bunu tam kırıldığı yerde onarır: birleştirme anında değil, **maddeyi üstlenme** anında. Üstlenme bir git ref'ine push'tan ibarettir; `git push` yalnızca ileri sarım kabul ettiği için, aynı anda gelen iki üstlenmeden tam olarak biri yerleşir. Diğeri saniyeyi bulmadan reddedilir, üstelik maddeyi kimin tuttuğunu ve neyin boşta olduğunu söyleyerek — daha tek satır yazılmadan. Tavsiye niteliğinde bir kilit dosyası değil, sonradan çözülecek bir merge conflict de değil: atomikliği git'in kendisi veriyor, işin içinde ne sunucu var ne token ne servis. Bir maddeyi üstlenmek ayrıca bağımlılıklarının size ne teslim ettiğini önünüze koyar ve sizi kimlerin beklediğini söyler. `/board-csk init` çalıştırılana kadar kapalı; tek başına çalışan onu hiç görmez.

<div align="center">
  <img src="assets/board-tr.svg" alt="İki geliştirici aynı saniyede aynı maddeyi üstleniyor; biri yerleşiyor, diğeri tek satır kod yazılmadan reddediliyor" width="900">
</div>

**Elinizdeki depoya giriyor.** `adopt`, Claude Starter Kit'i bir dal üzerinde, staged ama commit'lenmemiş hâlde devreder; böylece değişikliğin tamamı, size ait olmaya karar vermeden önce editörünüzün diff ekranında durur. `main` dalınıza hiç dokunulmaz.

## Hızlı başlangıç

```bash
npx @byerlikaya/claude-starter-kit          # yeni proje — kurulum sihirbazı
npx @byerlikaya/claude-starter-kit adopt    # mevcut proje — dal üzerinde devir
```

Ardından `.claude/FIRST_PROMPT.md` dosyasını Claude Code'a ilk mesaj olarak yapıştırın. Homebrew, sürüm arşivi ve plugin sürümü için [Kurulum](#kurulum) bölümüne bakın.

## İçindekiler

- [Agent'lar](#agentlar)
- [İçerik](#i̇çerik)
- [Nasıl çalışıyor](#nasıl-çalışıyor)
- [Kural → yaptırım](#kural--yaptırım)
- [Kurulum](#kurulum)
- [Oturum ve token maliyeti](#oturum-ve-token-maliyeti)
- [Doğrulama](#doğrulama)
- [Genişletme](#genişletme)
- [Lisans ve kaynaklar](#lisans-ve-kaynaklar)

---

---

## Agent'lar

Beş aşamaya yayılmış **12 uzman agent** — kalite, hiçbir şey commit edilmeden önce basamak basamak yükseliyor.

<div align="center">
  <img src="assets/orchestration-tr.svg" alt="Beş aşama: Anla, Üret, Denetle, Kapat, Devret" width="820">
</div>

<details open>
<summary>🧭&nbsp; <b>12 agent'ın tamamı: hangisi neyin sahibi, ne zaman devreye giriyor</b></summary>

| Agent | Aşama | Ne zaman devreye girer | Model |
|:--|:--|:--|:--:|
| **planner-csk** | 🧭 Anla | kapsam belirsizse | `inherit` |
| **backend-expert-csk** | 🔨 Üret | sunucu / API / iş mantığı | `inherit` |
| **database-expert-csk** | 🔨 Üret | şema, migration, indeks, önbellek | `inherit` |
| **frontend-expert-csk** | 🔨 Üret | arayüz, bileşen, istemci işi | `inherit` |
| **devops-expert-csk** | 🔨 Üret | dağıtım, CI hattı, olay müdahalesi | `inherit` |
| **security-expert-csk** | 🔍 Denetle | auth / IDOR / injection / sır · **güvenlik kritikse zorunlu** | `inherit` · `effort: high` |
| **privacy-agent-csk** | 🔍 Denetle | kişisel veri — KVKK/GDPR ve projenin beyan ettiği diğer rejimler | `inherit` |
| **test-expert-csk** | 🔍 Denetle | test, kapsam, regresyon | `inherit` |
| **performance-expert-csk** | 🔍 Denetle | sıcak yol, sorgu/döngü, render, payload | `inherit` |
| **review-agent-csk** | ✅ Kapat | commit öncesi kod sağlığı incelemesi | `inherit` |
| **commit-agent-csk** | ✅ Kapat | commit'i önerir, onayı bekler | `haiku` |
| **session-manager-csk** | 🤝 Devret | bağlam dolduğunda / aşama bittiğinde | `inherit` |

</details>

**Neden neredeyse her agent `inherit` diyor?** Modeli sabitlenmemiş bir subagent, oturum için seçtiğiniz modelde koşar. Bu bilinçli bir tercih: sabitleme ancak bir agent'ı çevresindeki işten *farklı* bir seviyede çalıştırmaya yarar, ve bir değişikliği temize çıkaran inceleme, o değişikliği yazandan zayıf olamaz. `security-expert-csk` fazladan titizliği `effort: high` ile alır — başka bir modelde değil, *sizin* modelinizde daha çok düşünerek. `commit-agent-csk`'de `haiku` kalır, çünkü staged bir diff'i Conventional Commit'e çevirmek mekanik bir iş ve commit kuralları zaten yaptırıma bağlı.

## İçerik

<div align="center">
  <img src="assets/network-tr.svg" alt="12 agent ve 40 skill, gerçek uygular ilişkileriyle" width="820">
  <br><sub>Her agent, her skill ve aralarındaki gerçek <code>uygular</code> ilişkileri — aşamaya göre gruplanmış, her agent kendi renginde; merkezde onları yöneten ana akış.</sub>
</div>

| Bileşen | Adet | Nedir |
|:--|:--:|:--|
| **Agent** | 12 | İnce tetikleyiciler — bir alanın *kimin* olduğu ve *ne zaman* devreye gireceği |
| **Skill** | 40 | Yöntemin kendisi; bir kez yazılır, ihtiyacı olan uygular |
| **Slash komutu** | 10 | `/brainstorm-csk` · `/plan-csk` · `/review-csk` · `/ship-csk` · `/handoff-csk` · `/update-csk` · `/doctor-csk` · `/board-csk` · `/gates-csk` · `/skill-csk` |
| **Hook** | 12 | Yaptırımlar, ayrıca oturum ölçümü ve yönlendirme |
| **Disiplin** | 1 | İlkeler, akış, Definition of Done, yasaklar — `CLAUDE.md`'nizin import ettiği dosya |

<details>
<summary>🪝&nbsp; <b>12 hook'un tamamı: hangi yaptırım neyi tutuyor</b></summary>

| Hook | Görevi |
|:--|:--|
| `route-hint.sh` | Her isteğin yanına o işin sahibi agent'ı yazar; uzmanlar siz istemeden devreye girer |
| `guard-bash.sh` | Araç seviyesinde komut kapısı: commit/push onayı, yıkıcı işlemler, uzaktan kod çalıştırma, hook kurcalama |
| `guard-write.sh` | Aynı korumanın Write/Edit tarafı — sessizce silinebilen bir kapı, kapı değildir. Hedef yolu eşleştirmeden önce sadeleştirir, böylece bir kapı dosyasına farklı bir yazımla ulaşılamaz. Pano üstlenme kapısını da o tutar: ekip deposunda, elinizde bir madde yokken **ilk dosya düzenlemesi** reddedilir, böylece üstlenilmemiş iş commit anında değil daha birinci dakikada yakalanır |
| `guard-commit-scan.sh` | Gerçek iz ve sır tarayıcılarını `PreToolUse` üzerinden koşturur; böylece `core.hooksPath` ayarlanamayan yerlerde de commit kapısı çalışır |
| `context-usage.sh` | Transcript'ten gerçek token sayısını okur ve her tura enjekte eder |
| `session-guard.sh` | Bağlam doluluğu %75'i ve %90'ı geçtiğinde birer kez uyarır — turu asla kesmez |
| `session-rehydrate.sh` | `/compact` veya `/clear` sonrasında devir notunu yeniden önünüze getirir |
| `skill-trust.sh` | Claude Starter Kit'in getirmediği ve sizin de kabul etmediğiniz her skill ya da agent'ı adıyla bildirir |
| `session-stats.sh` | Oturumun gerçekte ne yaptığını raporlar: patlayan araç döngüleri, tekrarlanan istekler, kesintiler. `reflect` ve `handoff` bunu okur, böylece geri dönüş hatırlamaya değil kayda dayanır |
| `session-update-check.sh` | Oturum açılırken bir kez, yeni bir kit sürümünün yayımlandığını söyler; her sürüm onu getirecek kanala göre karşılaştırılır. Sorgu ayrık koşar ve en fazla günde bir kez yapılır, dolayısıyla çevrimdışı ya da proxy arkasındaki bir makinede oturum açılışı hiçbir şey ödemez; `CSK_NO_UPDATE_CHECK=1` kapatır |
| `board.sh` | Ekip panosunun motoru: bir maddeyi üstlenir, devreder, tamamlar. Üstlenmenin kendisi push'tur — bir git ref'ine commit, yalnızca ileri sarım — bu yüzden aynı maddeyi iki kişinin alması, alma anında ve saniyeyi bulmadan çözülür: biri yerleşir, diğeri maddeyi kimin tuttuğu ve neyin boşta olduğu bilgisiyle reddedilir. Commit'ler git plumbing ile kurulur, dolayısıyla bir üstlenme çalışma ağacınıza, index'inize veya dalınıza dokunmaz |
| `board-sync.sh` | Yalnızca bu makineyi görebilecek olan oturuma ekibin durumunu taşır: kim hangi maddeyi tutuyor, ne üstlenilebilir, ne bloke, hangi üstlenme sessizleşmiş. Oturum başında yerel önbelleği okur ve tazelemeyi ayrık yapar, böylece erişilemeyen bir uzak depo oturum açılışını yavaşlatmaz; `CSK_NO_BOARD=1` kapatır |

İki git hook'u — `pre-commit` ve `commit-msg` — iz, sır, depo şişkinliği ve özel yol taramalarını koşturur. Sonuncusu şunun için var: yalnızca sizin makinenizde bulunan bir yol paylaşılan depoya yazılarak değil, yapıştırılarak sızar. Kendi `$HOME`'unuzu kendiliğinden engeller; yalnızca sizin tanıyabileceğiniz iç proje, müşteri ve sunucu adları ise gitignore'lanmış `.private-terms.txt` dosyasından gelir (`.private-allowlist.txt` kaçış kapısıdır). `commit-msg` ayrıca pano üstlenme kapısını tutar: panosu olan bir depoda commit ya elinizdeki bir maddeyi anmalıdır (`[#3]`) ya da maddesiz olduğunu beyan etmelidir (`[chore]`). Plugin sürümü, `skill-trust.sh` dışında bunların hepsini getirir; o hook neyin kite ait olduğunu bir kurulum script'inin yazdığı `kit-manifest.txt`'ten okur ve plugin böyle bir dosya oluşturmaz.

</details>

**Ekip olarak çalışmak.** Her ekip arkadaşının kiti kendi makinesinde koşar ve `docs/` gitignore'lanmıştır — bir plan, bir devir notu ve devam eden bir madde varsayılan olarak özeldir. İki kişinin aynı şeyi yapması tam da buradan çıkar. Panosu olan yarısı ise paylaşılır: **bir kişi** `/board-csk init` çalıştırır (panoyu ayrı bir depoda tutmak için `--remote <url>`) ve maddeleri girer; **diğerleri hiçbir şey ayarlamaz** — oturumları panoyu kendiliğinden çeker ve kimin neyi tuttuğu, neyin üstlenilebilir olduğu, neyin hangi maddeye takıldığıyla açılır. Bir maddeyi almak, bağımlılıklarının gerçekte ne teslim ettiğini yazdırır ve onu bekleyen maddeleri sayar; böylece sıradaki kişi, bir öncekinin sahip olduğu bağlamla başlar. Hesap yok, token yok, servis yok: pano bir git ref'i, üstlenmek de bir push.

**Ve siz istemeden açılmıyor.** `/board-csk init` hiç çalıştırılmamış bir depoda ne pano vardır ne pano kapıları — tek başına çalışma ve kiti daha önce kurmuş her proje eskisi gibi davranır. Pano varsa `/board-csk off` (veya `--global`) üç kapıyı da bırakır ve panoyu olduğu gibi korur, `CSK_NO_BOARD=1` aynısını tek oturum için yapar, panonun ayarındaki `require_item: referenced` ise üstlenmeleri ve ortak hafızayı sürdürürken yalnızca yaptırımı kaldırır. Pano uzak depo olmadan da çalışır: madde listesi, bağımlılık sırası ve kapılar yerinde kalır, yalnızca paylaşım gider.

<details>
<summary>📚&nbsp; <b>40 skill'in tamamı: katalog, her skill'in kendi dosyasından üretilir</b></summary>

<!-- SKILLS:START -->

| Skill | Ne yapar |
|:--|:--|
| `a11y` | Frontend erişilebilirlik denetimi (WCAG): anlamsal HTML, klavye erişimi, odak yönetimi, kontrast, ARIA, ekran okuyucular. |
| `adr` | Mimari Karar Kaydı: bağlam-karar-sonuç; geri dönüşü pahalı kararlar için. |
| `api-design` | API sözleşme tasarımı: kaynak adlandırma, hata modeli, sürümleme, sayfalama, geriye dönük uyumluluk, OpenAPI. |
| `automode-policy` | Auto mod sınıflandırıcısının yapılandırmasını denetler: kitin kuralları orada mı, ve asıl sessiz arıza — özel bir autoMode bloğunun yerleşik engelleme kurallarını uyarısızca silmesi. Kapı değil, rapordur; ölçüldü ve özel kurallar uygulanmıyor (2026-08-24). |
| `brainstorm` | Planlamadan ÖNCE ıraksak keşif: bulanık isteği 2-4 kapsamlı seçenek + adlandırılmış bilinmezlere çevir, bir yön seç, spec-planning'e devret. |
| `ci-pipeline` | CI hattı disiplini: lint→build→test→kalite→güvenlik, hızlı-başarısızlık, deterministik derleme, secret yönetimi, PR kapıları. |
| `code-review-csk` | Kod inceleme disiplini: önem sırasına dizili, gerekçeli geri bildirim: değişiklik sistemin genel kod sağlığını iyileştiriyor mu. |
| `commit-message` | Conventional Commits: staged diff'i okur, `type(scope): özet` önerir; gerektiğinde gövde/footer ekler. |
| `confidence-check` | Uygulamaya BAŞLAMADAN önce hazırlık kapısı: bu iş zaten var mı, mimariye uyuyor mu, dış API iddiası doğrulandı mı, çalışan bir referans var mı, kök neden biliniyor mu. Herhangi bir "hayır" durdurur. |
| `db-migration` | Şema göçlerini güvenle uygula: aracı sapta, değişikliği riske göre sınıfla, yıkıcı olanları onaya bağla, prod'da yedekle, önizle-uygula-doğrula, hatada geri al. |
| `dependency-audit` | Bağımlılık denetimi: bilinen CVE'ler, lisans uyumu, terk edilmiş/eski paketler, lockfile bütünlüğü ve her yeni bağımlılık için gerekçe. |
| `dependency-upgrade` | Bağımlılıkları build'i kırmadan güncele taşı: neyin açığı var, neyi deprecated, neyi geride belirle; her hedef sürümü riske göre sınıfla (patch/minor/major), güvenli olanı uygula, doğrula, kırmızıda geri al. |
| `devarch-module` | DevArchitecture backend deseni: MediatR CQRS handler/command/query, IResult/IDataResult, Autofac AOP zinciri, FluentValidation, i18n. |
| `docs-writer` | Dokümantasyonu kodla eşzamanlı tutar: public API veya davranış değişince README, kullanım ve ilgili dokümanlar. |
| `eval-grader` | Çıktı kalitesini ölç, sezgiye bırakma: bir üretken görevi iki katmanlı grader ile puanla (ucuz deterministik kod metrikleri + boyut-boyut LLM-yargıç), sabit görev kümesine karşı, sabitlenmiş baz çizgisine göre işaretli deltalarla. Doğruluğun yanında maliyeti de puanlar (pass-slow). |
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
| `privacy-compliance` | KVKK/GDPR denetim yöntemi: veri envanteri, amaç/hukuki sebep/saklama, veri minimizasyonu, açık rıza, şeffaflık, ilgili kişi hakları, yurt dışına aktarım. Hangi rejimlerin geçerli olduğunu proje `.claude/regulations.conf` ile bildirir; kaynağı verilmemiş rejim hakkında hüküm verilmez, kişisel veri dışı (BDDK/PCI-DSS gibi) rejimler kapsam dışı olduğunu açıkça söyler. |
| `red-team` | LLM/agent savunmalarına saldırgan gözüyle test: talimat ele geçirme, veri sızdırma ve güvenilmez içerikle araç istismarı; savunmanın gerçekten tutup tutmadığını doğrular. |
| `reflect` | Önemli işten sonra retrospektif öz-denetim: doğrulanmamış varsayımlar, atlanan maddeler, doğru-yaklaşım-mı. Kod değil, bulgular. |
| `release` | Sürümleme ve CHANGELOG: Conventional Commits'ten türetilen SemVer, Keep a Changelog biçimi, etiketleme, ön-sürüm kapıları. |
| `security-scan` | Yığından bağımsız güvenlik denetimi: saldırı yüzeyini haritala, güvenilmez girdiyi tehlikeli çağrılara kadar izle, bağımlılık ve yapılandırma açıklarını çıkar. |
| `sonarqube-check` | SonarQube kalite kapısı (dilden bağımsız, yerel-öncelikli): 0 Bug/Zafiyet/Hotspot/Code Smell, 0 derleme uyarısı. Analyzer yoksa dile göre yerel/sunucusuz kurulup çalıştırılır. |
| `spec-planning` | Spec-öncelikli planlama: görev ayrıştırma, ölçülebilir kabul kriterleri, bağımlılık sırası, risk önceliği. |
| `systematic-debugging` | Bir hatayı düzeltmeden önce kök nedeni bul: yeniden üret, izole et, hipotez kurup test et, nedeni doğrula, sonra düzelt ve doğrula. Tahmine dayalı yamayı durdurur. |
| `teamboard` | Paylaşılan ekip panosu: bir işi başlamadan önce üstlen, devret, tamamla. Üstlenme bir git ref kilidi olduğu için aynı maddeyi iki kişi alamaz; bağımlılığı bitmemiş madde alınamaz, commit kapısı canlı üstlenme ister. |
| `testing` | Testin nasıl'ı: piramit, AAA, izolasyon, risk kapsamı, determinizm. |
| `threat-model` | Güvenlik denetimini taramadan ÖNCE kapsamla (false-positive kesici): varlıklar, giriş noktaları, güven sınırları ve 5-8 alana özgü saldırı sınıfını parse edilebilir THREAT_MODEL.md'ye çıkar. Tehdit patch'i aşar; zafiyet yalnızca kanıttır. security-scan'i besler. |
| `token-budget` | Bağlam/token disiplini: subagent izolasyonu, çıktı = özet, dosyaya-taşı, delege eşiği, yalın skill'ler. |
| `trace-scan` | İz taraması (§4.1/§4.2): commit'ten önce staged değişiklikleri ve mesajı AI izlerine (co-author trailer, footer, robot emoji, araç adları) ve vendor şablon adlarına karşı tarar. |
| `vps-deploy` | Bir VPS'e güvenli dağıtım: runtime saptama, ters proxy + SSL, atomik geçiş, önceki sürümü koru, dağıtım sonrası sağlık kapısı, hatada otomatik geri alma. |
| `worktree` | Riskli ya da paralel dosya-değiştiren işi bir git worktree'de izole et; ana ağacın commit'lenmemiş değişiklikleri asla ezilmez. Fan-out agent'lar, tek-kullanımlık deneyler için. |

<!-- SKILLS:END -->

</details>

---

## Nasıl çalışıyor

Tasarımı üç kural ayakta tutuyor.

1. **Agent ince bir tetikleyicidir.** *Kim* ve *ne zaman* der, fazlasını demez. Kısa kalır, çünkü tarifi her oturuma yükleniyor.
2. **Yöntemin tek kaynağı skill'dir.** İşin nasıl yapılacağı orada bir kez yazılır ve hiçbir agent'ın içine kopyalanmaz.
3. **Önemli olan kural yaptırıma dönüşür.** Uygulama araç seviyesinde durur: bir hook, bir izin, bir test vakası. Modelden hatırlaması istenmez.

Günlük hâli şöyle görünüyor:

<div align="center">
  <img src="assets/workflow-tr.svg" alt="Komut akışı: /plan-csk, uzman agent'lar, /review-csk, /ship-csk, /handoff-csk" width="820">
</div>

## Kural → yaptırım

Solda kural, sağda o kuralın geçilmesine izin vermeyen şey.

| Kural | Neyle uygulanıyor |
|:--|:--|
| Commit ve push her izin modunda onayınızı gerektirir | `guard-bash.sh`, yalnızca sizin cevaplayabileceğiniz bir istem açar. `bypassPermissions` altında kapalı düşer |
| Yıkıcı işlemler: `reset --hard`, `checkout -- .`, force push, `rm -rf`, `clean -f`, `--no-verify`, amend | `guard-bash.sh`, araç seviyesinde engeller |
| Uzaktan kod çalıştırma ve izin patlatma: `curl…\|bash`, herkese yazılabilir `chmod`, `dd of=` | `guard-bash.sh`, her modda sert engel |
| Bir yaptırımı devre dışı bırakmak — `core.hooksPath`'i saptırmak, bir hook'u düzenlemek veya silmek, ya da yaptırımların dayandığı disiplin metnini değiştirmek | `guard-bash.sh` (kabuk) + `guard-write.sh` (dosya araçları). İkisi de **çözülmüş** yolu eşleştirir: `..` parçaları, çift eğik çizgi, Windows ayraçları ve sembolik bağlı bir üst dizin, düz yazımla aynı sonucu verir |
| Hiçbir API anahtarı, token veya özel anahtar commit'e girmez | `pre-commit` sır taraması; her desen kendi test vakasını taşır |
| Hiçbir makineye özel yol veya iç ad commit'e girmez | `pre-commit` özel yol taraması: kendi `$HOME`'unuz kendiliğinden, ayrıca gitignore'lanmış `.private-terms.txt` |
| Hiçbir kimlik dosyası bağlama *okunmaz* — `~/.ssh/id_rsa`, `~/.aws/credentials`, `*.pem`, kubeconfig | `settings.json` okuma reddi + `guard-bash.sh` |
| Commit'te yapay zekâ imzası veya üçüncü parti şablon adı bulunmaz | `pre-commit` + `commit-msg` git hook'ları |
| Hiçbir derleme çıktısı, vendor ağacı veya aşırı büyük blob staged edilmez | `pre-commit` depo şişkinliği taraması |
| `.claude/` içinde beliren, denetlenmemiş bir skill ya da agent adıyla bildirilir ve tarayıcı hükmüyle sunulur | oturum başında `skill-trust.sh` |
| Aynı maddeye iki kişi başlayamaz — ikincisi **üstlenmeye çalıştığı anda**, saniyeyi bulmadan, tek satır yazılmadan reddedilir | `board.sh claim` (üstlenmenin kendisi bir git ref'ine push'tur; yalnız ileri sarım olduğu için eş zamanlı iki üstlenmeden tam olarak biri yerleşir). Ölçüldü: aynı madde için yarışan üç klon, on tur, her turda tek kazanan |
| Kimsenin bilmediği bir işe başlayamazsınız | Elinizde madde yokken `guard-write.sh` ilk dosya düzenlemesini engeller; `commit-msg` ise elinizde olmayan bir maddeyi anan commit'i geri çevirir |
| Sürekli açık bağlam yalın kalır | `smoke-test.sh` bileşen başına bayt bütçesi |
| Koşan bir oturum, güncellemeden sonra eski kurallara uymaya devam etmez | `context-usage.sh` sürüm karşılaştırması |

Her kural **iki** yönü için de vaka taşır: engellemesi gerekeni engellediği, ve komşusunu engellemediği — `chmod 755`, `rm -rf build`, `git checkout -- src/app.js`. Kanıtlanmamış bir yaptırım yaptırım değildir; rutin işte ateşleyen bir yaptırımın da etrafından dolaşılır.

Peki gerçekten bir şey değiştiriyor mu? Aynı istek hem Claude Starter Kit'li hem de çıplak bir projede koşturuldu ve her birinin diskte bıraktığına göre puanlandı. Sıkışık bir teslim tarihi ve makul bir gerekçe verildiğinde çıplak proje `uploads/` dizinini üç denemenin üçünde de herkese yazılabilir yaptı; kitli proje hiçbirinde yapmadı. İlginç olan şu: yaptırım hiç ateşlenmedi. Kitli taraf o komuta hiç uzanmadı, kendiliğinden vazgeçip kuralı gerekçe gösterdi. Acelesi olmayan işlerde ikisi birbirinden ayırt edilemiyor; ölçümler ve gerekçeleri [`evals/README.md`](evals/README.md) içinde yayımlanıyor.

Yaptırımlar kazaları durdurur, kararlı denemeleri değil. Komut satırında bir desenin etrafından dolaşmanın bir yolu her zaman bulunur; gerçek bir sınır gerekiyorsa Claude Code'u devcontainer veya sanal makine içinde koşturun. `/doctor-csk` böyle bir sınırınız olup olmadığını söyler.

**Bir yaptırımın ateşlendiğini görmek.** `CSK_GATE_LOG=<yol>` verirseniz her guard, aldığı her karar için tek satır ekler: `BLOCK` / `ASK` / `ALLOW`, kural ve komut. Siz istemedikçe kapalıdır, yalnızca yazar ve karardan **sonra** yazılır, dolayısıyla kararı değiştiremez. Bir şeyi yaptırımın mı durdurduğunu yoksa modelin o yola hiç girmediğini mi bilmeniz gerektiğinde işe yarar — ikisi geriye tıpatıp aynı izi bırakır.

---

## Kurulum

İki giriş noktası var: yeni proje için **`start.sh`**, hâlihazırda yürüyen bir proje için **`adopt.sh`**. Hangi kanaldan kurarsanız kurun, çalışan aynı iki komuttur.

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

**Windows:** Claude Starter Kit bash tabanlıdır. **Git Bash** içinde çalıştırın ([git-scm.com](https://git-scm.com)); WSL de alternatif olur. Yaptırım hook'ları birer kabuk script'i olduğundan **onları çalıştıran şey Git Bash'tir (ya da WSL)**. İkisi de yoksa Claude Code PowerShell aracını kendiliğinden açar, hook'lar çalışamaz ve ortada yaptırım kalmaz — bu yapılandırma yaptırım katmanınca desteklenmiyor, kurulum script'leri de orada zaten koşamaz. Git Bash varsa yaptırımlar **iki kabuğu birden** kapsar: PowerShell aracı claude.ai ve Console hesaplarında varsayılan olarak açıktır ve onun komutları da aynı kurallardan geçer (`Remove-Item -Recurse -Force`, `… | iex`, `Get-Content .env` ve diğerleri).

**Plugin sürümü** — iskele kurmadan, yalnızca agent'lar, skill'ler ve yaptırım hook'ları mevcut Claude Code'unuzun içine:

```bash
/plugin marketplace add byerlikaya/claude-starter-kit
/plugin install claude-starter-kit@byerlikaya
```

Kurulu bir plugin, siz yenisini istemedikçe kurduğunuz sürümde kalır; bu yüzden `claude plugin marketplace update byerlikaya` ardından `claude plugin update claude-starter-kit` çalıştırın ve uygulanması için yeniden başlatın.

### Yeni proje

```bash
bash start.sh [--dotnet|--generic] [-h]
```

İki adım: önce backend deseni, sonra hiçbir şey yazılmadan önce onaylayacağınız bir özet.

**Her kurulum aynı kurulumdur** — 12 agent'ın ve 40 skill'in tamamı, backend, web ve mobil (React Native/Expo) bir arada. API olarak başlayıp web istemcisi kazanan bir proje, ikisi için de baştan donanımlıdır.

| Kurulumda sorulan | Seçenekler | Neyi değiştirir |
|:--|:--|:--|
| Backend deseni | `--dotnet` · `--generic` | `devarch-module` skill'i ve DevArchitecture temeli |
| DevArch temeli — yalnızca `--dotnet` ile | onayla · atla | `./backend` iskelesinin kurulup kurulmayacağı |

**`--dotnet`**, üretime hazır [DevArchitecture](https://github.com/DevArchitecture/DevArchitecture) temelini (CQRS · IResult · AOP · auth) bir onay kapısının arkasından klonlar ve onu zaten bilen agent'ları kurar — böylece token'lar standart bir mimariyi yeniden üretmeye değil, sizin iş mantığınıza gider. Backend `./backend` altına yerleşir, yanında `./frontend` ayrılır ve çözüm dosyası projenizin adını alır.

**`--generic`** aynı uzmanı o desen olmadan kurar — Node, Go, Python ya da farklı bir desen kullanan bir .NET projesi için. Hiçbir şey DevArchitecture'ı dayatmaz: backend uzmanı, projenizin beyan ettiği desen skill'ini uygular.

### Mevcut proje

```bash
bash adopt.sh    # hedef projenin kök dizininde
```

<div align="center">
  <img src="assets/handover-tr.svg" alt="adopt.sh kiti nasıl devrediyor" width="900">
</div>

Claude Starter Kit, bir ekibin bir projeyi başka bir ekibe devrettiği gibi gelir: hiçbir şey kırılmaz, alınmış kararlar kaybolmaz ve gelen şey öylece durup beklemez.

Her değişiklik ayrı bir dala, **staged ama commit'lenmemiş** hâlde iner — eklenen ve değişen her dosya editörünüzün Source Control panelinde listelenir. Orada inceler, kabul için `git commit`, vazgeçmek için `reset` yaparsınız. `main` dalına dokunulmaz. Kitin agent'ları sizinkilerle çakışmadan yan yana kurulur, disiplin tek bir `@import` ile bağlanır, `settings.json` şema farkındalığıyla birleştirilir ve mevcut husky ya da lefthook zincirleri bir shim üzerinden çalışmaya devam eder. İş, kalıcı bir `docs/HANDOVER.md` ve bir ADR ile kapanır; böylece kararlar bir sohbet kaydında değil sürüm kontrolünde yaşar.

### Güncelleme

```bash
npx @byerlikaya/claude-starter-kit@latest update    # ya da oturum içinde /update-csk
```

<details open>
<summary>🔁&nbsp; <b>Güncelleme mekaniği: ne tazeleniyor, değişiklik nereye iniyor</b></summary>

Claude Starter Kit kurulum sırasında `.claude/kit.conf` dosyasına backend desenini ve hangi kurulum script'inin koştuğunu, ayrıca `.claude/VERSION` dosyasına sürümü yazar. Tazeleme **deseni korur**: `--dotnet` ile kurulmuş bir proje `devarch-module` ile kalır, bir Node deposuna o hiç verilmez. Damga eksikse güncelleyici deseni kurulu dosyalardan geri okur. Eksik her bileşen yerine konur ve eklenen her şey sessizce belirmek yerine **çıktıda adıyla anılır**.

| | Güncellemede |
|:--|:--|
| `.claude/` agent · skill · komut · hook · eval | yeni sürümden tazelenir |
| `.claude/DISCIPLINE.md` | **üzerine yazılır** — kite aittir, içinde kendinize ait hiçbir şey bırakmayın |
| `./CLAUDE.md` | hiç dokunulmaz — proje kurallarınız yazdığınız gibi kalır |
| `.claude/settings.json` | şema farkındalığıyla birleştirilir; kendi hook'larınız ve izinleriniz korunur |
| kendi agent ve skill'leriniz (`-csk` eki olmayanlar) | dokunulmaz |

Değişikliğin nereye ineceği bir tercih. İlk devir `kit-adopt-<zaman damgası>` adlı bir inceleme dalı açar. `.claude/` dizini gitignore'lanmış rutin bir güncelleme, bulunduğunuz dala uygulanır. `.claude/` **izleniyorsa** güncelleme size sorar. `--here` veya `--new-branch` ile zorlayabilir, `--yes` ile soruları atlayabilirsiniz. Hangisi olursa olsun değişiklik staged ve commit'siz kalır.

Oturum içinde **`/update-csk`** sürüm kontrolünü yapar, güncelleyiciyi koşturur, `/doctor-csk` ile doğrular ve ardından `/compact` önerir; böylece tazelenen disiplin aynı oturuma yüklenir. **`/doctor-csk`** ise canlı bir kurulumu istediğiniz an denetler — hook'lar çalıştırılabilir mi, `core.hooksPath` ayarlı mı, yaptırımlar bağlı mı, disiplin gerçekten import edilmiş mi — ve projenin kendisi için tavsiye niteliğinde bir hazırlık puanı basar.

Bir projenin `CLAUDE.md` dosyası disiplini import etmek yerine **satır içinde** taşıyorsa güncellemeler oraya ulaşamaz. Güncelleyici bunu fark eder, etkilenen satırları gösterir ve onları tek bir `@.claude/DISCIPLINE.md` import'uyla değiştirmeyi önerir — önce yedek alarak, sizin inceleyeceğiniz bir dalda. Reddederseniz hiçbir şeye dokunulmaz.

</details>

---

## Oturum ve token maliyeti

Oturumun ne kadar dolduğu **ölçülür, tahmin edilmez**: her turda okunan gerçek token sayısı, `/context`'in verdiği değerin aynısı. **%75**'te bir uyarı, **%90**'da bir tane daha — ikisi de turunuzu kesmez.

Sabit maliyet gizlenmiyor, yazıyor. Disiplin ile birlikte her agent ve skill tarifi her oturuma yüklenir: **~24 KB**, gerçek bir turda **~10 bin token** mertebesinde — tahmin değil, gerçek bir çalıştırmaya göre ölçülmüş. Eklediğiniz her skill, her oturuma **~100 token**'lık kalıcı bir vergi bindirir; bu yüzden bileşen başına bayt bütçesi bir yaptırım olarak uygulanır. Bütçeyi yükseltmek testte açık bir düzenleme ister.

**Neden daha az bileşen kurulmuyor?** Çünkü kazancı yok denecek kadar az. Kümenin tamamı tarif olarak **~3,3k token** tutar; dört UI skill'i ile frontend agent'ını dışarıda bırakmak **~400 token** kazandırır — 200k'lık bir pencerenin yaklaşık **%0,2**'si. Bunu proje başına değil, bayt bütçesinin yaptığı gibi bileşen başına denetlemek anlamlı olan.

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, yaptırım bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek bir istek doğru agent'a ya da skill'e ulaşıyor mu
bash .claude/eval/doctor.sh          # bu kurulum sağlıklı mı, proje hazır mı
bash .claude/eval/preflight.sh       # bu makinede hangi araçlar var, olmayanlar neyi zayıflatıyor
```

`preflight.sh` ayrıca `start.sh`, `adopt.sh` ve `doctor.sh` içinden de koşar. Bir araç eksik olduğunda kit kırılmaz,
kabiliyet düşürerek devam eder — `jq` yoksa `python`'a, o da yoksa saf bash'e; `sha256sum` yoksa `cksum`'a iner.
Doğru tasarım bu, ama aynı zamanda bir eksiğin kendini hiç duyurmamasının da sebebi. Preflight eksiği ve bedelini
adıyla söyler. Yalnızca rapor eder; makinenize hiçbir şey kurmaz ve hiçbir çalıştırmayı engellemez.

## Genişletme

Bir agent ya da skill eklerken `AGENT_TEMPLATE.md` sözleşmesine uyun: frontmatter (ad · tetikleyici ifadeleri içeren tarif · en az yetkiyle araçlar · model seviyesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl → Koordinasyon → Definition of Done → Çıktı → Eskalasyon → Örnek → Kısıtlar). `smoke-test.sh`, hiçbir yönlendirmenin ulaşmadığı bir bileşeni geri çevirir; böylece hiçbir şey uyur hâlde yayımlanmaz.

## Lisans ve kaynaklar

MIT — [LICENSE](LICENSE) dosyasına bakın.

- **[NIST SP 800-218 (SSDF)](https://csrc.nist.gov/pubs/sp/800/218/final)** PW.7 ve **[OpenSSF Scorecard](https://github.com/ossf/scorecard)** `Code-Review` denetimi — `code-review-csk`'nin yönetişim katmanı: incelemenin yapıldığı, bulguların kaydedildiği ve ele alındığı.
- **[Conventional Comments](https://conventionalcomments.org/)** — `code-review-csk`'nin yorum yazarken kullandığı etiket sözlüğü (CC BY 3.0).
- **[google/eng-practices](https://github.com/google/eng-practices)** — `code-review-csk`'deki inceleme öncelik sırası ve "kod sağlığı" çıtası, damıtılarak yeniden ifade edilmiş (CC-BY 3.0).
