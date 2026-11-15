/// Route paths used across the app.
///
/// Always navigate with these constants rather than typing paths by hand.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';

  /// Development screen showing every design-system component.
  static const String designPreview = '/dev/design-preview';

  /// Where the app goes after onboarding.
  /// TEMPORARY: becomes the sign-in screen in Step 1.5.
  static const String afterOnboarding = designPreview;
}
