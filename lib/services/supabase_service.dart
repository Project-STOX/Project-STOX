import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> initializeIfConfigured() async {
    if (_initialized) {
      return;
    }

    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return;
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    _initialized = true;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'Supabase is not configured. Run with --dart-define=SUPABASE_URL and --dart-define=SUPABASE_ANON_KEY if legacy screens still require it.',
      );
    }
    return Supabase.instance.client;
  }
}
