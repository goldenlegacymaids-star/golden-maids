/// Route paths used across the app.
///
/// Always navigate with these constants rather than typing paths by hand.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';

  // Authentication
  static const String welcome = '/welcome';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String verifyCode = '/verify-code';
  static const String forgotPassword = '/forgot-password';
  static const String newPassword = '/new-password';

  // Main tabs (bottom navigation)
  static const String home = '/home';
  static const String bookings = '/bookings';
  static const String wallet = '/wallet';
  static const String profile = '/profile';

  // Inside the Home tab
  static const String search = '/home/search';
  static const String notifications = '/home/notifications';
  static const String maids = '/home/maids';
  static String category(String slug) => '/home/category/$slug';
  static String service(String slug) => '/home/service/$slug';

  // Profile
  static const String editProfile = '/profile/edit';

  /// Development screen showing every design-system component
  /// (not available in production builds).
  static const String designPreview = '/dev/design-preview';

  /// Where the app goes after onboarding.
  static const String afterOnboarding = welcome;

  /// Screens only for signed-out users; signed-in users are sent home.
  static const Set<String> guestOnly = {welcome, signIn, signUp, forgotPassword};
}
