---
name: security-scan
description: |
  Teknoloji-bağımsız güvenlik taraması. Bağımlılık denetimi, OWASP Top 10 (ve ötesi),
  yapılandırma incelemesi kapsar; önem-sıralı, düzeltme önerili rapor üretir. Her dil/framework ile çalışır.
  Trigger phrases: "security scan", "güvenlik taraması", "OWASP check", "zafiyet tara", "güvenlik açığı bul", "güvenlik denetimi"
---

# Güvenlik Taraması

Kapsamlı, teknoloji-bağımsız güvenlik denetimi: stack'i tespit et, bağımlılıkları denetle, kodu zafiyetlere karşı tara (OWASP Top 10 ve ötesi), yapılandırmayı incele ve eyleme dönük düzeltmelerle önem-sıralı bir rapor üret.

> **Kit uyarlaması (lokal, .claude/):** Teknoloji-bağımsız; varsayılan stack'te (.NET/PostgreSQL) de çalışır.
> `security-expert` bunu uygular; bulgular önem sırasına göre raporlanır ve **review-agent**'a akar.
> Otomatik düzeltme yalnız açık onayla (§4.4); `.claude` repoya gitmez (§4.3). §4 Yasaklar geçerli.

## Genel bakış

Bu skill **teknoloji-bağımsızdır** — her dil, framework veya runtime ile çalışır. En güncel zafiyet kalıpları ve araçları için web aramasını kullanır.

Sırayla yürütülen adımlar:
1. Proje analizi — dil/framework tespiti
2. Bağımlılık denetimi — ekosisteme uygun denetim araçları
3. Kod taraması — temel olarak OWASP Top 10 + analizde bulunan ek zafiyetler
4. Yapılandırma taraması — tehlikeli config hatalarını bul
5. Rapor — önem-sıralı bulgu listesi
6. Düzeltme sunumu — kullanıcı nasıl uygulanacağını seçer
7. Güvenlik kuralları — tarama boyunca geçerli kısıtlar

## Tarama öncesi kontrol listesi

- [ ] Proje dili ve framework'ü tespit edildi
- [ ] Tespit edilen her ekosistem için bağımlılık denetimi tamamlandı
- [ ] Uygulanabilir tüm OWASP Top 10 kategorileri için kod tarandı
- [ ] Yapılandırma dosyaları güvenlik anti-kalıplarına karşı kontrol edildi
- [ ] Önem-sıralı bulgularla rapor üretildi
- [ ] Düzeltme seçenekleri kullanıcıya sunuldu
- [ ] Rapor çıktısında hiçbir secret ifşa edilmedi

---

## Adım 1: Proje analizi

Dili, framework'ü ve paket ekosistemini belirlemek için projeyi tara. **Bu skill teknoloji-bağımsızdır.**

**Talimatlar:**
1. Proje kökünde ve alt dizinlerde manifest/build dosyalarını ara (`package.json`, `requirements.txt`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`, `build.gradle`, `composer.json`, `*.csproj`, `*.sln`, `mix.exs`, `Makefile` vb.)
2. Birden çok ekosistem tespit edilirse (ör. monorepo), hepsini kaydet.
3. Bağımlılıklardan framework'ü belirlemek için manifest'i oku.
4. Tespit edilen ekosistem için güncel önerilen güvenlik denetim aracını ve komutlarını bulmak üzere **web aramasını kullan** — araçlar ve en iyi pratikler sık değişir.
5. Tespit edilen stack'i sakla — hangi denetim komutlarının çalıştırılacağını ve hangi kod kalıplarının kontrol edileceğini belirler.

---

## Adım 2: Bağımlılık denetimi

Yüklü paketleri bilinen zafiyet veritabanlarına karşı kontrol et.

**Talimatlar:**
1. Projedeki paket yöneticisi/yöneticilerini belirle.
2. O ekosistem için güncel önerilen denetim komutunu bulmak üzere **web aramasını kullan** (ör. `npm audit`, `pip audit`, `dotnet list package --vulnerable`, `cargo audit`). Araçlar evrilir — hep en güncelini kontrol et.
3. Denetim aracı yüklü değilse kullanıcıyı bilgilendir ve kurmayı öner.
4. Denetim komutunu çalıştır ve çıktıyı yakala.
5. Sonuçları ayrıştır: paket adı, yüklü sürüm, zafiyet kimliği (CVE), önem derecesi ve varsa düzeltilmiş sürümü çıkar.
6. Tüm bulguları nihai rapora dahil et (Adım 5).

**İpuçları:**
- Mümkünse makine-okunur çıktı için `--json` veya eşdeğer bayrağı kullan.
- Yerleşik denetim komutu olmayan ekosistemler için üçüncü-taraf araçları ara (ör. OWASP Dependency-Check).
- Monorepo'larda her alt-projeyi ayrı denetle.

---

## Adım 3: Kod taraması — güvenlik zafiyeti analizi

Proje kaynak kodunu güvenlik zafiyetlerine karşı tara. Bu tarama **teknoloji-bağımsızdır.**

**OWASP Top 10 zorunlu temeldir.** Her tarama OWASP Top 10 kategorilerini kontrol ETMELİ. Tarama sırasında ek zafiyet bulursan dahil et.

**Taramadan önce** şunlar için web araması yap:
- `"OWASP Top 10 latest"` — güncel liste (periyodik güncellenir)
- `"[framework adı] security best practices"` — framework'e özel rehber
- `"[framework adı] common vulnerabilities"` — bu stack'e ait bilinen kalıplar

### Tarama yaklaşımı
Aşağıdaki her zafiyet kategorisi için:
1. **Kullanıcı girdisi giriş noktalarını belirle** — route'lar, API uçları, form handler'ları, CLI argümanları, dosya yüklemeleri, WebSocket handler'ları
2. **Veri akışını izle** — girdiyi kullanıldığı yere kadar takip et
3. **Sanitizasyonu kontrol et** — girdi kullanılmadan önce doğrulanıyor/kaçırılıyor/parametreleniyor mu?
4. Framework'e özel kalıplar için **web aramasını kullan**

### Zafiyet kategorileri
**Bu listeyle sınırlı kalma** — bunlar asgari kategoriler.

#### Enjeksiyon
- **SQL Injection** — girdi parametreli sorgu yerine SQL'e birleştiriliyor/gömülüyor
- **Command Injection** — girdi güvenli argüman dizisi yerine shell/sistem komutuna geçiriliyor
- **LDAP Injection** — girdi LDAP sorgularında kaçırılmadan
- **NoSQL Injection** — girdi doğrudan NoSQL sorgu nesnesinde, sanitize edilmeden
- **Template Injection (SSTI)** — girdi veri yerine template kodu olarak render ediliyor
- **Expression Language Injection** — girdi ifade motorunda kod olarak değerlendiriliyor

#### Siteler-arası
- **XSS** — girdi HTML'de kaçırılmadan/sanitize edilmeden render ediliyor
- **CSRF** — durum-değiştiren uçlarda CSRF token koruması yok
- **CORS yanlış yapılandırması** — kimlik bilgisiyle wildcard origin, doğrulanmadan yansıtılan origin

#### Veri ifşası
- **Sabit-kodlu secret'lar** — kaynak kodda API anahtarı, parola, token, özel anahtar. Regex ile ara:
  ```
  password\s*=\s*["'][^"']+["']
  api[_-]?key\s*=\s*["'][^"']+["']
  secret\s*=\s*["'][^"']+["']
  -----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----
  ```
  Test fixture'larını ve placeholder değerli `.env.example`'ı hariç tut.
- **Loglarda hassas veri** — parola, token, PII maskeleme olmadan loglanıyor
- **Bilgi sızıntısı** — stack trace, debug bilgisi veya iç yollar kullanıcıya açık

#### Dosya & yol
- **Path Traversal** — girdi dosya yolunda doğrulanmadan (ör. `../../../etc/passwd`)
- **Kısıtsız dosya yükleme** — tür/boyut/içerik doğrulaması yok; çalıştırılabilir yola kaydediliyor

#### Deserializasyon & veri işleme
- **Güvensiz deserializasyon** — güvenilmeyen veri güvensiz yöntemle deserialize ediliyor
- **Mass Assignment** — tüm alanlar allowlist olmadan girdiden bağlanabiliyor

#### Kimlik doğrulama & yetkilendirme
- **Kırık kimlik doğrulama** — zayıf parola politikası, login'de rate limit yok, token URL'de
- **Kırık erişim kontrolü** — uçlarda yetki kontrolü yok, IDOR (sahiplik doğrulamasız nesne referansı)
- **JWT sorunları** — algoritma karışıklığı (`alg: none`), koddaki secret, expiration eksikliği
- **Admin paneli / ayrıcalıklı alan yetkisi** — proje admin/dashboard veya rol-tabanlı erişim içeriyorsa:
  - Admin route'ları auth middleware ile korunuyor mu?
  - Rol/izin kontrolü var mı (yalnız "giriş yapmış" değil)?
  - Normal kullanıcı URL tahminiyle admin uçlarına erişebilir mi?
  - Ayrıcalık yükseltme riski var mı (kullanıcı kendi rolünü değiştirebiliyor)?
  - Hassas admin eylemleri ek korumalı mı (re-auth, 2FA)?
- **Yetki mimarisi analizi:**
  1. Tüm rolleri/seviyeleri belirle (admin, moderatör, kullanıcı, misafir…)
  2. Tüm route/uçları ve gereken izin seviyesini listele
  3. Her korumalı route'un gerçekten izin kontrol ettiğini doğrula
  4. Korunması gerekirken korunmayan route'ları ara
  5. Yetkinin hem controller hem veri-erişim katmanında uygulandığını kontrol et

#### Altyapı & yapılandırma
- **Güvenlik başlıkları eksik** — CSP, X-Frame-Options, HSTS, X-Content-Type-Options yok
- **Güvensiz bağımlılıklar** — (Adım 2'de kapsandı)
- **Prod'da debug modu** — (Adım 4'te kapsandı)

### Nasıl taranır
1. Route/controller dosyalarını oku — girdi buradan girer
2. Tehlikeli fonksiyon çağrılarını ara (`"[dil] dangerous functions security"`)
3. Middleware/interceptor kontrol et (auth, CSRF, rate limit uygulanmış mı)
4. Veri modeli tanımlarını gözden geçir (mass assignment koruması)
5. Regex kalıpları ara (sabit secret, `http://`, `eval()`, `exec()`)
6. Kimlik akışlarını kontrol et (login, kayıt, parola sıfırlama, oturum)
7. Yetki yapısını haritalandır ve her hassas route'ta hem auth hem yetki olduğunu çapraz-kontrol et

**Her bulgu için:** tam dosya+satır · zafiyet · saldırganın yapabileceği (etki) · bu koda özel düzeltme.

---

## Adım 4: Yapılandırma taraması

### 4.1 Git'e commit'lenmiş `.env`
```bash
git ls-files --error-unmatch .env 2>/dev/null
grep -q '\.env' .gitignore 2>/dev/null
```
- **Bulgu:** `.env` repoda izleniyor · **Önem:** CRITICAL
- **Düzeltme:** `git rm --cached .env`, `.gitignore`'a ekle, commit'lenmiş secret'ları döndür.

### 4.2 Prod'da debug modu
Framework'e özel ayar için `"[framework adı] debug mode production security"` ara. Kalıplar: `true` debug bayrakları, stack trace ifşa eden hata sayfaları, açık source map, eksik güvenlik middleware'i, erişilebilir geliştirme-uçları.

### 4.3 Güvensiz HTTP
`https://` olması gereken sabit `http://` URL'leri ara (API, webhook, OAuth redirect, CDN, `Secure`'suz cookie):
```
http://[^localhost][^\s"']*
secure:\s*false
SameSite.*None.*(?!Secure)
```
**Hariç tut:** `http://localhost`, `http://127.0.0.1`, `http://0.0.0.0`.

---

## Adım 5: Rapor

### Önem seviyeleri
| Seviye | Anlam |
|---|---|
| **CRITICAL** | Sömürülebilir — acil (SQL injection, sabit prod secret) |
| **HIGH** | Ciddi — deploy öncesi (XSS, command injection, bilinen CVE) |
| **MEDIUM** | Savunma açığı — yakında (eksik CSRF, gevşek CORS) |
| **LOW** | En-iyi-pratik ihlali — uygun olunca (debug modu, eksik başlık) |
| **INFO** | Gözlem — acil risk yok |

### Format
Bulguları önem sırasına göre diz:
```
[CRITICAL] SQL Injection — src/api/users.ts:42
  Sorun: Girdi doğrudan SQL sorgusuna birleştirilmiş
  Etki: DB okunabilir/değiştirilebilir/silinebilir
  Düzeltme: Parametreli sorgu kullan
```

### Özet
```
=== Güvenlik Taraması Özeti ===
  CRITICAL: X   HIGH: X   MEDIUM: X   LOW: X   INFO: X   Toplam: X
```

---

## Adım 6: Düzeltme sunumu
```
Nasıl ilerlemek istersiniz?
  1. Tümünü düzelt   2. Yalnız kritik (CRITICAL+HIGH)
  3. Tek tek onayla  4. Manuel (değişiklik yok)
```
Her düzeltme için: (1) diff önizle, (2) onay bekle, (3) bağımlılıkta yükseltme komutu + kırıcı-değişiklik notu, (4) sonra ilgili kontrolü yeniden çalıştır.

---

## Adım 7: Güvenlik kuralları
Tarama boyunca geçerli, asla ihlal etme:
1. **Tavsiye niteliğinde, kapsamlı değil** — profesyonel pentest/SAST/DAST yerine geçmez; raporun sonunda söyle.
2. **Secret'ları maskele** — yalnız ilk 4 + son 4 karakter (`sk-p...i789`); tam secret yazma.
3. **Onaysız otomatik düzeltme yok** — "Tümünü düzelt" seçilse bile önce ne değişeceğini göster.
4. **Sormadan araç kurma.**
5. **Mevcut işlevi koru** — düzeltme güvenlik açığı dışında davranışı değiştirmemeli.
6. **Kod/veri sızdırma** — analiz yerelde; dış servise gönderme.
7. **Proje sınırında kal.**
