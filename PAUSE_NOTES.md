# IEM Driver — checkpoint rilis

Disimpan: 13 November 2026. Ini checkpoint kerja; belum berarti aplikasi sudah
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
- File kerja tersimpan otomatis di folder workspace. Folder ini belum memiliki
  metadata Git/remote; `gh` juga tidak tersedia dan konektor GitHub belum
  terhubung, sehingga belum ada publikasi atau tag yang dibuat.

## Batasan dan pekerjaan tersisa

1. Jalankan `dart format`, `flutter analyze`, seluruh `flutter test`, build APK
   Android release, dan build Windows; belum ada verifikasi setelah patch sesi
   terakhir.
2. Implementasikan/validasi WASAPI loopback untuk spectrum sistem. Saat ini
   spectrum native masih berasal dari stream test internal, bukan seluruh audio
   Windows.
3. Tambahkan telemetri sample-rate/bit-depth yang benar-benar diambil dari OS;
   route card sekarang belum melaporkan nilai format stream aktual.
4. Tambahkan quick picker profil jack analog dan pilihan UI pink noise.
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
8. Setelah repository/remote dan autentikasi GitHub tersedia, buat tag dan
   publish hanya setelah build artifacts serta signing diverifikasi.

## Titik lanjut tercepat

Mulai dengan memeriksa workflow/installer dan mengaktifkan Windows
Developer Mode (atau build di mesin Windows yang mendukung symlink), lalu build
full PC app. Minta pemilik menyediakan signing keystore dan akses repository/
remote GitHub. Berikutnya lengkapi WASAPI loopback, telemetry format stream,
quick-picker jack, lalu uji hardware. Jangan menyebutnya production-ready
sebelum validasi perangkat dan publikasi dari repository pemilik selesai.

## Catatan rekayasa

- Android global output effects pada session 0 adalah best-effort; kebijakan
  OEM dapat menolak kontrol. DynamicsProcessing dan Equalizer merupakan graphic
  EQ, bukan pengganti PEQ penuh.
- WASAPI loopback hanya menangkap mix pada shared mode; capture tidak memproses
  audio output.
- Jangan menimpa config Equalizer APO tanpa izin. Pertahankan backup dan file
  include yang dikelola aplikasi.
