import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app (phone dialler, WhatsApp, email, browser).
/// Returns false when nothing on the device can open it.
typedef ExternalLauncher = Future<bool> Function(Uri uri);

/// Replaced in tests, which cannot open other apps.
final externalLauncherProvider = Provider<ExternalLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
