---
name: security-scan
description: |
  Yığın-bağımsız güvenlik denetimi. Saldırı yüzeyini haritalar, güvenilmeyen girdiyi tehlikeli
  çağrılara kadar izler, bağımlılık ve yapılandırma açıklarını çıkarır; önem-sıralı, düzeltmeli rapor verir.
  Trigger phrases: "security scan", "güvenlik taraması", "OWASP check", "zafiyet tara", "güvenlik açığı bul", "güvenlik denetimi"
---

# Güvenlik Taraması

Bir güvenlik açığının çekirdeği tek cümlede toplanır: **güvenilmeyen bir girdi, yeterince
denetlenmeden tehlikeli bir işleme ulaşıyor.** Bu skill de o cümlenin peşine düşer — önce
girdinin nereden geldiğini, sonra nereye aktığını, arada hangi kapının olması gerektiğini arar.
Yığından bağımsızdır: dil/framework ne olursa olsun aynı mantık işler; güncel araç ve kalıp
gerektiğinde web araması yapılır.

> **Kit uyarlaması (lokal, .claude/):** `security-expert-cck` bunu uygular; bulgular önem sırasına
> göre **review-agent-cck**'a taşınır. Varsayılan stack'te (.NET/PostgreSQL) de geçerlidir. Otomatik
> düzeltme yalnız açık onayla (§4.4); `.claude` repoya gitmez (§4.3). §4 Yasaklar geçerlidir.

## Ne yapar, ne yapmaz
- **Yapar:** yaygın açık sınıflarını, bilinen zafiyetli bağımlılıkları ve riskli yapılandırmayı yüzeye çıkarır; her bulguya somut düzeltme bağlar.
- **Yapmaz:** profesyonel pentest / SAST / DAST yerine geçmez. Rapor **yol gösterir**, tam güvence vermez — bunu raporun sonunda belirt.
- **Sınır:** analiz yereldedir; kod/veri dış servise gönderilmez, proje dizini dışına çıkılmaz.

## Zihinsel model — kaynak → kapı → sink
Her kontrolü üç soruya indirge:
1. **Kaynak** — girdi nereden giriyor? (route, API ucu, form, CLI argümanı, dosya yükleme, WebSocket, kuyruk mesajı, dış API yanıtı)
2. **Sink** — bu girdi hangi tehlikeli işleme varıyor? (SQL çalıştırma, shell, dosya yolu, HTML render, deserializasyon, template)
3. **Kapı** — arada doğrulama / parametreleme / kaçırma / yetki kontrolü **var mı**? Yoksa bulgu bu.

Tarama bu modeli dört cephede uygular: **bağımlılık · kod · yapılandırma · yetki**. Sonuç önem sırasına dizilir, düzeltme kullanıcı seçimine sunulur.

## Kontrol listesi
- [ ] Yığın ve paket ekosistem(ler)i tespit edildi, saldırı yüzeyi çıkarıldı
- [ ] Her ekosistem için bağımlılık denetimi çalıştırıldı
- [ ] Kaynak→sink yolları dört açık sınıfında izlendi
- [ ] Yapılandırma ve sır (secret) sızıntısı tarandı
- [ ] Yetki matrisi çıkarıldı, korunmayan hassas uçlar arandı
- [ ] Bulgular önem sırasıyla raporlandı, hiçbir sır ifşa edilmedi
- [ ] Düzeltme seçenekleri kullanıcıya sunuldu

---

## Cephe 0 — Keşif (yüzeyi haritala)

Denetimin geri kalanı buradaki haritaya dayanır.

1. Kökte ve alt dizinlerde manifest/build dosyalarını tara: `package.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`, `build.gradle`, `composer.json`, `*.csproj`, `*.sln`, `mix.exs`. Monorepo ise her ekosistemi ayrı not et.
2. Manifest'ten framework'ü ve çalışma zamanını çıkar.
3. **Saldırı yüzeyini listele:** kullanıcı girdisinin sisteme girdiği tüm noktalar (üstteki "Kaynak" listesi). Bunlar sonraki cephelerin başlangıç noktalarıdır.
4. Tespit edilen framework için **web araması** yap — araç ve kalıplar sık değişir: `"[framework] security best practices"`, `"[framework] common vulnerabilities"`, güncel `"OWASP Top 10"` listesi.

---

## Cephe 1 — Bağımlılıklar

Üçüncü-taraf paketlerdeki bilinen zafiyetler çoğu ihlalin en ucuz yoludur.

1. Ekosisteme uygun denetim komutunu çalıştır (kurulu değilse kur önerisi ver, kendin kurma):

   | Ekosistem | Komut |
   |---|---|
   | Node | `npm audit` · `pnpm audit` · `yarn npm audit` |
   | Python | `pip-audit` |
   | .NET | `dotnet list package --vulnerable --include-transitive` |
   | Rust | `cargo audit` |
   | Go | `govulncheck ./...` |
   | Ruby | `bundle audit` |
   | Java | OWASP Dependency-Check |

2. Doğru/güncel komuttan emin değilsen web'de doğrula; mümkünse `--json` ile makine-okunur çıktı al.
3. Her bulgudan çıkar: paket · yüklü sürüm · zafiyet kimliği (CVE/GHSA) · önem · düzeltilmiş sürüm.
4. Monorepo'da her alt-projeyi ayrı denetle. Sonuçlar rapora (aşağı) girer.

---

## Cephe 2 — Kod (kaynak→sink izleme)

Saldırı yüzeyindeki her giriş noktasından başla, girdiyi kullanıldığı yere kadar izle, arada kapı olup olmadığına bak. Aşağıdaki tablo **asgari** kapsamdır — tarama sırasında başka sink görürsen ekle.

| Sink sınıfı | Aç​ık | "Kapı" ne olmalı |
|---|---|---|
| **Sorgu** | SQL / NoSQL / LDAP / ORM ham sorgu enjeksiyonu | Parametreli sorgu; string birleştirme yok |
| **Komut** | Shell/OS komut enjeksiyonu | Argüman dizisi; shell'e string geçme yok |
| **Render** | XSS (girdi HTML'de kaçırılmadan), SSTI (girdi template kodu olarak) | Bağlama uygun kaçırma; girdi veri olarak, kod değil |
| **Yol** | Path traversal, kısıtsız dosya yükleme | Yol allowlist/normalizasyon; tür-boyut-içerik doğrulama |
| **Nesne** | Güvensiz deserializasyon, mass assignment | Güvenli format; alan allowlist'i |
| **İfade** | Expression/eval enjeksiyonu, `eval`/`exec` | Girdiyi asla kod olarak değerlendirme |

**Durumu değiştiren + tarayıcı kaynaklı uçlarda ayrıca:**
- **CSRF** — durum değiştiren uçta token koruması var mı?
- **CORS** — kimlik bilgisiyle wildcard origin ya da doğrulanmadan yansıtılan origin var mı?

**Sır (secret) sızıntısı — kaynakta sabit-kodlu kimlik:** şu kalıpları ara, `.env.example` ve test fixture'larını hariç tut:
```
(password|api[_-]?key|secret|token)\s*[:=]\s*["'][^"']+["']
-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----
```
Ayrıca: loglarda maskelenmemiş parola/token/PII; kullanıcıya sızan stack trace veya iç yol.

**İzleme yöntemi:** route/controller dosyalarını oku (girdi buradan girer) → tehlikeli çağrıları grep'le (`eval`, `exec`, string-SQL) → middleware/interceptor'da auth·CSRF·rate-limit var mı bak → veri modelinde mass-assignment koruması var mı bak. Dile özel tehlikeli fonksiyonlar için web araması yap.

**Her bulgu için kaydet:** dosya:satır · açık · saldırganın yapabileceği (etki) · bu koda özel düzeltme.

---

## Cephe 3 — Yapılandırma

**Sır repoda mı:**
```bash
git ls-files --error-unmatch .env 2>/dev/null && echo "UYARI: .env izleniyor"
```
Bulguysa CRITICAL: `git rm --cached .env` → `.gitignore`'a ekle → **ifşa olmuş sırları döndür**.

**Prod'da debug açık:** framework'e özel bayrak için `"[framework] debug mode production"` ara. Belirtiler: açık debug bayrağı, stack trace gösteren hata sayfası, yayımlanmış source map, erişilebilir geliştirme uçları.

**Güvensiz taşıma:** `https` olması gereken sabit `http://` adresleri (API, webhook, OAuth redirect, CDN) ve `Secure`'suz cookie. `localhost`/`127.0.0.1`/`0.0.0.0` hariç.

**Eksik güvenlik başlıkları:** CSP, HSTS, X-Frame-Options, X-Content-Type-Options.

---

## Cephe 4 — Yetki (auth-z)

Erişim kontrolü açıkları taramada en çok kaçırılan sınıftır çünkü kod "çalışıyor" görünür. Proje admin/dashboard veya rol-tabanlı erişim içeriyorsa zorunlu:

1. Tüm rolleri/seviyeleri çıkar (admin, moderatör, kullanıcı, misafir…).
2. Tüm route/uçları ve **gereken** izin seviyesini bir matrise yaz.
3. Her korumalı route'un gerçekten kontrol ettiğini doğrula — "giriş yapmış olmak" yetki değildir.
4. Korunması gerekirken korunmayan uçları ara; URL tahminiyle erişilebilen admin ucu var mı dene.
5. Yetkinin hem controller **hem** veri-erişim katmanında uygulandığını doğrula (IDOR: sahiplik doğrulaması olmadan nesne referansı).
6. Ayrıcalık yükseltme: kullanıcı kendi rolünü/iznini değiştirebiliyor mu? Hassas admin eylemi ek koruma (re-auth/2FA) istiyor mu?
7. **JWT:** `alg: none` / algoritma karışıklığı, koda gömülü secret, eksik expiration.

---

## Rapor

**Önem ölçeği:**

| Seviye | Anlam |
|---|---|
| CRITICAL | Doğrudan sömürülebilir — acil (SQL injection, prod'da sabit sır) |
| HIGH | Ciddi — deploy öncesi kapat (XSS, command injection, bilinen CVE) |
| MEDIUM | Savunma boşluğu — yakında (eksik CSRF, gevşek CORS) |
| LOW | En-iyi-pratik ihlali — uygun olunca (debug modu, eksik başlık) |
| INFO | Gözlem — acil risk yok |

**Bulgu formatı** (önem sırasına dizili):
```
[CRITICAL] SQL Injection — src/api/users.ts:42
  Açık : Girdi doğrudan SQL sorgusuna birleştirilmiş
  Etki : DB okunabilir / değiştirilebilir / silinebilir
  Çözüm: Parametreli sorgu kullan
```

**Özet satırı:**
```
=== Güvenlik Taraması Özeti ===
  CRITICAL: X · HIGH: X · MEDIUM: X · LOW: X · INFO: X · Toplam: X
```

## Düzeltme sunumu
```
Nasıl ilerleyelim?
  1. Tümünü düzelt        2. Yalnız CRITICAL+HIGH
  3. Tek tek onayla       4. Manuel (değişiklik yok)
```
Her düzeltmede: diff önizle → onay bekle → (bağımlılıksa) yükseltme komutu + kırıcı-değişiklik notu → ilgili kontrolü yeniden çalıştır.

## Değişmez kurallar
1. **Yol gösterir, güvence vermez** — profesyonel denetimin yerini tutmaz; raporda söyle.
2. **Sırları maskele** — yalnız ilk 4 + son 4 karakter (`sk-p…i789`); tam sırrı asla yazma.
3. **Onaysız otomatik düzeltme yok** — "Tümünü düzelt" seçilse bile önce ne değişeceğini göster.
4. **Sormadan araç kurma.**
5. **Davranışı koruma** — düzeltme, açığı kapatmak dışında işlevi değiştirmemeli.
6. **Yerelde kal** — kodu/veriyi dış servise gönderme, proje sınırını aşma.
