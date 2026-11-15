# IEM Driver — checkpoint rilis

Disimpan: 15 November 2026. Windows release dan installer berhasil dibangun;
checkpoint ini belum berarti paket sudah ditandatangani atau siap dipublikasikan.

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
- Setelah Developer Mode diaktifkan, `flutter build windows --release` berhasil.
  Build awal menemukan MSVC C4324 pada indeks cache-line-aligned SPSC queue;
  warning tersebut kini ditekan lokal pada deklarasi queue dan build ulang
  berhasil. Loopback belum diuji runtime pada endpoint fisik.
- Ditambahkan root `.gitignore` untuk output CMake, build Flutter, dan bahan
  signing lokal. README dirapikan dan diperbarui sesuai status loopback.
- Estimasi: sekitar 70% implementasi fitur menuju expert preview dan 65%
  kualifikasi paket lintas platform; angka ini bukan sertifikasi produksi.
  Signing resmi, workflow GitHub, APO, dan tes hardware masih menjadi gerbang.
- Installer Inno diperkuat dengan pemeriksaan compile-time untuk executable
  hasil build, target x64-compatible, ikon aplikasi, dan tautan dukungan. Inno
  Setup 6.7.3 berhasil mengompilasi installer lokal tanpa warning arsitektur.
- Workflow rilis kini mensyaratkan tag stabil `vMAJOR.MINOR.PATCH` cocok dengan
  versi `app/pubspec.yaml`, memverifikasi APK bertanda tangan serta mengecek
  installer dan portable ZIP sebelum publish. Pengecekan APO installer sekarang
  mencari direktori instalasi default, bukan file konfigurasi yang bisa belum
  dibuat.
- Android release APK berhasil dibangun ulang dengan JDK 25 melalui `JAVA_HOME`
  sementara, tetapi tidak memiliki signature rilis. Build pertama memilih JVM 8
  Oracle dari PATH dan gagal; konfigurasi global tidak diubah.
- Installer `dist/IEM-Driver-Setup-v0.1.0.exe` dan portable
  `dist/IEM-Driver-Windows-portable.zip` berhasil dibuat lokal. Belum dilakukan
  install/uninstall smoke test, code signing Windows, atau uji APO/audio nyata.

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
- Audit lokal tidak menemukan release keystore, `key.properties`, atau
  `IEM_RELEASE_*` credentials. Hanya debug keystore yang tersedia; jangan pakai
  itu untuk rilis. APK lokal terbaru karena itu unsigned.
- Perubahan sesi terakhir yang sudah tersimpan: runner Windows menerima flag
  pink-noise dan tidak lagi mengirim PEQ ke test engine; indikator perangkat
  diganti fade statis 200 ms tanpa jiggle/animasi charging; card status System
  EQ ditambahkan; overlay wallpaper dinaikkan ke 85%.
- Dropdown Sine/Pink Noise sudah masuk dan teruji pada Flutter test suite.
- Repository lokal memakai branch `main` dan remote `origin` ke
  `aantiosaputra11-glitch/Driver-Sound-HRB`; commit awal sudah dipush. Perubahan
  checkpoint 15 November belum dipush. Belum ada tag/release GitHub.

## Batasan dan pekerjaan tersisa

1. Uji installer dan portable Windows pada PC bersih; verifikasi Equalizer APO,
   izin tulis konfigurasi, loopback, pergantian endpoint, dan rollback.
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
6. Installer dan GitHub Actions workflow sudah dibuat; uji instalasi,
   update/uninstall, dan jalankan workflow CI sebelum membuat rilis publik.
7. Global `AudioEffect` session 0 Android tidak dijamin oleh OEM dan hanya
   menyediakan graphic EQ; Q, tipe filter PEQ, dan preamp tidak dapat diterapkan
   setara PEQ penuh. Rilis harus menyebutnya best-effort dan menguji perangkat
   fisik yang ditargetkan.
8. Setelah signing Android, code signing Windows (bila digunakan), APO, dan
   hardware diverifikasi, minta persetujuan sebelum push, membuat tag, atau
   memublikasikan artifacts ke GitHub.

## Titik lanjut tercepat

Berikutnya siapkan release keystore dan GitHub Actions secrets, lalu uji
installer/loopback/Equalizer APO pada PC dan global AudioEffect pada Android
target. Jalankan workflow rilis hanya setelah gates lolos dan dengan persetujuan
pengguna. Jangan menyebutnya production-ready sebelum validasi perangkat dan
signing resmi selesai.

## Catatan rekayasa

- Android global output effects pada session 0 adalah best-effort; kebijakan
  OEM dapat menolak kontrol. DynamicsProcessing dan Equalizer merupakan graphic
  EQ, bukan pengganti PEQ penuh.
- WASAPI loopback hanya menangkap mix pada shared mode; capture tidak memproses
  audio output.
- Jangan menimpa config Equalizer APO tanpa izin. Pertahankan backup dan file
  include yang dikelola aplikasi.
