# Agentik Çalışma Kiti — Claude Code

Bir projeyi, hangi aşamada olursa olsun, aynı mühendislik disipliniyle ilerleten yeniden kullanılabilir bir Claude Code iskeleti. Sıfırdan bir projeye **kurulur**; hâlihazırda ilerleyen bir projeye ise onu bozmadan **devredilir**. Her iki yolda da akış aynıdır: **planla → üret → denetle → commit'le** — ve her adımdaki kalite ile güvenlik, modelin hatırlamasına değil, araç seviyesindeki kapılara dayanır.

**Sürüm 1.0.0** · **MIT Lisansı** · [Değişiklik günlüğü](CHANGELOG.md)

## Neden bu kit?

Çoğu "agent kurulumu" bir öneriler yığınıdır: kurallar bir dosyada durur, onlara uyulup uyulmaması modelin insafına kalır. Bu kit farklı bir söz verir — **kritik kural bir kapıdır, hatırlatma değil.**

- Commit mesajına yapay-zeka izi **sızamaz**, çünkü bir git hook bunu reddeder.
- Onaysız `commit`/`push` **olmaz**, çünkü bir PreToolUse hook bunu — otomatik/bypass modda bile — durdurur.
- Oturum doluluğu **tahmin edilmez**, çünkü gerçek token sayısı transcript'ten ölçülür.
- Kurulum mevcut projeyi **ezmez**, çünkü devir ayrı bir git dalında yapılır; beğenmezseniz bir komutla silinir.

## Üç ilke

1. **Ajan = ince tetikleyici.** Bir ajan yalnızca "kim, ne zaman"ı söyler; kısa kalır ve işin nasılını skill'e bırakır.
2. **Skill = tek bilgi kaynağı.** Asıl yöntem ve kural skill'de yaşar; ajana kopyalanmaz, tek yerden güncellenir.
3. **Kural → kapı.** Önemli olan kural araç seviyesinde zorlanır (hook · permission · eval). Modelin onu anımsaması beklenmez.

## İki uygulama yolu

### Sıfırdan proje — `start.sh`

```bash
bash start.sh [--backend|--frontend|--mobile|--fullstack] [--dotnet|--generic]
```

`start.sh` bir kurulum sihirbazıdır. Bayrak vermezseniz adımları tek tek sorar (profil → backend yığını → özet ve onay); bayraklar ise sessiz/CI kullanımı içindir. Her seçenek ne kuracağını **kurmadan önce** gösterir: kaç ajan, kaç skill, hangi güvenlik kapıları.

| Profil | Kurulan uzman ajanlar | Öne çıkan skiller |
|---|---|---|
| `--backend` | backend · database | db-migration · api-design · observability |
| `--frontend` | frontend | frontend · a11y · i18n-integrity |
| `--mobile` | frontend (+ React Native/Expo katmanı) | frontend-rn-expo · a11y |
| `--fullstack` | hepsi | tüm skiller |

Backend yığını yalnızca `--backend`/`--fullstack` için sorulur:

- **`--dotnet`** — .NET / DevArchitecture kalıbı (MediatR CQRS · IResult · AOP). `devarch-module` ve `sonarqube-check` skilleri gelir; DevArchitecture temeli, açık bir **onay kapısıyla** projeye dahil edilir.
- **`--generic`** — yığın-bağımsız backend uzmanı. Mevcut repo kalıbına uyar; .NET'e özel skiller kurulmaz. Node, Go, Python ve benzeri için uygundur.

Kurulum tamamlanınca `./.claude/` (ajanlar · skiller · komutlar · hook'lar · eval · settings.json) ile kök `./CLAUDE.md` oluşur, git hook'ları silahlanır ve kurulum artıkları temizlenir.

### Mevcut projeye devir — `update.sh`

```bash
bash update.sh          # hedef projenin kökünde
```

Zaten ilerleyen bir projeye kiti, **bir ekibin projeyi başka bir ekibe devretmesi** gibi uygular. Amaç üç şeyi aynı anda korumaktır: proje bozulmaz, projede alınmış kararlar kaybolmaz, kit de pasif kalmaz. Araç sırasıyla şunları yapar:

1. **Tespit eder** — mevcut ajanları, kuralları, husky/lefthook zincirini, izlenen dosyaları okur; hiçbir şeyi değiştirmez.
2. **Önerir** — yedi devir kararına projeye özgü akıllı bir öneri üretir; interaktif modda hepsini gözden geçirip değiştirebilirsiniz.
3. **Bir devir dalı açar** — tüm değişiklik ayrı bir git dalında yapılır. `main` el değmez; sonucu bir diff olarak inceler, `git` ile kabul veya iptal edersiniz.
4. **Yan yana yaşatır** — kit ajanları `-cck` ekiyle kurulur ve projenin kendi ajanlarıyla asla çakışmaz. Projenin ajanlarına dokunulmaz.
5. **Disiplini bağlar** — kit kuralları `DISCIPLINE.md`'ye yazılır ve projenin `CLAUDE.md`'sine tek satır `@import` ile eklenir; projenin içeriği değişmez.
6. **Ayarları birleştirir** — `settings.json` şema-farkında biçimde birleştirilir; projenin kendi hook ve izinleri korunur, kitinkiler eklenir.
7. **Kapıları kanıtlar** — kurulumdan sonra kapıların gerçekten çalıştığı test edilir (iddia değil, kanıt). Mevcut bir husky zinciri varsa, kit hook'ları onunla bir köprü üzerinden birlikte çalışır.
8. **Devri belgeler** — kalıcı bir `docs/HANDOVER.md` ile `docs/adr/` altında bir karar kaydı bırakır. Böylece kararlar sohbette değil, versiyon kontrolünde yaşar.

## İçindekiler

- **11 ajan** — planner · backend · database · security · privacy · test · frontend · devops · review · commit · session-manager. Ajan adları `-cck` ekiyle isimlenir (Claude Code Kit); böylece kurulduğu her projenin kendi ajanlarıyla çakışmaz.
- **27 skill** — kod gözden geçirme, güvenlik taraması, migration, dağıtım, gözlemlenebilirlik, performans, erişilebilirlik, çeviri bütünlüğü, sürümleme, olay müdahalesi ve daha fazlası.
- **5 slash komut** — `/plan` · `/review` · `/ship` · `/handoff` · `/simplify`.
- **Hook'lar** — `guard-bash.sh` (araç seviyesi kapı), `pre-commit` + `commit-msg` (iz-denetimi), `context-usage.sh` ve `session-guard.sh` (oturum ölçümü), `trace-blocklist.txt`.
- **CLAUDE.md** — davranış, üç ilke, iş akışı, tamamlanma tanımı (DoD), token disiplini ve yasaklar.

## Oturum ve token yönetimi

Bir asistan `/context` komutunu kendisi çalıştıramaz; bu yüzden çoğu kurulum oturum doluluğunu **tahmin eder**. Bu kit ölçer. `context-usage.sh`, transcript'teki son turun API kullanımından gerçek token sayısını okur — `/context`'in gösterdiği değerin aynısı. `UserPromptSubmit` hook'u bunu her tur otomatik olarak bağlama enjekte eder; `Stop` hook'u (`session-guard.sh`) ise doluluk **%75'i aştığında** devir önerisini garantiyle yüzeye çıkarır. Böylece oturum-sağlığı satırı bir ölçüme dayanır, bir tahmine değil.

## Kural → kapı

| Kural | Zorlayan mekanizma |
|---|---|
| Commit/push yalnızca onayla — otomatik/bypass modda bile | `guard-bash.sh` (PreToolUse); `CLAUDE_GIT_OK` ile açılır |
| Destrüktif işlem (reset --hard · force push · rm -rf · --no-verify) | `guard-bash.sh` (araç seviyesinde blok) |
| Commit'te yapay-zeka izi ve dış şablon/vendor adı bulunmaz | `pre-commit` + `commit-msg` git hook (iz-denetimi) |
| Oturum eşiği | `context-usage.sh` (ölçüm) + `session-guard.sh` (Stop hook) |
| Kalite kapısı (SonarQube kullanan projeler — dil-bağımsız: JS/TS · Python · Go · Java · C# …) | `sonarqube-check` + `/ship` |

Bu kapılar `settings.json` ve git `core.hooksPath` üzerinden silahlanır; `smoke-test.sh` her değişiklikten sonra hazır olduklarını doğrular.

## Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek prompt doğru ajan/skill'e mi gidiyor
```

`smoke-test`, ajan/skill frontmatter'ını, sahipsiz skill referanslarını, hook'ların +x ve silahlı oluşunu ve context ölçüm eşiklerini denetler. `routing-eval`, golden bir prompt kümesinin beklenen hedefe yönlendiğini ve iki ajanın aynı tetiği paylaşmadığını doğrular; Türkçe diyakritiği normalize eder ve Claude Code'u çalıştırmaz.

## İş akışı

`/plan` (belirsiz kapsam) → uzman ajanlar üretir → `/review` (güvenlik · kalite · test) → `/ship` (DoD kapısı; commit'i önerir, onay bekler) → bağlam dolunca `/handoff` → `/clear`.

## Genişletme

Yeni bir ajan veya skill eklerken `AGENT_TEMPLATE.md` sözleşmesini izleyin: frontmatter (name · description + Trigger phrases · en-az-yetki tools · model kademesi) ve gövde (Ne zaman → Uzmanlık duruşu → Nasıl/skill → Koordinasyon → DoD → Çıktı & bağlam → Hata/eskalasyon → Örnek → Kısıtlar).

## Lisans ve atıf

MIT — bkz. [LICENSE](LICENSE). Disiplin katmanının bir kısmı üst kaynaklardan uyarlanmıştır: `code-review` skill'i `google/eng-practices` (CC-BY 3.0) çalışmasından, `devarch-module` skill'i ise DevArchitecture kalıbından (yazarının açık izniyle). Ayrıntılar için [ATTRIBUTION.md](ATTRIBUTION.md).
