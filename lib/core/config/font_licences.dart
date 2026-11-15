import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/app_assets.dart';

/// Adds the bundled fonts' SIL Open Font Licences to the app's licences page,
/// as the licence requires.
void registerFontLicences() {
  LicenseRegistry.addLicense(_fontLicences);
}

Stream<LicenseEntry> _fontLicences() async* {
  const fonts = [
    ('Poppins', AppAssets.poppinsLicence),
    ('Inter', AppAssets.interLicence),
  ];
  for (final (family, path) in fonts) {
    final text = await rootBundle.loadString(path);
    yield LicenseEntryWithLineBreaks([family], text);
  }
}
