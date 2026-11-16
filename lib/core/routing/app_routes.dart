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

  // Candidate profile: full screen, above the bottom navigation.
  static const String candidatePrefix = '/maid/';
  static String candidate(String id) => '$candidatePrefix$id';

  /// Hiring form: full screen. With [candidateId], that maid is
  /// pre-selected.
  /// Booking a home service (signed-in only).
  static const String bookPrefix = '/book/';
  static String book(String slug) => '$bookPrefix$slug';

  static const String hirePath = '/hire';
  static String hire({String? candidateId}) => candidateId == null
      ? hirePath
      : '$hirePath?maid=${Uri.encodeQueryComponent(candidateId)}';

  // Profile
  static const String editProfile = '/profile/edit';
  static const String savedMaids = '/profile/saved-maids';
  static const String hiringRequests = '/profile/hiring-requests';
  static String hiringRequest(String id) => '$hiringRequests/$id';

  /// Development screen showing every design-system component
  /// (not available in production builds).
  static const String designPreview = '/dev/design-preview';

  /// Where the app goes after onboarding.
  static const String afterOnboarding = welcome;

  /// Screens only for signed-out users; signed-in users are sent home.
  static const Set<String> guestOnly = {welcome, signIn, signUp, forgotPassword};
}
