# xtool-extended: TestFlight ve App Store Yol Haritası

## Hedef

Linux/WSL ve macOS üzerinde SwiftPM tabanlı iOS uygulamalarını, varsa Watch uygulaması ve uzantılarıyla birlikte dağıtım için hazırlamak ve App Store Connect'e yüklemek.

Hedef kullanım `xtool deploy testflight`; sonraki aşama App Store inceleme ve yayımlama akışıdır. Birleşik deploy komutu henüz mevcut değil. Şu an `xtool dev archive`, `xtool ds upload-build` ve `xtool ds build-upload-status` ile ayrı hazırlama, yükleme ve durum akışları var.

**Temel ayrım:** IPA oluşturulması, Apple'a yüklenmesi, Apple tarafından işlenmesi, test kullanıcılarına dağıtılması ve App Store'da yayımlanması ayrı sonuçlardır. CLI bunları ayrı raporlamalıdır.

## Mevcut temel

- iOS ve companion Watch ürünlerini derleme ve aynı uygulama paketine yerleştirme desteği var.
- Geliştirme sertifikası ve geliştirme provisioning profilleriyle cihaz kurulumu var.
- App Store Connect API anahtarı ve JWT kimlik doğrulaması mevcut.
- Ayrı dağıtım sertifikası/profili seçimi, release IPA üretimi ve hazır IPA yükleme akışı eklendi; birleşik deploy komutu ve tester dağıtımı sonraki aşamalar.
- Geliştirme akışı bundle ID'lerine `XTL-` öneki ekliyor; dağıtım akışı gerçek App Store kimliklerini korumalı.
- Varsayılan sürüm ve build numaraları `1.0.0` ve `1`; dağıtımda açıkça yönetilmeleri gerekiyor.

## 0. Hesap ve doğrulama uygulamasını hazırlama

- [x] Apple Developer Program üyeliğini ve App Store Connect yükleme yetkilerini doğrula.
- [x] Uygulamanın App Store Connect kaydını ve kullanılacak gerçek bundle ID'sini belirle.
- [x] API anahtarını mevcut kimlik doğrulama akışıyla kullan; özel anahtarı repoya veya loglara yazma.
- [x] Gerçek kullanıcı verisi içermeyen küçük bir iOS doğrulama uygulaması seç. Sonraki doğrulama için buna companion Watch uygulaması ve bir uzantı ekle.
- [x] İlk TestFlight hedefini mevcut bir internal test grubu olarak belirle; dış test ve App Store yayımlamasını ilk sürüme dahil etme.

**Tamamlanma ölçütü:** Hesap, uygulama kaydı ve kimlikler belli; API ile uygulamaya erişim doğrulanmış.

**Durum: tamamlandı.** Kayıtlı anahtarla uygulama ve sertifika API'leri doğrulandı; dört geçerli dağıtım sertifikası bulundu. Anahtarın Admin/App Manager rolü kullanıcı tarafından teyit edildi. Kullanıcının seçtiği mevcut uygulama kaydı için onayıyla `xtool Internal` adlı boş internal grup oluşturuldu ve yeniden okunarak doğrulandı; tester/build eklenmedi, tüm build'lere otomatik erişim açılmadı. Hesaba özel kimlikler Git'e alınmayan `.build/testflight-readiness.json` dosyasında tutuluyor.

`Examples/DistributionValidation` içinde ağ veya kullanıcı verisi içermeyen iOS + Watch + widget fixture'ı hazırlandı. Üç hedefin release derlemesi ve yerel paket yapısı doğrulandı. Bu kontrol dağıtım imzalama, Apple'a yükleme veya TestFlight kurulumu değildir; bunlar sonraki milestone'larda doğrulanacak.

## 1. Geliştirmeden ayrı dağıtım imzalama akışı

- [x] Geliştirme ve App Store dağıtımını açık bir imzalama amacıyla ayır; mevcut `xtool dev` davranışını koru.
- [x] Apple Distribution sertifikası ve karşılık gelen özel anahtarı seçme/oluşturma desteği ekle. Özel anahtarı bulunmayan bir sertifikayı kullanılabilir sayma.
- [x] Geliştirme ve dağıtım sertifikalarının saklanmasını ayır. Dağıtım işlemi geliştirme sertifikalarını iptal etmemeli veya onların kayıtlarını ezmemeli.
- [x] Ana uygulama, Watch uygulaması ve uzantılar için uygun App Store Connect profillerini seç veya oluştur. Cihaz UDID listelerini geliştirme akışında tut.
- [x] Kullanıcıya ait ilgisiz profilleri silme; mevcut profil temizleme mantığını dağıtım profillerine körlemesine uygulama.
- [x] Bundle ID ve App Group kimliklerini App Store kaydıyla aynı tut. `WKCompanionAppBundleIdentifier` ilişkisini koru.
- [x] Entitlements'ı dağıtım profilleriyle eşleştir: geliştirme amaçlı `get-task-allow` kalmamalı; push kullanılıyorsa üretim ortamı doğru olmalı.

**İlgili kod:** `SigningContext.swift`, `AutoSigner.swift`, `ProvisioningIdentifiers.swift`, `DeveloperServicesFetchCertificateOperation.swift`, `DeveloperServicesFetchProfileOperation.swift`, `DeveloperServicesAddAppOperation.swift`.

**Tamamlanma ölçütü:** iOS, Watch ve uzantı paketleri doğru dağıtım sertifikası/profiliyle imzalanabiliyor; geliştirme kurulumu testleri bozulmuyor.

**Durum: tamamlandı.** `SigningContext.Purpose.appStore` eklendi; varsayılan geliştirme amacı korunuyor. Dağıtım sertifikası ayrı saklanıyor, özel anahtar ile sertifikanın eşleşmesi doğrulanıyor; kota hatasında sertifika iptal edilmiyor. Uygun mevcut App Store profili yeniden kullanılıyor veya cihaz ilişkisi olmadan oluşturuluyor. Geliştirme profil temizliği de artık App Store profilini silmiyor.

Dağıtım yolu önceden kayıtlı kesin bundle ID'leri ve capability ayarlarını kullanıyor; mevcut mağaza kaydının capability'lerini değiştirmiyor. App Group ve diğer istenen entitlements profil tarafından yetkilendirilmediyse işlem açık hata veriyor. Anahtar içermeyen testler, yanlış takım/profil/özel anahtar ve yetkisiz entitlement durumlarını kapsıyor.

Gerçek hesapla, fixture'ın Git dışında tutulan bir kopyası seçilmiş mevcut uygulama kimlikleriyle imzalandı: iOS, Watch ve widget için Apple Distribution sertifikası ve App Store profilleri oluşturuldu, ikinci çalıştırmada yeniden kullanıldı. Üç imzalı executable'da `get-task-allow=false` doğrulandı. 75 test ve `make lint` geçti; gerçek hesap testi ayrıca opt-in olarak geçti. Build yüklenmedi ve testçilere dağıtılmadı.

## 2. Mağazaya uygun release IPA üretimi

- [x] Mevcut `BuildSettings`, `Planner` ve `Packer` akışlarını kullanarak release derlemesi üret.
- [x] Uygulama sürümünü ve build numarasını açıkça al/doğrula. Yerel mevcut çıktıyı koru; uzak yinelenen build kontrolünü yükleme aşamasına bırak.
- [x] iOS, Watch ve uzantılardaki sürüm/build bilgilerini tutarlı hale getir.
- [x] Apple'ın istediği ikon, asset catalog, Info.plist ve derleme metadata'sını belirle. Mevcut dosya kopyalama yaklaşımının yeterli olduğu varsayılmamalı.
- [x] Her hedef için mimari, minimum işletim sistemi, gömülü framework ve imza yapısını yerel olarak doğrula. Tek mimarili Watch çıktısının Apple tarafından kabulünü üçüncü aşamada ayrıca test et.
- [x] Asset derleme ve paket araçlarının Linux/WSL'de hangi bölümlerinin çalıştığını gerçek çıktı üzerinde doğrula. Eksik bir araç varsa açık hata ver; gerektiğinde macOS üzerinde paket hazırlama yolunu belgeleyip Linux yükleyicisinden ayrı tut.
- [x] Üretilen IPA'yı doğrulama bitmeden başarılı dağıtım çıktısı olarak sunma; hatada önceki geçerli çıktıyı koru.

**Tamamlanma ölçütü:** İncelenebilir, dağıtım imzalı bir IPA hazır. Yerel kontroller geçiyor; Apple'ın kabulü bir sonraki aşamada kanıtlanacak.

**Durum: tamamlandı — yerel dağıtım IPA üretimi doğrulandı.** `xtool dev archive --version … --build-number … --assets …` release derlemesi, ortak sürüm/build, önceden derlenmiş ikonların birleştirilmesi, App Store imzalaması ve IPA üretimini tek yerel akışta yapıyor. Derleyici/linker çıktısındaki SDK alanının minimum OS olarak yazılması gerçek kontrolde yakalandı; dağıtım derlemesi artık gerçek SDK sürümünü bağlayıcıya geçiriyor. Xcode/SDK metadata'sı kurulu SDK'nın version/SDKSettings/SystemVersion plist dosyalarından okunuyor.

Fixture'ın iOS ve Watch ikonları GitHub Actions macOS çalıştırıcısında Apple `actool` ile derlendi; iki `Assets.car` Apple `assetutil` kontrolünden geçti. [Doğrulama çalıştırması](https://github.com/ferixinder/xtool-extended/actions/runs/42098644849) yalnız test ikonları içeriyor; anahtar veya uygulama binary'si gönderilmedi. Ana dal değiştirilmedi; bu çalışma için yalnız `codex/milestone2-assets` doğrulama dalında fixture/workflow commit'leri oluşturuldu. Yeni AssetKit kütüphanesinin Watch kapsamı yeterli olmadığı için dağıtım yoluna eklenmedi.

Linux'ta iOS + Watch + widget release olarak derlendi ve gerçek hesapla imzalanarak `.build/distribution-validation/FerixValidation-1.0.0-101.ipa` üretildi. Üç hedefin sürüm/build ve SDK bilgileri, profil ve resource seal varlığı, Mach-O kod sayfası hash'leri, CMS imzaları ve plist/manifest imza hash'leri kontrol edildi. Tekrar aynı çıktıya yazma girişimi hata verdi ve önceki IPA'nın SHA-256 özeti değişmedi. İmzasız/değiştirilmiş binary, hatalı sürüm, simülatör, uyumsuz framework ve paketleme hatası için regresyon kontrolleri eklendi.

Linux'ta asset catalog derlendiği iddia edilmiyor: mevcut çözüm macOS'ta önceden derlenmiş katalogları kullanıyor ve eksik katalogda açık hata veriyor. Kullanım ve sınırlar `Documentation/xtool.docc/Distribution.md` içinde. Apple'a build yüklenmedi; uzak yinelenen build kontrolü, tam Apple paket doğrulaması ve tek mimarili Watch kabulü milestone 3'te doğrulanacak. macOS tam archive akışı ayrıca doğrulanmadı; macOS ikon derlemesi ve Linux IPA üretimi doğrulandı.

## 3. Tek uygulamayla gerçek Apple kabulünü kanıtlama

- [x] Önce hazır ve dağıtım imzalı IPA'yı yükleyen dar kapsamlı bir akış kur. Derleme, tester yönetimi ve yayımlama otomasyonunu henüz birleştirme.
- [x] Apple'ın Build Uploads API'siyle yükleme oluştur, dosya rezervasyonu al, verilen yükleme işlemlerini uygula ve dosyayı commit et.
- [x] Dosya boyutu ve checksum bilgisini doğrula. Büyük dosyayı gereksiz yere bütünüyle belleğe alma.
- [x] App Store Connect JWT'sini yalnız API isteklerinde kullan. Dosya yükleme adreslerine yalnız ilgili işlemin istediği başlıkları gönder; özel anahtarları ve imzalı URL parametrelerini loglama.
- [x] Yükleme sonrasında Apple'ın işleme sonucunu izle. Yerel veya aktarım hatasıyla Apple'ın paket doğrulama reddini ayır.
- [x] Önce iOS uygulamasının, ardından Watch ve uzantı içeren paketin TestFlight'ta işlenmesini doğrula. Bulunan paketleme eksiklerini ikinci aşamada düzelt.

**Tamamlanma ölçütü:** xtool ile hazırlanan örnek IPA Apple tarafından işlenmiş ve TestFlight'ta kullanılabilir durumda. Companion Watch paketi için de ayrı doğrulama kaydı var. Bu kanıt olmadan uçtan uca Linux mağaza dağıtımı destekleniyor denmemeli.

**Durum: tamamlandı.** `xtool ds upload-build` mevcut dağıtım IPA'sını seçilmiş uygulama kaydıyla eşleştiriyor, yinelenen sürüm/build'i kontrol ediyor, rezervasyon/HTTPS parça aktarımı/MD5 commit işlemlerini yapıyor. Dosya en fazla 1 MiB parçalarla okunuyor; commit öncesi değişmediği yeniden kontrol ediliyor. `xtool ds build-upload-status` aynı yüklemeyi tekrar oluşturmadan Apple'ın upload ve build işleme durumlarını ayrı izliyor. Yalnız `COMPLETE` + `VALID`, kabul olarak raporlanıyor. Mevcut HTTP dependency ve ASC JWT üreticisi kullanılıyor; upload adreslerine JWT eklenmiyor.

Gerçek hesap doğrulamasında önce yalnız iOS içeren `1.0.0 (102)` kabul edildi. Watch/widget içeren `103` reddedildi: Apple 90502 ile widget'ta `UIRequiredDeviceCapabilities.arm64`, 90733 ile watchOS 27 altı için hem `arm64` hem `arm64_32` istedi. Dağıtım packer'ı iki Watch dilimini ve gömülü Mach-O kütüphanelerini birleştirecek, iOS uzantılarının cihaz yeteneklerini koruyarak arm64 ekleyecek şekilde düzeltildi. Geliştirme mimarisi seçimi aynı kaldı.

Düzeltilmiş iOS + Watch + widget paketi `1.0.0 (104)` de Apple tarafından `COMPLETE` + `VALID` ile kabul edildi. Apple'ın build bundle kaydında ana executable, Watch executable ve widget executable görüldü. Kullanıcıdan ayrıca alınan açık onayla yalnız bu doğrulama build'lerine `usesNonExemptEncryption=false` beyanı uygulandı. Hem 102 hem 104 için internal durum `READY_FOR_BETA_TESTING`, external durum `READY_FOR_BETA_SUBMISSION` olarak yeniden okundu.

`xtool Internal` grubunda hâlâ sıfır tester ve sıfır build olduğu API ile doğrulandı. Kullanıcı daveti, gruba build ataması, Beta App Review veya App Store yayımlaması yapılmadı. Gerçek TestFlight cihaz kurulumu henüz doğrulanmadı; beşinci aşamada yapılacak. Hesaba özel upload/build kimlikleri ve sonuçlar Git dışındaki `.build/milestone3-validation.json` içinde. Bu aşamada GitHub dalı, push veya PR oluşturulmadı.

91 testlik paket ve `make lint` geçti (gerçek hesap/yerel IPA gerektiren iki opt-in test varsayılan çalıştırmada atlanıyor). Yanlış uygulama/yinelenen build, parça aralıkları, sınırlı bellekle okuma, kaynak dosyanın değişmesi, aktarım hatası ve URL gizliliği, izin hatası, iptal ve Apple işleme reddi için kontroller var. Aynı 102 IPA'sını tekrar yükleme girişimi gerçek API kontrolünde yeni upload oluşturmadan reddedildi. Otomatik retry, kaldığı parçadan devam ve birleşik deploy komutu dördüncü aşamaya bırakıldı.

## 4. `xtool deploy testflight` ilk sürümü

- [ ] Kanıtlanan akışı CLI'a bağla: uygulama kaydını bul, release IPA hazırla, dağıtım için imzala, yükle ve sonucu raporla.
- [ ] Sorunları ayırabilmek için hazır IPA yükleme yolunu da koru; bunun için ikinci bir bağımsız yükleyici geliştirme.
- [ ] Mevcut App Store Connect kimlik doğrulamasını ve HTTP istemcisini yeniden kullan. Gerekli Build Uploads kaynaklarını mevcut API üretim akışına ekle veya mevcut istemci katmanında destekle.
- [ ] İptal, ağ kesilmesi, zaman aşımı ve geçici sunucu hatalarını ele al. Yeniden denemede aynı build'i kontrolsüz biçimde yeniden oluşturma/yükleme.
- [ ] İşlem kimliği, sürüm, build numarası ve App Store Connect bağlantısını göster. Yalnız aktarım tamamlandıysa sonucu “TestFlight hazır” olarak raporlama.
- [ ] Hatalı kimlik doğrulama, eksik profil, yinelenen build numarası ve Apple işleme reddinde uygun hata ve başarısız çıkış kodu ver.

**Tamamlanma ölçütü:** Komut doğrulama uygulamasını tek akışta TestFlight'a taşıyor; başarısız aşamayı açıkça bildiriyor.

## 5. TestFlight kullanıcılarına dağıtım

- [ ] İşlenmiş build'i kullanıcının seçtiği mevcut internal test grubuna bağla; otomatik olarak yeni tester veya grup oluşturma.
- [ ] Gerekli beta açıklamaları ve export compliance yanıtlarını kullanıcıdan al; beyanları kendiliğinden varsayma.
- [ ] İkinci adım olarak external grupları ve gerekli Beta App Review sürecini destekle. İnceleme bekleyen build'i dış testçilere dağıtılmış sayma.
- [ ] Gerçek tester hesabıyla iPhone kurulumu ve companion Watch kurulumu doğrula.

**Tamamlanma ölçütü:** Seçilen test grubundaki kullanıcı uygulamayı TestFlight üzerinden kurabiliyor; Watch sürümü de doğrulanmış.

## 6. App Store inceleme ve yayımlama

- [ ] Aynı işlenmiş build'i App Store sürümüne bağlayan akışı ekle; TestFlight ve App Store için ayrı yükleyiciler yazma.
- [ ] Açıklama, ekran görüntüleri, gizlilik bilgileri, destek adresleri ve inceleme bilgileri gibi eksikleri kontrol edip raporla.
- [ ] Kullanıcının açık talebiyle incelemeye gönderme desteği ekle. TestFlight'a yükleme komutu bu işlemi tetiklememeli.
- [ ] İnceleme durumu, ret gerekçesi ve yayımlama durumunu göster. Apple'ın inceleme kararını CLI başarısı olarak önden ilan etme.
- [ ] Otomatik veya manuel yayımlama seçimini kullanıcıya bırak; yayımlamayı yükleme işleminden ayrı bir eylem olarak tut.

**Tamamlanma ölçütü:** Onaylı bir build, seçilen yayımlama yöntemiyle App Store'a çıkarılabiliyor; durumlar ayrı ayrı doğrulanıyor.

## 7. Testler, CI ve kullanım dokümantasyonu

Bu kontroller her aşamanın kendi değişikliğiyle birlikte eklenmeli; son aşamaya ertelenmemeli.

- [ ] Dağıtım sertifikası/profili seçimi, gerçek bundle ID'leri ve entitlements için birim testleri ekle.
- [ ] iOS + Watch + uzantı paketleri için fixture'lar ve paket doğrulama testleri ekle.
- [ ] Upload rezervasyonu, checksum, dosya commit'i, işleme reddi, yetki hatası, yeniden deneme ve iptal senaryolarını sahte HTTP yanıtlarıyla test et.
- [ ] Geliştirme sertifikalarının/profillerinin korunmasını ve mevcut `xtool dev` akışının çalışmasını regresyon testleriyle güvenceye al.
- [ ] Her desteklenen ortamda ilgili testleri ve `make lint` kontrolünü çalıştır. Gerçek Apple yüklemesini ayrı, kontrollü bir doğrulama işi olarak tut.
- [ ] API anahtarlarının saklanması, gerekli yetkiler, sürüm/build numarası kullanımı, Watch sınırlamaları ve hata giderme adımlarını README ve CLI yardımına ekle.
- [ ] CI örneğinde secret'ları güvenli ortamdan al; fork PR'larına dağıtım anahtarlarını açma ve her push'ta otomatik mağaza dağıtımı başlatma.

**Tamamlanma ölçütü:** Yeni kullanıcı belgelenmiş adımlarla akışı tekrarlayabiliyor; CI testleri anahtar veya gerçek mağaza yüklemesi gerektirmiyor.

## İlk teslimat sınırı

İlk kullanılabilir sürüm için **0 → 1 → 2 → 3 → 4** sırası tamamlanmalı. Testler her aşamada eklenmeli. Tester grupları, external review ve App Store yayımlaması daha sonra gelmeli. Yeni bağımlılıklar veya genel amaçlı bir dağıtım sistemi, mevcut katmanlar yetersiz kalmadan eklenmemeli.

## Resmi kaynaklar

- [Apple — Build uploads API](https://developer.apple.com/documentation/appstoreconnectapi/build-uploads)
- [Apple — Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple — Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
- [Apple — Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple — Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Apple — Xcode command-line tool reference (`actool`)](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
