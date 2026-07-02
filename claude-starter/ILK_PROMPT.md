# Claude Code — İlk Prompt

`start.sh` çalıştıktan sonra Claude Code'u repo kökünde aç ve şunu yapıştır:

```
Yeni proje. Önce bağlamı yükle: ./CLAUDE.md (davranış + proje + stack tek dosyada)
+ docs/ altında spec/plan varsa oku.

Disiplin katmanı şu kaynaklardan türer; kararlar bunlarla HİZALI kalsın:
- Çalışma prensipleri:  multica-ai/andrej-karpathy-skills
- Kod gözden geçirme:   google/eng-practices
- Backend kalıbı:       DevArchitecture/DevArchitecture
- Skill formatı + jenerik skiller: algans/skillgen

İlk kurulum (KOD YAZMA, sırayla):
1) /agents ile 10 ajanın tanındığını göster.
2) Skiller DOLU gelir (code-review, security-scan, db-migration, vps-deploy, devarch-module dahil).
   Yalnız gerekiyorsa projenin stack'ine ince-ayar yap; kaynak/şablon ADI repoya giden hiçbir
   artefakta (kod, namespace, yorum, config) SIZMASIN (§4.2). Domain-özel "nasıl"lar (varsa)
   .claude/skills/ altına AYRICA yazılır.
3) Eksik/uyumsuz varsa DUR ve bildir.

Çalışma kuralları:
- Dört ilke: düşün-sonra-yaz · önce sadelik · cerrahi değişiklik · hedef odaklı.
- Erteleme YOK. Önemli kararları bana SEÇMELİ sor (her seçenek için öneri + gerekçe).
- Her iş DoD ile kapanır: /simplify + testler yeşil + sonarqube-check (0/0/0/0).
- Commit'ler Conventional Commits; commit-agent önerir, onayımı bekler.
- §4 Yasaklar mutlak: yapay zeka izi yok · vendor adı sızmaz · commit/push yalnız açık onayla.
- Her yanıtın SONUNA session-manager'ın oturum-sağlığı satırını ekle (/context yüzdesine göre).

Bitince: bu projenin ilk sprintini birlikte SEÇMELİ planlayalım (planner).
Her yanıtı tek bir yüksek değerli sonraki adımla bitir.
```

