# IEM Driver — checkpoint rilis

Disimpan: 15 November 2026. Ini checkpoint kerja; belum berarti aplikasi sudah
lulus build akhir atau siap dipublikasikan.

## Verifikasi lanjutan (14 November 2026)

- `dart format` dijalankan; `flutter analyze` bersih dan semua 17 tes lulus.
- Android release-mode APK berhasil dikompilasi. Karena belum ada signing
  keystore rilis, APK hasil Gradle unsigned dan tidak untuk dibagikan.
- APK release-mode terpisah ditandatangani dengan debug certificate untuk
  pengujian internal dan lolos verifikasi `apksigner`:
  `app/build/app/outputs/flutter-apk/app-release-test.apk`.
- Target native `iem_windows_endpoint` berhasil dikompilasi dengan CMake/MSBuild.
- Full Flutter Windows build belum berhasil: plugin symlink hilang karena
  Windows Developer Mode/symlink support tidak aktif. Mencoba build CMake runner
  langsung mengonfirmasi plugin source links tidak ada; jangan mem-bypass dengan
  membuat symlink manual.
- Ditambahkan `.github/workflows/release.yml` dan `installer/IEMDriver.iss`.
  Workflow belum dijalankan di GitHub; installer tidak dapat dites lokal karena
  Inno Setup tidak terpasang.
- `README.md` dan `app/README.md` kini membedakan fitur yang ada dari gap
  system-wide/loopback serta menjelaskan konfigurasi signing.

## Verifikasi dan perubahan (15 November 2026)

- Ditambahkan `WasapiLoopbackCapture` untuk menangkap mix output endpoint
  Windows default secara read-only, mengubah PCM float/16/24/32-bit menjadi
  input analyzer, dan mengekspos start/stop/status/read lewat method channel.
- UI Windows sekarang memiliki kontrol **Monitor PC audio** terpisah dari test
  tone. Kedua mode saling eksklusif; monitor berhenti jika endpoint capture
  berakhir dan perlu dimulai ulang setelah route audio berubah.
- `iem_windows_endpoint` berhasil dikonfigurasi dan dibangun dengan CMake/MSBuild,
  termasuk file loopback baru.
- `dart format` selesai, `flutter analyze` bersih, dan seluruh 17 tes lulus.
- `flutter build windows --release` dicoba lagi tetapi tetap tertahan karena
  Developer Mode/plugin symlink support nonaktif. Loopback belum dapat diuji
  runtime pada aplikasi Windows penuh atau perangkat audio fisik.
- Ditambahkan root `.gitignore` untuk output CMake, build Flutter, dan bahan
  signing lokal. README dirapikan dan diperbarui sesuai status loopback.
- Estimasi: sekitar 70% implementasi fitur menuju expert preview, tetapi sekitar
  55% kualifikasi paket uji lintas platform; persentase ini belum menilai
  sertifikasi produksi. Build Windows penuh, signing, APO, dan tes hardware masih
  menjadi gerbang rilis.

## Status saat jeda

- UI Flutter memiliki PEQ 10-band interaktif, kontrol fader, delapan slot,
  preset sharing/import, tema wallpaper, dan impor/ekspor AutoEQ text.
- Parser AutoEQ Dart, sampling respons PEQ untuk auto-preamp, dan tes parser
  telah ditambahkan; empat tes parser sebelumnya lulus. Validasi menyeluruh
  harus dijalankan lagi setelah perubahan sesi terakhir.
- Android memiliki controller global best-effort `DynamicsProcessing` dengan
  fallback `Equalizer` pada session 0. Oboe diarahkan hanya untuk generator
  test tone (termasuk pink noise); dukungan global bergantung ROM/OEM.
- Windows memiliki layanan Dart yang mengelola file include Equalizer APO dan
  membuat backup `config.txt`. Pengujian build akhir/izin tulis belum selesai.
- Gradle disiapkan untuk minSdk 28, targetSdk 34, ProGuard, serta signing dari
  environment variable; tidak ada keystore/password yang boleh masuk repo.
- Perubahan sesi terakhir yang sudah tersimpan: runner Windows menerima flag
  pink-noise dan tidak lagi mengirim PEQ ke test engine; indikator perangkat
  diganti fade statis 200 ms tanpa jiggle/animasi charging; card status System
  EQ ditambahkan; overlay wallpaper dinaikkan ke 85%.
- Dropdown Sine/Pink Noise sudah masuk dan teruji pada Flutter test suite.
- Repository lokal memakai branch `main` dan remote `origin` ke
  `aantiosaputra11-glitch/Driver-Sound-HRB`; commit awal sudah dipush. Perubahan
  checkpoint 15 November belum dipush. Belum ada tag/release GitHub.

## Batasan dan pekerjaan tersisa

1. Aktifkan Windows Developer Mode (atau gunakan mesin dengan plugin symlink
   support), lalu jalankan `flutter build windows --release` dan uji loopback
   runtime pada endpoint nyata. Native target CMake, analyzer, dan 17 tes Flutter
   sudah lolos; capture belum diuji pada aplikasi penuh.
2. Pastikan monitoring loopback pulih/berhenti dengan benar saat default
   endpoint berubah atau perangkat terputus.
3. Tambahkan telemetri sample-rate/bit-depth yang benar-benar diambil dari OS;
   route card sekarang belum melaporkan nilai format stream aktual.
4. Quick picker jack analog dan pilihan UI pink noise sudah tersedia; validasi
   pemilihan profil jack pada perangkat fisik masih diperlukan.
5. Selesaikan izin Equalizer APO: konfigurasi di Program Files dapat memerlukan
   elevasi; service sekarang hanya melaporkan kegagalan, belum punya flow UAC.
   Verifikasi juga rollback/backup terhadap config yang berisi format newline
   berbeda.
6. Buat installer Inno Setup dengan dependency check APO, dokumentasi rilis,
   dan GitHub Actions workflow. Uji instalasi/update/uninstall di Windows bersih.
7. Global `AudioEffect` session 0 Android tidak dijamin oleh OEM dan hanya
   menyediakan graphic EQ; Q, tipe filter PEQ, dan preamp tidak dapat diterapkan
   setara PEQ penuh. Rilis harus menyebutnya best-effort dan menguji perangkat
   fisik yang ditargetkan.
8. Setelah build Windows, signing Android, APO, dan hardware diverifikasi,
   unggah perubahan checkpoint, buat tag, lalu publish artifacts ke GitHub.

## Titik lanjut tercepat

Mulai dengan mengaktifkan Windows Developer Mode (atau build di mesin Windows
yang mendukung plugin symlink), lalu build full PC app dan uji loopback. Berikutnya
lengkapi telemetry format stream, verifikasi Equalizer APO dan Android pada
hardware, siapkan signing keystore, lalu jalankan workflow rilis. Jangan
menyebutnya production-ready sebelum validasi perangkat dan signing resmi selesai.

## Catatan rekayasa

- Android global output effects pada session 0 adalah best-effort; kebijakan
  OEM dapat menolak kontrol. DynamicsProcessing dan Equalizer merupakan graphic
  EQ, bukan pengganti PEQ penuh.
- WASAPI loopback hanya menangkap mix pada shared mode; capture tidak memproses
  audio output.
- Jangan menimpa config Equalizer APO tanpa izin. Pertahankan backup dan file
  include yang dikelola aplikasi.
