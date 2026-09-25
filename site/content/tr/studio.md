# Studio

Üç kademe derine inen bir delegasyon, terminalde çoktan kaybettiğiniz bir kaydırma geçmişidir. **Crewforth Studio** onu çizen yerel bir panel: tuvalde her ajana bir düğüm düşüyor; düğüm, ajan doğduğu anda beliriyor ve o an ne yaptığını, en son hangi aracı kullandığını, ne harcadığını ve geri ne bildirdiğini üstünde taşıyor.

Panel `~/.claude/projects` dizinini okuyor; Claude Code bu makinedeki bütün oturumları orada tutuyor. Dolayısıyla çalışan tek bir panel hepsini birden görüyor: projede Crewforth kurulu olsun ya da olmasın, panelin o projenin içinde başlatılmış olması da gerekmiyor.

```bash
/crew-studio                                       # Crewforth kurulu her projede
node .claude/studio/server/index.js --open        # aynısı, slash seçicisi olmadan
npx crewforth studio                              # hiçbir şey kurmadan
```

| Panelde ne var | Neye dayanıyor |
|:--|:--|
| Herhangi bir oturumun canlı delegasyon grafiği | diskteki transcript ağacı; 700 ms'de bir boyut imzası okunuyor, imza değiştiyse ağaç yeniden kuruluyor |
| Panelin başlattığı oturumlar, sohbet penceresinden sürülüyor | stream-json biçiminde bir `claude -p`; komut da cevap da alt sürecin stdin ve stdout'undan geçiyor |
| O oturumlardaki her araç çağrısı siz cevaplayana kadar bekletiliyor | panelin kendi ayar dosyası üzerinden enjekte edilen ve `*` ile eşleşen bir `PreToolUse` hook'u. Harness'ın 90 sn'sine karşılık 45 sn'de karar veriyor; **sessizlik ret demek**, yani kapalı bir panel izin yerine geçmiyor |
| Oturumu kopyalamak yerine gerçekten sürdürmek | oturumu tutan bir süreç yoksa çıplak `--resume`; oturumun kimliği korunuyor, yazılanlar aynı transcript'in sonuna ekleniyor. Tutan bir süreç varsa fork ediliyor, çünkü tek bir transcript'e iki yazar onu bozar |
| Kapı kaydı, oturum istatistikleri ve pano | Crewforth'un mevcut script'leri; hiçbiri yeniden hesaplanmıyor, hepsi okunuyor. Kapı kaydı satırları "zaman damgası taşımıyor" diye etiketleniyor, çünkü o biçimde zaman damgası yok |

<div align="center">
  <img src="../../../assets/studio-panels.gif" alt="Panelde gezinme: proje listesinden bir oturum açılıyor, bir ajanın raporu ve araç zaman çizelgesi grafiğin yanında açılıyor, düşen ajana atlanıyor ve oturumun konuşması sağda açılıyor" width="900">
  <br><sub>Aynı panel, kullanılırken: bir oturum açılıyor, bir ajanın ne bildirdiği okunuyor, düşen ajana atlanıyor, arkasındaki konuşma açılıyor.</sub>
</div>

**Studio, Crewforth ile birlikte kuruluyor.** `start.sh` ve `adopt.sh` `.claude/` altında altı dizin açıyor, Studio da altıncısı. Yani Crewforth kurulu her projede **`/crew-studio`** ile açıyorsunuz; slash seçicisi olmadan `node .claude/studio/server/index.js --open`. Hiç npm bağımlılığı yok, Node 18+ istiyor, yalnızca `127.0.0.1`'e bağlanıyor ve her API yolunda o koşuya özel bir token arıyor. **Makinede Node yoksa Crewforth onu kendi getiriyor.** `.claude/studio/ensure-node.sh --plan` ne indireceğini olduğu gibi gösteriyor: nodejs.org'daki güncel LTS, yayımlanmış SHA-256'ya karşı doğrulanıyor ve `~/.claude/studio-runtime` altına açılıyor. Siz evet demeden hiçbir şey kurmuyor. Yönetici hakkı istemiyor, paket yöneticisine dokunmuyor, PATH'i değiştirmiyor; o tek dizini silmek yaptığı her şeyi geri alıyor.

| Kanal | Studio |
|:--|:--|
| `npx crewforth` · Homebrew · sürüm arşivi · git clone | `.claude/studio/` altına kuruluyor |
| Claude Code plugin | plugin'in içinde geliyor; `/crewforth:crew-studio` ile açılıyor (plugin komutları ad alanlı) |

Dört kanal da paneli taşıyor. Tek bir komut dosyası iki edisyona birden hizmet ediyor: Claude Code plugin'in kendi kurulum yolunu o metnin içine yazıyor, dolayısıyla panel gerçekte neredeyse orada bulunuyor. Davranış iki edisyonda aynı; tek dürüst boşluk şu: panelin telemetri sekmeleri açıldığı projeyi okuyor ve plugin kurulumu projeye Crewforth dosyası koymuyor. O yüzden gates, stats ve board sekmeleri yanıltıcı bir sıfır yerine "ölçülmedi" diyor, sebebiyle birlikte. Gates sekmesi yine de plugin'in kapılarının o projenin `.claude/gate-log.tsv` dosyasına kaydettiği kapı kararlarını listeliyor.

Panel `~/.claude/projects` dizinini okuyor; orada bu makinedeki **her** Claude Code oturumu duruyor. Proje kökünden başlatmak yalnızca hangi projeyle açılacağını belirliyor.

<div align="center">
  <img src="../../../assets/studio-graph.png" alt="Tek tuvalde on iki ajan ve bir workflow konteyneri; her kart durumunu, araç sayısını, token ve süresini taşıyor, düşen ajan kırmızıyla çerçeveli" width="900">
  <br><sub>Hangi ajan ne yapıyor, ne harcadı, hangisi düştü. Düşeni aramak gerekmiyor; ⚠ düğmesi doğrudan ona götürüyor.</sub>
</div>
