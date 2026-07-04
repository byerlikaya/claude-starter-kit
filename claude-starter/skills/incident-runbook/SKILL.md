---
name: incident-runbook
description: |
  Üretim olayı müdahalesi ve runbook disiplini: sakinleş-teşhis-azalt-çöz, sonra suçsuz postmortem
  ve tekrarlanabilir runbook. Önce etkiyi durdur, sonra kök nedeni; öğrenilmiş dersi kalıcılaştır.
  Trigger phrases: "incident", "olay müdahale", "runbook", "postmortem", "kök neden", "outage", "üretim olayı", "olay sonrası"
---

# Olay Müdahale & Runbook

İki mod: **canlı olay** (şimdi ne yapmalı) ve **sonrası** (postmortem + runbook). Öncelik: kullanıcı etkisini
durdurmak > kök nedeni bulmak. Panik değil, sıralı adım.

## Canlı olay — sıra
1. **Kabul et & sınıfla** — etki nedir (kim, ne kadar), önem (SEV1 tam kesinti … SEV3 küçük).
2. **Etkiyi azalt ÖNCE** — geri al (rollback), feature-flag kapat, trafiği kaydır, ölçekle. Kök nedeni beklemeden.
3. **Tek koordinatör** — kim karar veriyor belli; iletişim tek kanaldan.
4. **Teşhis** — son değişiklik? (deploy/migration/config) log+metrik+trace (observability) ile daralt.
5. **Çöz** — en küçük güvenli düzeltme; sonra doğrula (health-check).
6. **Kapat** — etki bitti mi teyit; zaman çizelgesini not al (postmortem girdisi).

## Azaltma refleksleri
- Son deploy şüpheli → **rollback** (vps-deploy geri dönüş).
- Şüpheli özellik → **feature-flag** kapat.
- Yıkıcı migration sonrası → yedekten dönüş (db-migration).
- Bağımlılık/servis çökük → devre kesici / graceful degradation.

## Postmortem (suçsuz)
Olay çözülünce, 24-72 saat içinde:
- **Zaman çizelgesi**: tespit → müdahale → çözüm (gerçek saatler).
- **Etki**: kim, ne kadar süre, ne kaybı.
- **Kök neden**: "5 neden"; kişi değil sistem/süreç sorgulanır (**suçsuz**).
- **Aksiyonlar**: tekrarı önleyecek somut, sahipli, tarihli maddeler (erteleme yok).
- Kalıcı karar çıktıysa → `adr`.

## Runbook üret
Tekrarlayabilir olaylar için adım-adım runbook: belirti → teşhis komutları → azaltma → doğrulama → eskalasyon.
Runbook **projeye özel** ve **çalıştırılabilir** olmalı (jenerik değil); `docs-writer` ile koordine.

## Değişmez kurallar
1. **Etkiyi durdur, sonra anla** — kök neden çözümü bekletmez.
2. **Suçsuz kültür** — postmortem kişiyi değil sistemi sorgular.
3. **Aksiyonlar sahipli + tarihli** — "sonra bakarız" yok.
4. **Runbook çalıştırılabilir** — gerçek komut/adım, temenni değil.
5. **Öğrenmeyi kalıcılaştır** — ders adr/runbook/monitoring'e döner, kaybolmaz.
