# Kapılar

Önemli olan kural bir kapıya dönüşür. Uygulama araç seviyesinde durur: bir hook, bir izin, bir test vakası. Modelden hatırlaması istenmez.

| Bileşen | Adet | Nedir |
|:--|:--:|:--|
| **Ajan** | {{AGENT_COUNT}} | İnce tetikleyiciler: bir alanın *kimin* olduğu ve *ne zaman* devreye gireceği |
| **Skill** | {{SKILL_COUNT}} | Yöntemin kendisi; bir kez yazılır, ihtiyacı olan uygular |
| **Slash komutu** | {{COMMAND_COUNT}} | `/crew-brainstorm` · `/crew-plan` · `/crew-review` · `/crew-ship` · `/crew-handoff` · `/crew-update` · `/crew-doctor` · `/crew-board` · `/crew-gates` · `/crew-skill` · `/crew-studio` |
| **Hook** | 12 | Kapılar, ayrıca oturum ölçümü ve yönlendirme |
| **Disiplin** | 1 | İlkeler, akış, Definition of Done, yasaklar. `CLAUDE.md`'niz bu dosyayı import ediyor |

## 12 hook'un tamamı

| Hook | Görevi |
|:--|:--|
| `route-hint.sh` | Her isteğin yanına o işin sahibi ajanı yazar; uzmanlar siz istemeden devreye girer |
| `guard-bash.sh` | Araç seviyesinde komut kapısı: commit/push onayı, commit öncesi inceleme, yıkıcı işlemler, uzaktan kod çalıştırma, hook kurcalama |
| `guard-write.sh` | Aynı korumanın Write/Edit tarafı. Sessizce silinebilen bir kapı, kapı değildir. Hedef yolu eşleştirmeden önce sadeleştirir, böylece bir kapı dosyasına farklı bir yazımla ulaşılamaz. |
| `guard-commit-scan.sh` | Gerçek iz ve sır tarayıcılarını `PreToolUse` üzerinden koşturur; böylece `core.hooksPath` ayarlanamayan yerlerde de commit kapısı çalışır |
| `context-usage.sh` | Transcript'ten gerçek token sayısını okur ve her tura enjekte eder |
| `session-guard.sh` | Bağlam doluluğu %{{FILL_WARN}}'i ve %{{FILL_ALERT}}'ı geçtiğinde birer kez uyarır, turu asla kesmez |
| `session-rehydrate.sh` | `/compact` veya `/clear` sonrasında devir notunu yeniden önünüze getirir |
| `skill-trust.sh` | Crewforth'un getirmediği ve sizin de kabul etmediğiniz her skill ya da ajanı adıyla bildirir |
| `session-stats.sh` | Oturumun gerçekte ne yaptığını raporlar: patlayan araç döngüleri, tekrarlanan istekler, kesintiler. `reflect` ve `handoff` bunu okur, böylece geri dönüş hatırlamaya değil kayda dayanır |
| `session-update-check.sh` | Yeni bir sürüm yayımlandığında, oturum açılırken bir kez güncellenip güncellenmeyeceğini sorar; her sürüm onu getirecek kanala göre karşılaştırılır. Sorgu ayrık koşar ve en fazla günde bir kez yapılır, dolayısıyla çevrimdışı ya da proxy arkasındaki bir makinede oturum açılışı hiçbir şey ödemez; `CREW_NO_UPDATE_CHECK=1` kapatır |
| `board.sh` | Ekip panosunun motoru: bir maddeyi üstlenir, devreder, tamamlar. Depoda `/crew-board init` çalıştırılmadıkça kapalıdır |
| `board-sync.sh` | Ekibin pano durumunu oturuma taşır. Oturum açılışında yerel önbelleği okur, tazelemeyi arka planda yapar; böylece erişilemeyen bir uzak depo açılışa maliyet bindirmez. `CREW_NO_BOARD=1` kapatır |

İki git hook'u (`pre-commit` ve `commit-msg`) iz, sır, depo şişkinliği ve özel yol taramalarını koşturur. Sonuncusu şunun için var: yalnızca sizin makinenizde bulunan bir yol paylaşılan depoya yazılarak değil, yapıştırılarak sızar. Kendi `$HOME`'unuzu kendiliğinden engeller; yalnızca sizin tanıyabileceğiniz iç proje, müşteri ve sunucu adları ise gitignore'lanmış `.private-terms.txt` dosyasından gelir (`.private-allowlist.txt` kaçış kapısıdır). `commit-msg` ayrıca pano üstlenme kapısını tutar: panosu olan bir depoda commit ya elinizdeki bir maddeyi anmalıdır (`[#3]`) ya da maddesiz olduğunu beyan etmelidir (`[chore]`). Plugin sürümü, `skill-trust.sh` dışında bunların hepsini getirir; o hook neyin Crewforth'a ait olduğunu bir kurulum script'inin yazdığı `kit-manifest.txt`'ten okur ve plugin böyle bir dosya oluşturmaz.

## Kural → kapı

Solda kural, sağda o kuralın geçilmesine izin vermeyen şey.

| Kural | Neyle uygulanıyor |
|:--|:--|
| Commit ve push her izin modunda onayınızı gerektirir; stage etmek ve dal açmak serbesttir | `guard-bash.sh`, yalnızca sizin cevaplayabileceğiniz bir istem açar. `bypassPermissions` altında kapalı düşer |
| Bir commit, **tam olarak kendi diff'i** için temiz bir inceleme gerektirir | `guard-bash.sh`, `crew-review-agent` değişikliği temize çıkarırken kaydettiği değerlerle staged diff'in git nesne kimliğini ve incelemenin yapıldığı `HEAD`'i karşılaştırır. Başka bir diff'in — ya da aynı diff'in başka bir taban üzerindeki — incelemesi sayılmaz; boyut istisnası yoktur |
| Yıkıcı işlemler: `reset --hard`, `checkout -- .`, force push, `rm -rf`, `clean -f`, `--no-verify`, amend | `guard-bash.sh`, araç seviyesinde engeller |
| Uzaktan kod çalıştırma ve izin patlatma: `curl…\|bash`, herkese yazılabilir `chmod`, `dd of=` | `guard-bash.sh`, her modda sert engel |
| Bir kapıyı devre dışı bırakmak: `core.hooksPath`'i saptırmak, bir hook'u düzenlemek veya silmek, ya da kapıların dayandığı disiplin metnini değiştirmek | `guard-bash.sh` (kabuk) + `guard-write.sh` (dosya araçları). İkisi de **çözülmüş** yolu eşleştirir: `..` parçaları, çift eğik çizgi, Windows ayraçları ve sembolik bağlı bir üst dizin, düz yazımla aynı sonucu verir |
| Hiçbir API anahtarı, token veya özel anahtar commit'e girmez | `pre-commit` sır taraması; her desen kendi test vakasını taşır |
| Hiçbir makineye özel yol veya iç ad commit'e girmez | `pre-commit` özel yol taraması: kendi `$HOME`'unuz kendiliğinden, ayrıca gitignore'lanmış `.private-terms.txt` |
| Hiçbir kimlik dosyası bağlama *okunmaz*: `~/.ssh/id_rsa`, `~/.aws/credentials`, `*.pem`, kubeconfig | `settings.json` okuma reddi + `guard-bash.sh` |
| Commit'te yapay zekâ imzası veya üçüncü parti şablon adı bulunmaz | `pre-commit` + `commit-msg` git hook'ları |
| Hiçbir derleme çıktısı, vendor ağacı veya aşırı büyük blob staged edilmez | `pre-commit` depo şişkinliği taraması |
| Hiçbir commit kalite çıtasını sessizce düşürmez: tetiklendiği yerde susturulan bir denetleyici, atlanan ya da silinen bir test, kalan bir testten çıkarılan assertion'lar, işin yerinde duran bir stub ya da boş `catch` | `pre-commit` çıta koruması, desteklenen yığınlarda. Üretilmiş dosyalar ve dokümantasyon muaf; gerçek bir istisna, aynı commit'te incelemenin gördüğü bir `.floor-allowlist.txt` satırıdır |
| `.claude/` içinde beliren, denetlenmemiş bir skill ya da ajan adıyla bildirilir ve tarayıcı hükmüyle sunulur | oturum başında `skill-trust.sh` |
| Sürekli açık bağlam yalın kalır | `smoke-test.sh` bileşen başına bayt bütçesi |
| Koşan bir oturum, güncellemeden sonra eski kurallara uymaya devam etmez | `context-usage.sh` sürüm karşılaştırması |

Her kural **iki** yönü için de vaka taşır: engellemesi gerekeni engellediği ve komşusunu (`chmod 755`, `rm -rf build`, `git checkout -- src/app.js`) engellemediği. Kanıtlanmamış bir kapı kapı değildir; rutin işte ateşleyen bir kapının da etrafından dolaşılır.

Kapılar kazaları durdurur, kararlı denemeleri değil. Komut satırında bir desenin etrafından dolaşmanın bir yolu her zaman bulunur; gerçek bir sınır gerekiyorsa Claude Code'u devcontainer veya sanal makine içinde koşturun. `/crew-doctor` böyle bir sınırınız olup olmadığını söyler.

## Bir kapının ateşlendiğini görmek

Bash guard'ı her blok, onay istemi ve `CLAUDE_GIT_OK` ön onayı için (`BLOCK` / `ASK` / `ALLOW`), kapı dosyası yazma guard'ı da her blok için `.claude/gate-log.tsv` dosyasına bölüm ve kuralla birlikte bir satır ekler; komut yalnızca `CREW_GATE_LOG_CMD=1` verilirse yazılır. Projenin `.claude/` dizini varsa ve dosya git'te yok sayılıyorsa ya da proje bir repo değilse varsayılan olarak açıktır; `CREW_GATE_LOG=<yol>` kaydı başka yere gönderir, `/dev/null` kapatır. Commit taraması ve pano kapısı satır yazmadan reddeder. Yalnızca yazar ve karardan **sonra** yazılır, dolayısıyla kararı değiştiremez. Bir şeyi kapının mı durdurduğunu yoksa modelin o yola hiç girmediğini mi bilmeniz gerektiğinde işe yarar, çünkü ikisi geriye tıpatıp aynı izi bırakır.
