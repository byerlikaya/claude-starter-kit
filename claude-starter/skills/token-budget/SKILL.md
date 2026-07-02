---
name: token-budget
description: |
  Bağlam/token yönetimi disiplini: subagent izolasyonu, çıktı=özet sözleşmesi, dosyaya-taşıma,
  delege eşiği, yalın skill. session-manager ve tüm ajanlar buna uyar.
  Trigger phrases: "token", "context", "bağlam yönetimi", "context doldu", "context temizle"
---

# Token & Bağlam Disiplini

Subagent'ın amacı context yönetimi: subagent kendi penceresinde çalışır, ana thread'e **yalnız
özetini** döndürür — ara gürültü (dosya okuma, arama, log) ana bağlama hiç girmez.
**Uyarı:** subagent-yoğun akış tek-thread'e göre kabaca 7x token yer; izolasyon için delege et, her şey için değil.

## Kurallar
1. **Çıktı = özet.** Ajan ana thread'e kısa yapılandırılmış özet döner; ham log / dosya-dökümü / uzun kod **döndürmez**.
2. **Dosyaya taşı.** Ağır çıktı (plan, tarama raporu, envanter) `docs/*.md`'ye yazılır; geri **özet + işaretçi** döner. (lokal, gitignore'da)
3. **Delege eşiği.** Gürültülü/ağır iş (çok dosya okuma, tarama, araştırma) → subagent. Tek tool-call / küçük iş → **ana thread**.
4. **En-az-araç.** Ajan yalnız gerekli araca sahip; fazlası kazara context kirletir + limit tüketir.
5. **Yalın SKILL.md.** Skiller ana context'e yüklenir; ağır referans ayrı dosyaya, yalnız gerekince.
6. **Hedefli okuma.** Tüm dosyayı okumak yerine Grep/Glob ile nokta atışı.
7. **/context ile yönet.** session-manager gerçek yüzdeye göre devam/handoff+clear önerir; faz sınırında `/clear`.
