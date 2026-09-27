# Genişletme

Tasarımı üç kural ayakta tutuyor.

1. **Ajan ince bir tetikleyicidir.** *Kim* ve *ne zaman* der, fazlasını demez. Kısa kalır, çünkü tarifi her oturuma yükleniyor.
2. **Yöntemin tek kaynağı skill'dir.** İşin nasıl yapılacağı orada bir kez yazılır ve hiçbir ajanın içine kopyalanmaz.
3. **Önemli olan kural kapıya dönüşür.** Uygulama araç seviyesinde durur: bir hook, bir izin, bir test vakası. Modelden hatırlaması istenmez.

Bir ajan ya da skill eklerken `AGENT_TEMPLATE.md` sözleşmesine uyun: frontmatter (ad · tarif · en az yetkiyle araçlar · model seviyesi), gövdedeki `Trigger phrases:` satırı ve gövde bölümleri (Ne zaman → Uzmanlık duruşu → Nasıl → Koordinasyon → Definition of Done → Çıktı → Eskalasyon → Örnek → Kısıtlar). `smoke-test.sh`, hiçbir yönlendirmenin ulaşmadığı bir bileşeni geri çevirir; böylece hiçbir şey uyur hâlde yayımlanmaz. `/crew-skill` sizi adım adım götürür ve kapılarla biter.

Tam kurulum yerine tek bir bileşen almak için `npx crewforth add <ad>`, bir ajanı ya da skill'i (ve bir ajanın kullandığı skill'leri) `./.claude` içine kopyalar; `npx crewforth add --list` kataloğu gösterir.
