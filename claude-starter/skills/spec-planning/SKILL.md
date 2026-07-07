---
name: spec-planning
description: |
  Spec-first planlama yöntemi: görev kırılımı, ölçülebilir kabul kriteri, bağımlılık sırası,
  risk-önceliklendirme. planner-cck bunu uygular; plan docs/PLAN.md'ye yazılır.
  Trigger phrases: "planla", "spec", "görev kırılımı", "kabul kriteri", "yol haritası", "nasıl bölelim"
---

# Spec-First Planlama

Kod yazmadan önce: ne yapılacağı, nasıl "bitti" sayılacağı ve hangi sırada ilerleneceği netleşir.

## Adımlar
1. **Amaç & kapsam:** çözülen problem tek cümlede; kapsam-dışını da açıkça yaz (scope creep önle).
2. **Dikey dilimlere böl:** uçtan uca çalışan en küçük parçalar (yatay katman değil). Her dilim tek başına değer üretir.
3. **Her görev için sözleşme:** girdi · çıktı · **ölçülebilir kabul kriteri** (test edilebilir) · tahmini risk.
4. **Bağımlılık grafiği:** hangi görev neyi bekliyor; döngü yok. **En riskli/bilinmeyeni öne al** (fail-fast).
5. **Belirsizlikler:** varsayım listesi + açık sorular; muğlak yeri tahminle doldurma, SEÇMELİ sor.

## Çıktı (docs/PLAN.md)
```
# <Özellik> — Plan
## Kabul kriterleri
- [ ] <ölçülebilir sonuç>
## Görevler (sıra)
1. <görev> — kriter: <...> — bağımlılık: <yok/#n> — risk: <düşük/orta/yüksek>
## Varsayımlar / Açık sorular
- ...
```

## DoD (bu skill'in katkısı)
- Her görevin "bitti"si test edilebilir; sıralama ve bağımlılıklar görünür; en riskli iş başa alınmış.
