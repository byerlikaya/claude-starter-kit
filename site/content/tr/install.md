# Kurulum

İki giriş noktası var: yeni proje için **`start.sh`**, hâlihazırda yürüyen bir proje için **`adopt.sh`**. Hangi kanaldan kurarsanız kurun, çalışan aynı iki komuttur.

```bash
# npx: kurulum gerektirmez
npx crewforth init                  # yeni proje
npx crewforth adopt                 # mevcut proje
npx crewforth@latest update         # mevcut kurulumu tazele

# Homebrew
brew install byerlikaya/tap/crewforth
crewforth init              # yeni proje
crewforth adopt             # mevcut proje

# Sürüm arşivi: paket yöneticisi olmadan
gh release download --repo Crewforth/crewforth -p '*.tgz' && tar xzf crewforth-*.tgz
bash start.sh               # yeni proje
bash adopt.sh               # mevcut proje (tazelemek için tekrar çalıştırın)
```

**Windows:** Crewforth bash tabanlıdır. **Git Bash** içinde çalıştırın ([git-scm.com](https://git-scm.com)); WSL de alternatif olur. Kapı hook'ları birer kabuk script'i olduğundan **onları çalıştıran şey Git Bash'tir (ya da WSL)**. İkisi de yoksa Claude Code PowerShell aracını kendiliğinden açar, hook'lar çalışamaz ve ortada kapı kalmaz. Bu yapılandırma kapı katmanınca desteklenmiyor; kurulum script'leri de orada zaten koşamaz. Git Bash varsa kapılar **iki kabuğu birden** kapsar: PowerShell aracı claude.ai ve Console hesaplarında varsayılan olarak açıktır ve onun komutları da aynı kurallardan geçer (`Remove-Item -Recurse -Force`, `… | iex`, `Get-Content .env` ve diğerleri).

**Plugin sürümü:** iskele kurmadan; ajanlar, skill'ler, komutlar, kapı hook'ları ve Studio, mevcut Claude Code'unuzun içine:

```bash
/plugin marketplace add Crewforth/crewforth
/plugin install crewforth@crewforth
```

Kurulu bir plugin, siz yenisini istemedikçe kurduğunuz sürümde kalır; bu yüzden `claude plugin marketplace update crewforth` ardından `claude plugin update crewforth` çalıştırın ve uygulanması için yeniden başlatın.

## Yeni proje

```bash
bash start.sh [--private|--shared] [--lang tr|en] [--yes] [--version] [-h]
```

Sihirbaz önce hangi dilde konuşacağını sorar (Türkçe ya da İngilizce), ardından kurulumu kimin kullanacağını; sonunda hiçbir şey yazılmadan önce onaylayacağınız bir özet gösterir. Seçtiğiniz dil tüm sorulara ve mesajlara uygulanır; kurulan dosyalar İngilizce kalır.

**Her kurulum aynı ekibi getiriyor:** 12 ajanın ve 40 skill'in tamamı. Backend, web ve mobil (React Native/Expo) bir arada geliyor. API olarak başlayıp web istemcisi kazanan bir proje, ikisi için de baştan donanımlıdır.

| Kurulumda sorulan | Seçenekler | Neyi değiştirir |
|:--|:--|:--|
| Dil | `--lang tr` · `--lang en` | kurulumun ekrana yazdıkları — diske yazdığı hiçbir şey değil |
| Kimin için | `--private` · `--shared` | `.claude/` ve `CLAUDE.md`'nin gitignore'a mı gireceği, yoksa ekip için commit mi edileceği |

**Backend yığından bağımsızdır.** Kurulum yığın sormaz. İlk backend işinde `backend-architecture` skill'i yığını çözer: önce isteğiniz, sonra `CLAUDE.md`'deki `## Stack` bölümü, sonra deponun manifest dosyaları (`package.json`, `go.mod`, `pyproject.toml`, `*.csproj`, …); yalnız boş bir depoda, her birinde önerilen bir cevap ve "Decide for me" seçeneği olan en fazla dört çoktan seçmeli soru sorar. Cevap `## Stack` bölümüne yazılır ve bir ADR ile kaydedilir; yani bir kez sorulur. Node, Go, Python, .NET ve JVM eşit desteklenir; `.claude/skills/` altına kendi desen skill'ini koyan projede o uygulanır.

## Mevcut proje

```bash
bash adopt.sh    # hedef projenin kök dizininde
```

<div align="center">
  <img src="../../../assets/handover-tr.svg" alt="adopt.sh Crewforth'u nasıl devrediyor" width="900">
</div>

Crewforth, bir ekibin bir projeyi başka bir ekibe devrettiği gibi gelir: hiçbir şey kırılmaz, alınmış kararlar kaybolmaz ve gelen şey öylece durup beklemez.

Her değişiklik ayrı bir dala, **staged ama commit'lenmemiş** hâlde iner; eklenen ve değişen her dosya editörünüzün Source Control panelinde listelenir. Orada inceler, kabul için `git commit`, vazgeçmek için `reset` yaparsınız. `main` dalına dokunulmaz. Crewforth'un ajanları sizinkilerle çakışmadan yan yana kurulur, disiplin tek bir `@import` ile bağlanır, `settings.json` şema farkındalığıyla birleştirilir ve mevcut husky ya da lefthook zincirleri bir shim üzerinden çalışmaya devam eder. İş, kalıcı bir `docs/HANDOVER.md` ve bir ADR ile kapanır; böylece kararlar bir sohbet kaydında değil sürüm kontrolünde yaşar.

## Güncelleme

```bash
npx crewforth@latest update    # ya da oturum içinde /crew-update
```

Yeni bir sürüm yayımlandığında Claude, oturumun başında bir kez şimdi mi, sonra mı güncelleneceğini ya da o sürümün atlanıp atlanmayacağını sorar. Kendiliğinden asla güncellemez.

Crewforth kurulum sırasında `.claude/kit.conf` dosyasına hangi kurulum script'inin koştuğunu, ayrıca `.claude/VERSION` dosyasına sürümü yazar. 3.0'dan önce .NET deseniyle kurulmuş bir proje **`cqrs-aop-module` skill'ini korur**: backend uzmanının uygulamaya devam ettiği bir proje skill'i olarak kalır; güncelleme bunu söyler ve asla silmez. Eksik her bileşen yerine konur ve eklenen her şey sessizce belirmek yerine **çıktıda adıyla anılır**.

| | Güncellemede |
|:--|:--|
| `.claude/` ajan · skill · komut · hook · eval · studio | yeni sürümden tazelenir |
| `.claude/DISCIPLINE.md` | **üzerine yazılır**; Crewforth'a aittir, içinde kendinize ait hiçbir şey bırakmayın |
| `./CLAUDE.md` | hiç dokunulmaz; proje kurallarınız yazdığınız gibi kalır |
| `.claude/settings.json` | şema farkındalığıyla birleştirilir; kendi hook'larınız ve izinleriniz korunur |
| kendi ajan ve skill'leriniz (`crew-` öneki olmayanlar) | dokunulmaz |

Değişikliğin nereye ineceği bir tercih. İlk devir `kit-adopt-<zaman damgası>` adlı bir inceleme dalı açar. `.claude/` dizini gitignore'lanmış rutin bir güncelleme, bulunduğunuz dala uygulanır. `.claude/` **izleniyorsa** güncelleme size sorar. `--here` veya `--new-branch` ile zorlayabilir, `--yes` ile soruları atlayabilirsiniz. Hangisi olursa olsun değişiklik staged ve commit'siz kalır. İzlenen bir `.claude/` ayrıca `.gitattributes`'a eol pinleri alır; böylece git'i `core.autocrlf=true` olan — yani Git for Windows varsayılanındaki — bir takım arkadaşında hook'lar LF kalır. Git Bash CRLF bir hook'u yine de koşturur (ölçüldü); pin, koşturmayan bir bash için (belgelenmiş vaka WSL) ve çalışma ağacının commit'lenenle birebir aynı kalması için.

Oturum içinde **`/crew-update`** sürüm kontrolünü yapar, güncelleyiciyi koşturur, `/crew-doctor` ile doğrular ve ardından `/clear` önerir; böylece tazelenen disiplin yeni bir oturumda yüklenir. **`/crew-doctor`** ise canlı bir kurulumu istediğiniz an denetler (hook'lar çalıştırılabilir mi, `core.hooksPath` ayarlı mı, kapılar bağlı mı, disiplin gerçekten import edilmiş mi) ve projenin kendisi için tavsiye niteliğinde bir hazırlık puanı basar.

Bir projenin `CLAUDE.md` dosyası disiplini import etmek yerine **satır içinde** taşıyorsa güncellemeler oraya ulaşamaz. Güncelleyici bunu fark eder, etkilenen satırları gösterir ve onları tek bir `@.claude/DISCIPLINE.md` import'uyla değiştirmeyi önerir; önce yedek alır, işi de sizin inceleyeceğiniz bir dalda yapar. Reddederseniz hiçbir şeye dokunulmaz.
