/// Build-time settings.
///
/// Values are passed in when running or building the app:
///
/// ```bash
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// `env.json` is git-ignored. Copy `env.example.json` to create it.
///
/// SECURITY: only public client values belong here (the Supabase project URL
/// and its publishable key `sb_publishable_...`, which are safe because every
/// table is protected by Row Level Security). Never put the Supabase `service_role`
/// key, payment-gateway secrets or any other secret in this file or in
/// `env.json`. Secrets live only in Supabase Edge Function secrets.
abstract final class Env {
  /// `development` or `production`.
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isProduction => appEnv == 'production';

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
