---
name: code-review
description: |
  Kod gözden geçirme disiplini: değişikliğin genel kod-sağlığını iyileştirip iyileştirmediğine
  odaklı, önem-sıralı, gerekçeli geri bildirim. review-agent-cck bunu uygular.
  Trigger phrases: "code-review", "kod incele", "PR incele", "gözden geçir", "review yap"
---

# Kod Gözden Geçirme

> **Kit uyarlaması (lokal, .claude/):** `review-agent-cck` (salt-okunur) uygular. Kaynak (hizalama):
> google/eng-practices — adı repoya giden artefakta geçmez (§4.2). Yorumlar önem-sıralı; §4 geçerli.

## Temel standart (kıdemli ilke)
Bir değişiklik, sistemin **genel kod-sağlığını iyileştirdiği** noktaya geldiğinde onaylanır —
**mükemmel olması gerekmez.** İki hatadan kaçın:
- **Bloklama:** ilerlemeyi durduran, mükemmeliyetçi, öznel takıntı. İlerleme olmazsa kod hiç iyileşmez.
- **Gevşeklik:** her seferinde küçük ödünler kod-sağlığını zamanla aşındırır.
Onay ölçütü "daha iyi mi", "kusursuz mu" değil. İstenmeyen bir özellik ise tasarım iyi olsa da reddedilebilir.

## Neye bakılır (öncelik sırası)
1. **Tasarım:** parçalar birbirine oturuyor mu; bu değişiklik buraya mı ait; şimdi mi eklenmeli.
2. **İşlevsellik:** amaçlananı yapıyor mu; kullanıcı/geliştirici için doğru mu; sınır durumları, eşzamanlılık.
3. **Karmaşıklık:** gereğinden karmaşık mı; over-engineering / gelecekteki-varsayıma göre tasarım (YAGNI) var mı.
4. **Testler:** doğru, anlamlı, yeterli test var mı; test-için-test değil gerçek davranış.
5. **İsimlendirme:** niyeti taşıyan, ne çok uzun ne kriptik adlar.
6. **Yorumlar:** "ne"yi değil **"neden"i** açıklıyor mu; ölü/gereksiz yorum yok.
7. **Stil & tutarlılık:** proje kılavuzuna uygun; mevcut konvansiyonla tutarlı.
8. **Dokümantasyon:** davranış değiştiyse ilgili doküman güncellendi mi.
9. **Her satır:** insan-yazımı her satıra bak; anlamadığın kodu "muhtemelen doğrudur" diye geçme.

## Yorum yazma
- **Nazik ve gerekçeli:** ne değişmeli + **neden**. Emir değil, öneri diliyle.
- **"Nit:"** etiketiyle küçük/zorunlu-olmayan notları ayır — bunlar bloklamaz.
- Koda değil koda yorum yap; kişiyi değil kodu değerlendir.
- İyi olanı da belirt; sadece kusur avlama.

## Hız & anlaşmazlık
- **Hızlı dön:** bekleyen review üretkenliği düşürür; ilk fırsatta bak.
- Anlaşmazlıkta **teknik gerçek + veri** konuşur, kişisel tercih değil. Uzlaşılamazsa yüz yüze / üst mercie taşı — pasif bloklama değil.

## DoD (bu skill'in katkısı)
- Bulgular önem-sıralı (blocker / öneri / nit) ve **gerekçeli**.
- Kapsam kayması ve gizli karmaşıklık işaretlendi.
