import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 앱에 포함한 터미널 폰트(패밀리 이름 → OFL 라이선스 asset).
const bundledTerminalFontLicenses = {
  'Cascadia Mono': 'assets/fonts/cascadia/OFL.txt',
  'Cascadia Code': 'assets/fonts/cascadia/OFL.txt',
  'JetBrains Mono': 'assets/fonts/jetbrains_mono/OFL.txt',
  'D2Coding': 'assets/fonts/d2coding/OFL.txt',
};

/// 포함한 폰트의 OFL 고지를 라이선스 화면에 등록한다. OFL은 폰트와 함께
/// 라이선스를 배포하도록 요구한다.
void registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final byAsset = <String, List<String>>{};
    bundledTerminalFontLicenses.forEach(
      (family, asset) => (byAsset[asset] ??= []).add(family),
    );
    for (final MapEntry(key: asset, value: families) in byAsset.entries) {
      yield LicenseEntryWithLineBreaks(
        families,
        await rootBundle.loadString(asset),
      );
    }
  });
}
