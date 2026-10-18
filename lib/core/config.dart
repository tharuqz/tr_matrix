/// Backend settings — same public values the website uses.
/// Override at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://aybstbwgqdqfyvvvcwwr.supabase.co',
  );

  /// Your website — used to ask its server to send phone notifications.
  static const siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://trmatrix.top',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF5YnN0YndncWRxZnl2dnZjd3dyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyODYwNTAsImV4cCI6MjA5Njg2MjA1MH0.J0Kl1BYJzm2b7FjJx-2l4d7U1rFP47GZCiRAEfaIQtc',
  );
}
