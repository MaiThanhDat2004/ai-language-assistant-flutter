import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/auth_api.dart';
import '../../core/api/audio_api.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/languages_api.dart';
import '../../core/api/sessions_api.dart';
import '../../core/api/templates_api.dart';
import '../../core/api/vocabulary_api.dart';
import '../../core/api/stats_api.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/audio/voice_recorder.dart';
import '../../core/auth/token_storage.dart';
import '../../core/models/user.dart';
import '../../core/theme/app_colors.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return ApiClient(
    tokenStorage: storage,
    onUnauthorized: () async {
      ref.read(authStateProvider.notifier).logoutLocal();
    },
  );
});

final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final templatesApiProvider = Provider<TemplatesApi>(
    (ref) => TemplatesApi(ref.watch(apiClientProvider)));
final sessionsApiProvider = Provider<SessionsApi>(
    (ref) => SessionsApi(ref.watch(apiClientProvider)));
final chatApiProvider =
    Provider<ChatApi>((ref) => ChatApi(ref.watch(apiClientProvider)));
final languagesApiProvider = Provider<LanguagesApi>(
    (ref) => LanguagesApi(ref.watch(apiClientProvider)));
final audioApiProvider =
    Provider<AudioApi>((ref) => AudioApi(ref.watch(apiClientProvider)));
final vocabularyApiProvider = Provider<VocabularyApi>(
    (ref) => VocabularyApi(ref.watch(apiClientProvider)));
final statsApiProvider =
    Provider<StatsApi>((ref) => StatsApi(ref.watch(apiClientProvider)));

// Audio services — singleton qua app lifecycle vì stateful (player, recorder)
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final r = VoiceRecorder();
  ref.onDispose(() => r.dispose());
  return r;
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final p = AudioPlayerService();
  ref.onDispose(() => p.dispose());
  return p;
});

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;

  const AuthState({required this.isLoading, required this.isAuthenticated});

  const AuthState.initial()
      : isLoading = true,
        isAuthenticated = false;

  AuthState copyWith({bool? isLoading, bool? isAuthenticated}) => AuthState(
        isLoading: isLoading ?? this.isLoading,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      );
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final Ref ref;

  AuthStateNotifier(this.ref) : super(const AuthState.initial()) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final storage = ref.read(tokenStorageProvider);
      final has = await storage.hasTokens;
      state = AuthState(isLoading: false, isAuthenticated: has);
    } catch (e, st) {
      // ignore: avoid_print
      print('Auth bootstrap failed: $e\n$st');
      state = const AuthState(isLoading: false, isAuthenticated: false);
    }
  }

  void setAuthenticated(bool value) {
    state = state.copyWith(isLoading: false, isAuthenticated: value);
  }

  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final refresh = await storage.refreshToken;
    if (refresh != null) {
      try {
        await ref.read(authApiProvider).logout(refresh);
      } catch (_) {}
    }
    await storage.clear();
    setAuthenticated(false);
  }

  Future<void> logoutLocal() async {
    final storage = ref.read(tokenStorageProvider);
    await storage.clear();
    setAuthenticated(false);
  }
}

final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier(ref);
});

final languagesProvider = FutureProvider<List>((ref) async {
  return ref.read(languagesApiProvider).list();
});

// User profile — global cache, dùng cho greeting / avatar / preferred_language
// trên Home, Profile, ... Invalidate sau khi updateProfile để refresh.
final meProvider = FutureProvider<User>((ref) async {
  return ref.read(authApiProvider).getMe();
});

// ==========================================================
// Theme mode — persist qua TokenStorage, sync với AppColors static
// ==========================================================
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final Ref ref;
  ThemeModeNotifier(this.ref) : super(ThemeMode.light) {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final storage = ref.read(tokenStorageProvider);
    final saved = await storage.themeMode;
    final mode = switch (saved) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    // Sync AppColors static palette với mode persist được
    AppColors.setDarkMode(mode == ThemeMode.dark);
    state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.setThemeMode(switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    });
    AppColors.setDarkMode(mode == ThemeMode.dark);
    state = mode;
  }

  Future<void> toggle() async {
    await set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});
