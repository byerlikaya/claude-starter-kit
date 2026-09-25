<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo.svg">
  <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.svg">
  <img src="assets/logo.svg" alt="Crewforth" width="420">
</picture>

![Sürüm](https://img.shields.io/badge/version-3.0.0-2563eb?style=flat-square)
![Lisans](https://img.shields.io/badge/license-MIT-16a34a?style=flat-square)
![Ajan](https://img.shields.io/badge/agents-12-f59e0b?style=flat-square)
![Skill](https://img.shields.io/badge/skills-40-f59e0b?style=flat-square)

[🇬🇧 English](README.md) · 🇹🇷 Türkçe

**Crewforth, Claude Code için mühendislik ekibinizdir.**

Claude Code'a subagent'lar, skill'ler, slash komutları ve hook'lar ekler: her biri bir alanın sahibi olan 12 uzman ajan,<br>
yöntemi taşıyan 40 skill, günlük akış için 11 slash komutu ve önemli kuralları uygulayan hook'lar.

<img src="assets/studio-flow.gif" alt="Studio, ajanlar doğup çalışıp rapor verirken delegasyonu çiziyor" width="880">

</div>

## Neden Crewforth

- **İş, sahibi olan uzmana gider.** Belirsiz bir istek kod yazılmadan önce planlanır, sunucu işi `crew-backend-expert`'e gider, riskli bir değişiklik de `crew-security-expert` incelemeden kapanmaz. Bir yönlendirme hook'u, isteğinizin yanına işin sahibini yazar.
- **Önemli kurallar akılda tutulmaz, kapılarla uygulanır.** Yıkıcı bir komut çalışmadan reddedilir, commit onayınızı bekler, sızmış bir anahtar geçmişe girmez.
- **Her sonuç ölçülür ve yayımlanır; tutmayanlar da.** Aynı istek Crewforth ile ve onsuz koşturulur, ikisi de diskte bıraktığına göre puanlanır. [Nasıl ölçüyoruz](#nasıl-ölçüyoruz) bölümüne bakın.

## Hızlı başlangıç

```bash
npx crewforth init              # yeni proje kurar
npx crewforth add <agent|skill> # yalnız bir ajan ya da skill ekler
npx crewforth studio            # Studio panelini açar
```

Hiçbir şey yazılmadan önce bir özeti onaylarsınız; `add` tam kurulum yapmadan `./.claude` içine kopyalar. Hâlihazırda çalışılan bir depoda `npx crewforth adopt` her şeyi ayrı bir dala, staged ve commit'lenmemiş olarak getirir; `main` dalına dokunulmaz. Ardından Claude Code'da `/crew-doctor` çalıştırıp kurulumu doğrulayın.

## Bir oturum nasıl akar

<div align="center">
  <img src="assets/workflow-tr.svg" alt="Komut akışı: /crew-plan, uzman ajanlar, /crew-review, /crew-ship, /crew-handoff" width="820">
</div>

| Adım | Komut | Ne olur |
|:--|:--|:--|
| Planla | `/crew-plan` | `crew-planner` isteği kabul kriterli görevlere böler |
| Yap | (yönlendirilir) | işin sahibi ajan değişikliği yazar ve skill'lerini uygular |
| İncele | `/crew-review` | güvenlik, gizlilik, performans ve test denetimleri paralel koşar |
| Teslim et | `/crew-ship` | `crew-review-agent` temiz incelemeyi kaydeder; `crew-commit-agent` commit'i önerir ve onayınızı bekler |
| Devret | `/crew-handoff` | `handoff` durumu bir sonraki oturum için yazar |

Toplam **11 slash komutu**: `/crew-plan`, `/crew-review`, `/crew-ship`, `/crew-handoff`, `/crew-brainstorm`, `/crew-update`, `/crew-doctor`, `/crew-board`, `/crew-gates`, `/crew-skill`, `/crew-studio`.

## Ajanlar

**12 uzman ajan** var; her biri işin kime ait olduğunu ve ne zaman devreye girdiğini söyler. Yöntem skill'lerde durur: [crewforth.com/tr/skills](https://crewforth.com/tr/skills).

| Ajan | Sahip olduğu alan |
|:--|:--|
| `crew-planner` | istek belirsizken kapsam ve kabul kriterleri |
| `crew-backend-expert` | sunucu, API ve iş mantığı; yığın fark etmez |
| `crew-database-expert` | şema, migration, indeks ve önbellek |
| `crew-frontend-expert` | web ve mobilde arayüz, bileşen ve istemci işi |
| `crew-devops-expert` | dağıtım, CI hattı ve olay müdahalesi |
| `crew-security-expert` | auth, injection ve sırlar; güvenlik açısından kritik değişikliklerde zorunlu |
| `crew-privacy-agent` | KVKK, GDPR ve projenin bildirdiği rejimler altında kişisel veri |
| `crew-test-expert` | test, kapsam ve regresyon |
| `crew-performance-expert` | sıcak yol, sorgu, render ve payload |
| `crew-review-agent` | bir commit'in ihtiyaç duyduğu kod sağlığı incelemesi |
| `crew-commit-agent` | onayınızı bekleyen commit önerisi |
| `crew-session-manager` | oturum doluluğu ve devir |

## Kapılar

| Kural | Neyle uygulanır |
|:--|:--|
| Commit ve push her izin modunda onayınızı ister | `guard-bash.sh` |
| Bir commit, tam olarak kendi diff'i için temiz bir inceleme ister | `guard-bash.sh` ve `crew-review-agent`'ın yazdığı kayıt |
| Yıkıcı komutlar (`reset --hard`, force push, `rm -rf`, `--no-verify`) reddedilir | `guard-bash.sh` |
| Yapay zekâ imzası commit'e girmez | `pre-commit` ve `commit-msg` git hook'ları |
| API anahtarı, token ya da özel anahtar commit'e girmez | `pre-commit` sır taraması |
| Bir kapıyı kapatmak için kapı dosyası düzenlenemez ya da silinemez | `guard-write.sh` |

Bütün hook'lar ve kurallar: [crewforth.com/tr/gates](https://crewforth.com/tr/gates). Kapılar kazaları durdurur, kararlı denemeleri değil; kesin bir sınır için devcontainer ya da sanal makine kullanın.

## Studio

Studio, delegasyonu olurken çizen yerel bir panel: her ajan bir düğüm, düğüm de o ajanın ne yaptığını, ne harcadığını ve ne bildirdiğini gösterir. Makinedeki bütün Claude Code oturumlarını okur, `/crew-studio` ya da `npx crewforth studio` ile açılır ve yalnızca `127.0.0.1`'e bağlanır. Ayrıntılar: [crewforth.com/tr/studio](https://crewforth.com/tr/studio).

## Kurulum ve güncelleme

| Kanal | Komut |
|:--|:--|
| npx | yeni proje için `npx crewforth init`, mevcut proje için `npx crewforth adopt` |
| Claude Code plugin | `/plugin marketplace add Crewforth/crewforth`, ardından `/plugin install crewforth@crewforth` |
| Node yoksa | GitHub release arşivi, bkz. [crewforth.com/tr/install](https://crewforth.com/tr/install) |

**Gereksinimler:** Claude Code 2.1.214 veya sonrası (2.1.282 ile test edildi) ve `npx` için Node.js 20 veya sonrası (22 ya da 24 önerilir).

**2.x plugin'inden mi geliyorsunuz?** Plugin'in ve marketplace'in adı değişti, bu yüzden 2.x kurulumu 3.0'a kendiliğinden güncellenmez. Bir kez geçin:

```
/plugin uninstall claude-starter-kit
/plugin marketplace add Crewforth/crewforth
/plugin install crewforth@crewforth
```

Yeni bir sürüm yayımlandığında Claude, oturumun başında bir kez şimdi mi, sonra mı güncelleneceğini ya da o sürümün atlanıp atlanmayacağını sorar; kendiliğinden asla güncellemez. `/crew-update` güncellemeyi çalıştırır ve neyin değiştiğini söyler; `./CLAUDE.md` dosyanıza dokunulmaz. Windows'ta Git Bash kullanın. Bütün seçenekler: [crewforth.com/tr/install](https://crewforth.com/tr/install).

## Nasıl ölçüyoruz

Aynı isteği Crewforth kurulu bir projede ve çıplak bir projede koşturuyor, ikisini de diskte bıraktığına göre puanlıyoruz. Bir sonucun sağlaması gereken kural koşudan önce yazılıyor. Her sonuç gerekçesiyle yayımlanıyor, o kuralın tutmadığı sonuçlar da: [`evals/README.md`](evals/README.md).

## Katkı, lisans ve bağlantılar

Issue ve pull request'ler [github.com/Crewforth/crewforth](https://github.com/Crewforth/crewforth) adresinde. Yeni bir ajan ya da skill `kit/AGENT_TEMPLATE.md` sözleşmesine uyar ve `bash packaging/verify.sh` geçmelidir.

MIT, [LICENSE](LICENSE) dosyasına bakın. `crew-code-review`; [google/eng-practices](https://github.com/google/eng-practices) ve [Conventional Comments](https://conventionalcomments.org/) (ikisi de CC BY 3.0) ile [NIST SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final) ve [OpenSSF Scorecard](https://github.com/ossf/scorecard) `Code-Review` denetimine dayanır.

Belgeler: [crewforth.com/tr](https://crewforth.com/tr) · Oturum ve maliyet: [crewforth.com/tr/sessions-and-cost](https://crewforth.com/tr/sessions-and-cost) · Doğrulama: [crewforth.com/tr/verification](https://crewforth.com/tr/verification) · Genişletme: [crewforth.com/tr/extending](https://crewforth.com/tr/extending)
