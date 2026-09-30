# App Store Ekran Görüntüsü Üretici

Uygulama ekran görüntülerinden App Store için 3 karelik, sürekliliği olan
tanıtım görselleri üretir. Tüm sahne tek bir panorama (3852 × 2778) olarak
çizilir ve 3 kareye bölünür; böylece arka plan geçişleri, ışık ve kare
sınırlarındaki yüzen kartlar aynı fotoğrafın ardışık kareleri gibi okunur.
Telefonlar farklı açılarla hafifçe eğilmiştir.

## Çıktılar (`output/`)

| Dosya | Boyut | Açıklama |
| --- | --- | --- |
| `appstore_{1..3}_1284x2778.png` | 1284 × 2778 | 6.7" iPhone (birincil) |
| `appstore_{1..3}_1242x2688.png` | 1242 × 2688 | 6.5" iPhone |
| `panorama.png` | 3852 × 2778 | Bölünmemiş tam sahne |
| `preview_sheet.png` | 1/4 ölçek | App Store boşluklarıyla hızlı önizleme |

## macOS uygulaması (`macos-app/`)

Aynı sahneyi üreten, sürükle-bırak arayüzlü native SwiftUI uygulaması.
Python veya ek kurulum gerektirmez; macOS 13+ ve Xcode (ya da Xcode
Command Line Tools) yeterlidir.

Çift tıklanabilir `.app` oluşturmak için:

```bash
cd macos-app
./build-app.sh
open "dist/App Store Görselleri.app"
```

Xcode ile açmak için `macos-app/Package.swift` dosyasına çift tıklayın ve
Run (⌘R) deyin. Hızlı denemek için `cd macos-app && swift run`.

Uygulamada:

- Her kare için ekran görüntüsünü kutuya sürükleyin ya da tıklayıp seçin.
- Etiket, başlık (`*kelime*` turuncu olur), alt metin, eğim ve konum
  kaydırıcılarını düzenleyin; önizleme anında güncellenir.
- Kare ekle/sil (1–5 kare).
- Yüzen kartlar: her kartın türünü (durum noktası, ilerleme çubuğu, onay
  işareti), metnini, konumunu ve eğimini düzenleyin; kart ekleyin/silin veya
  hepsini kapatın. Konum kare cinsindendir: 1,0 = 1. ve 2. karenin sınırı.
- **Dışa aktar** ile bir klasör seçin; 1284 × 2778 ve 1242 × 2688 PNG'ler,
  `panorama.png` ve `preview_sheet.png` o klasöre yazılır.

Yazı tipi olarak sistemin SF Pro'su kullanılır (Inter Display'e çok yakın);
bu yüzden font dosyası taşımaz.

## Python scripti ile çalıştırma

```bash
pip install pillow
python3 generate.py
```

Yaklaşık 10 saniye sürer.

## Özelleştirme

Tüm ayarlar `generate.py` dosyasının üstünde:

- `FRAMES`: her kare için ekran görüntüsü dosyası, adım etiketi, başlık
  (`*yıldız*` içindeki kelimeler turuncu), alt metin, eğim açısı ve konum.
- `CHIPS`: kare sınırlarına oturan yüzen kartlar (`status`, `progress`, `check`).
- Renkler (`NAVY`, `ORANGE`, ...) ve `SCREEN_W` (telefon ekran genişliği).

Daha keskin sonuç için `assets/` içine cihazdan alınan tam çözünürlüklü
ekran görüntülerini (ör. 1179 × 2556 veya 1290 × 2796) koymanız yeterlidir;
script her çözünürlüğü ölçekler.

Yazı tipi: [Inter](https://rsms.me/inter/) (`fonts/`).
