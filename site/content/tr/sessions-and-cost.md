# Oturum ve maliyet

Oturumun ne kadar dolduğu **ölçülür, tahmin edilmez**: her turda okunan gerçek token sayısı, `/context`'in verdiği değerin aynısı. **%{{FILL_WARN}}**'te bir uyarı, **%{{FILL_ALERT}}**'da bir tane daha; ikisi de turunuzu kesmez.

Sabit maliyet gizlenmiyor, yazıyor. Disiplin ile birlikte her ajan ve skill tarifi her oturuma yüklenir: `smoke-test.sh`'in ölçtüğü **{{ALWAYS_ON_BYTES}} bayt**. Aynı malzemenin 21.804 baytının 9.198 token ettiği gerçek bir `claude -p` turu oranı veriyor; bu oranla yaklaşık **{{ALWAYS_ON_TOKENS}} token**. Süitin kapı olarak tuttuğu sayı bayt rakamı. Eklediğiniz her skill, her oturuma **~100 token**'lık kalıcı bir vergi bindirir; bu yüzden bileşen başına bayt bütçesi bir kapı olarak uygulanır. Bütçeyi yükseltmek testte açık bir düzenleme ister.

**Neden daha az bileşen kurulmuyor?** Çünkü kazancı yok denecek kadar az. Bütün ajan ve skill tarifleri toplam {{DESC_BYTES}} bayt, aynı oranla yaklaşık **{{DESC_TOKENS}} token** tutar; dört UI skill'i ile frontend ajanını dışarıda bırakmak bunun {{UI_BYTES}} baytını, kabaca **{{UI_TOKENS}} token**'ı kazandırır. Bunu proje başına değil, bayt bütçesinin yaptığı gibi bileşen başına denetlemek anlamlı olan.

## Ekip olarak çalışmak

**Depoyu birden fazla kişi paylaşıyorsa bir ekip panosu.** Bir maddeyi almak bir git ref'ine push demek ve push yalnızca fast-forward kabul ediyor; dolayısıyla aynı anda gelen iki üstlenmeden tam olarak biri geçer, diğeri tek satır kod yazılmadan bir saniyenin altında reddedilir. Kararlar ve devir notları panoyla birlikte taşınır; bir oturumda karara bağlanan şey bir sonraki kişinin oturumuna ulaşır. Siz istemedikçe kapalıdır (`/crew-board init`); tek başına çalışırken hiç görünmez.

<div align="center">
  <img src="../../../assets/board-tr.svg" alt="Ekip panosu: üstlenme, bir git ref'ine atomik bir push" width="820">
</div>
