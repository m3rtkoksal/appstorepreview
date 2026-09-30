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

## Çalıştırma

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
