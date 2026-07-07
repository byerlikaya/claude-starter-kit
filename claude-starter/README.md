# Agentik Çalışma Kiti — kurulu kit

Bu proje bir Claude Code çalışma kiti ile donatıldı. Kit, işi her aşamada aynı disiplinle yürütür:
**planla → üret → denetle → commit'le** — ve her adımdaki kalite ile güvenlik, modelin hatırlamasına
değil, araç seviyesindeki kapılara dayanır. Kitin tüm davranış kuralları kök `CLAUDE.md`'dedir; bu dosya
`.claude/` altında ne olduğunu ve nasıl çalıştığını özetler.

## Üç ilke

1. **Ajan = ince tetikleyici.** Bir ajan yalnızca "kim, ne zaman"ı söyler; kısa kalır ve işin nasılını skill'e bırakır.
2. **Skill = tek bilgi kaynağı.** Asıl yöntem ve kural skill'de yaşar; ajana kopyalanmaz.
3. **Kural → kapı.** Önemli kural araç seviyesinde zorlanır (hook · permission · eval); anımsanması beklenmez.

## `.claude/` içinde ne var

- **Ajanlar** (`agents/`) — rol başına bir ince tetikleyici: planlama, backend, veritabanı, güvenlik,
  gizlilik, test, frontend, devops, gözden geçirme, commit ve oturum yönetimi. Adlar `-cck` ekiyle
  isimlenir; böylece bu kitin ajanları projenin kendi ajanlarıyla çakışmaz.
- **Skiller** (`skills/`) — "nasıl" bilgisinin tek kaynağı: kod gözden geçirme, güvenlik taraması,
  migration, dağıtım, gözlemlenebilirlik, performans, erişilebilirlik, çeviri bütünlüğü, sürümleme,
  olay müdahalesi ve daha fazlası. (Kurulu set, seçilen profile göre budanmış olabilir.)
- **Komutlar** (`commands/`) — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hook'lar** (`hooks/`) — `guard-bash.sh` (araç seviyesi kapı), `pre-commit` + `commit-msg`
  (iz-denetimi), `context-usage.sh` ve `session-guard.sh` (oturum ölçümü), `trace-blocklist.txt`.
- **settings.json** — izinler ve hook zinciri (PreToolUse · UserPromptSubmit · Stop).
- **Kök `CLAUDE.md`** — davranış, üç ilke, iş akışı, tamamlanma tanımı, token disiplini ve yasaklar.
- **AGENT_TEMPLATE.md** — yeni ajan/skill açma sözleşmesi.

## İş akışı

`/plan` (belirsiz kapsam) → uzman ajanlar üretir → `/review` (güvenlik · kalite · test) →
`/ship` (DoD kapısı; commit'i önerir, onay bekler) → bağlam dolunca `/handoff` → `/clear`.

## Oturum ve token yönetimi

Bir asistan `/context` komutunu kendisi çalıştıramaz; bu yüzden çoğu kurulum oturum doluluğunu tahmin
eder. Bu kit ölçer. `context-usage.sh`, transcript'teki son turun gerçek token sayısını okur;
`UserPromptSubmit` hook'u bunu her tur bağlama enjekte eder; `Stop` hook'u (`session-guard.sh`) doluluk
**%75'i aştığında** devir önerisini garantiyle yüzeye çıkarır. Böylece oturum-sağlığı satırı bir ölçüme
dayanır, bir tahmine değil.

## Kural → kapı

| Kural | Zorlayan mekanizma |
|---|---|
| Commit/push yalnızca onayla — otomatik/bypass modda bile | `guard-bash.sh` (PreToolUse); `CLAUDE_GIT_OK` ile açılır |
| Destrüktif işlem (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (araç seviyesinde blok) |
| Commit'te yapay-zeka izi ve dış şablon/vendor adı bulunmaz | `pre-commit` + `commit-msg` git hook |
| Oturum eşiği | `context-usage.sh` (ölçüm) + `session-guard.sh` (Stop hook) |
| Kalite kapısı (SonarQube kullanan projeler — dil-bağımsız) | `sonarqube-check` + `/ship` |

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek prompt doğru ajan/skill'e mi gidiyor
```

`smoke-test` yapıyı, hook'ların +x ve silahlı oluşunu ve context ölçüm eşiklerini denetler;
`routing-eval` golden prompt kümesinin doğru hedefe yönlendiğini ve trigger çakışması olmadığını
doğrular. İkisi de Claude Code'u çalıştırmaz.

## Genişletme

Yeni bir ajan veya skill eklerken `AGENT_TEMPLATE.md` sözleşmesini izleyin: frontmatter (name ·
description + Trigger phrases · en-az-yetki tools · model kademesi) ve gövde (Ne zaman → Uzmanlık
duruşu → Nasıl/skill → Koordinasyon → DoD → Çıktı & bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Not

Her şey proje-yereldir (`./.claude`); ev dizinine (`~/.claude`) bağımlılık yoktur. `.claude/` ve
`CLAUDE.md`'nin yerel mi tutulacağı yoksa ekiple paylaşılacağı mı, kurulumda verilen karara bağlıdır.
