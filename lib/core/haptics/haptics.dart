import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/shared_preferences_provider.dart';

/// The vibrations the app uses, from lightest to firmest.
enum HapticKind {
  /// A tick: switching tabs, choosing a filter or chip.
  selection,

  /// A light tap: saving a maid.
  light,

  /// A firmer tap: pull-to-refresh.
  medium,

  /// Two taps, light then firmer: a booking, request or document went
  /// through.
  success,

  /// Two firm taps: something failed or was refused.
  error,
}

/// Plays a vibration on the phone. Replaced in tests.
typedef HapticPlayer = Future<void> Function(HapticKind kind);

/// The phone's own haptics: no extra permission. They follow the phone's
/// "touch feedback" setting.
Future<void> playSystemHaptic(HapticKind kind) async {
  switch (kind) {
    case HapticKind.selection:
      await HapticFeedback.selectionClick();
    case HapticKind.light:
      await HapticFeedback.lightImpact();
    case HapticKind.medium:
      await HapticFeedback.mediumImpact();
    case HapticKind.success:
      await HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await HapticFeedback.mediumImpact();
    case HapticKind.error:
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await HapticFeedback.heavyImpact();
  }
}

final hapticPlayerProvider = Provider<HapticPlayer>((ref) => playSystemHaptic);

/// Profile → Vibration. On by default; remembered on the phone.
class HapticsEnabledNotifier extends Notifier<bool> {
  static const String storageKey = 'settings_vibration';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(storageKey) ?? true;

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, enabled);
  }
}

final hapticsEnabledProvider = NotifierProvider<HapticsEnabledNotifier, bool>(
  HapticsEnabledNotifier.new,
);

/// Vibrates for [kind], unless the customer turned vibration off. Safe to
/// call anywhere: it never throws and never waits.
void haptic(BuildContext context, HapticKind kind) {
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } on Object {
    return; // Outside the app (e.g. a widget shown on its own).
  }
  if (!container.read(hapticsEnabledProvider)) return;
  unawaited(_play(container.read(hapticPlayerProvider), kind));
}

Future<void> _play(HapticPlayer player, HapticKind kind) async {
  try {
    await player(kind);
  } on Object {
    // Vibration is a nicety: a phone without it simply stays still.
  }
}
