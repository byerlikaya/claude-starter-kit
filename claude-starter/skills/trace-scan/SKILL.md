---
name: trace-scan
description: |
  Iz-denetimi disiplini (§4.1/§4.2): commit oncesi staged degisiklik ve commit mesajinda
  yapay zeka izi (co-author, "Generated with", 🤖, arac adlari) ve ucuncu-taraf sablon/vendor
  adi arar. commit-agent-cck iş kapanisinda tetikler; git hook'lari ayni denetimi otomatik uygular.
  Trigger phrases: "iz tara", "trace scan", "AI izi", "vendor adi kontrol", "commit oncesi denetim"
---

# Iz-Denetimi (trace-scan)

Amac: §4.1/§4.2'yi *hatirlamaya* degil *kapiya* baglamak. Kural sadece metinde kalirsa
er ya da gec iz sizar; bu skill + hook'lar sizmayi commit aninda durdurur.

## Ne zaman
- Her commit oncesi (otomatik: `pre-commit` + `commit-msg` hook'lari).
- commit-agent-cck mesaj onermeden once (manuel dogrulama).

## Nasil
Desen listesi: `./.claude/hooks/trace-blocklist.txt` (grep -iE, satir basi bir desen).
- **Varsayilanlar yuksek-isabet:** co-author, "Generated with/by", 🤖, arac adlari (Claude Code,
  Copilot, ChatGPT), "AI-generated". Tek basina cok gecen sozcukler (model/asistan) KASITLI yok.
- **Vendor adi projeye ozel:** kullanilan ucuncu-taraf sablon adini listeye EKLE (§4.2).

Manuel tarama (hook'suz hizli bakis):
```bash
git diff --cached --unified=0 | grep -E '^\+' | grep -Ev '^\+\+\+' \
  | grep -iEf .claude/hooks/trace-blocklist.txt
```

## Hook kurulumu
`start.sh` `git config core.hooksPath .claude/hooks` ayarlar (git deposu varsa). Hook'lar
`.claude` altinda → gitignore'da, lokal kalir (§4.3). Sonradan repo icin:
```bash
git config core.hooksPath .claude/hooks
chmod +x .claude/hooks/pre-commit .claude/hooks/commit-msg
```

## Kurallar
- Bulgu varsa commit DURUR; ifade kaldirilir, gercek gerekce insansi Turkce yazilir.
- `--no-verify` ile atlamak yalniz ACIK taleple (§4.5); hook sessizce atlanmaz.
- Yanlis-pozitif olursa deseni daralt/kaldir — listeyi proje sahibi kurar.
