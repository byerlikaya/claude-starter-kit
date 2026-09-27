# Doğrulama

```bash
bash .claude/eval/smoke-test.sh      # yapı, frontmatter, kapı bütünlüğü
bash .claude/eval/routing-eval.sh    # örnek bir istek doğru ajana ya da skill'e ulaşıyor mu
bash .claude/eval/doctor.sh          # bu kurulum sağlıklı mı, proje hazır mı
bash .claude/eval/preflight.sh       # bu makinede hangi araçlar var, olmayanlar neyi zayıflatıyor
```

`preflight.sh` ayrıca `start.sh`, `adopt.sh` ve `doctor.sh` içinden de koşar. Crewforth ne `jq` ne `python` ister: her JSON okuma ve yazma, her hook ve her kurulum adımı tek bir bash/awk yolundan geçer; macOS, Linux ve sıfır bir Windows Git Bash aynı kodu koşar, aynı sonucu alır. Hâlâ isteğe bağlı olan bir araç eksikse Crewforth kırılmaz, kabiliyet düşürerek devam eder: `sha256sum` yoksa `cksum`'a iner. Doğru tasarım bu, ama aynı zamanda bir eksiğin kendini hiç duyurmamasının da sebebi. Preflight eksiği ve bedelini adıyla söyler. Yalnızca rapor eder; makinenize hiçbir şey kurmaz ve hiçbir çalıştırmayı engellemez.

## Gerçekten bir şey değiştiriyor mu?

Aynı istek hem Crewforth kurulu hem de çıplak bir projede koşturuluyor ve her birinin diskte bıraktığına göre puanlanıyor. Bir sonucun sağlaması gereken kural koşudan önce yazılıyor. Her ölçüm gerekçesiyle [`evals/README.md`](../../../evals/README.md) içinde yayımlanıyor; o kuralın tutmadığı ölçümler de dahil.
