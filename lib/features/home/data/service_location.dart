import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/uae.dart';
import '../../../core/services/shared_preferences_provider.dart';

/// The emirate the customer wants services in. Stored on the device.
/// (Saved addresses replace this in Phase 3.)
class ServiceLocationNotifier extends Notifier<String> {
  static const String storageKey = 'service_location_emirate';

  @override
  String build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(storageKey);
    return UaeEmirates.all.contains(saved)
        ? saved!
        : UaeEmirates.defaultEmirate;
  }

  Future<void> select(String emirate) async {
    if (!UaeEmirates.all.contains(emirate)) return;
    state = emirate;
    await ref.read(sharedPreferencesProvider).setString(storageKey, emirate);
  }
}

final serviceLocationProvider =
    NotifierProvider<ServiceLocationNotifier, String>(
      ServiceLocationNotifier.new,
    );
