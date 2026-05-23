import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/pronunciation/pronunciation_screen.dart';
import '../../features/sessions/sessions_screen.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/templates/templates_screen.dart';
import '../../features/vocabulary/review_screen.dart';
import '../../features/vocabulary/vocabulary_screen.dart';
import '../../shared/providers/app_providers.dart';

class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const sessions = '/sessions';
  static const templates = '/templates';
  static const profile = '/profile';
  static const vocabulary = '/vocabulary';
  static const review = '/review';
  static const stats = '/stats';
  static const pronunciation = '/pronunciation';
  static const chat = '/chat'; // /chat/:sessionId
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (auth.isLoading) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }
      // Bootstrap xong: splash phải đi tiếp
      if (loc == AppRoutes.splash) {
        return auth.isAuthenticated ? AppRoutes.home : AppRoutes.welcome;
      }
      final isAuthRoute = loc == AppRoutes.welcome ||
          loc == AppRoutes.login ||
          loc == AppRoutes.register;
      if (!auth.isAuthenticated && !isAuthRoute) return AppRoutes.welcome;
      if (auth.isAuthenticated && isAuthRoute) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.sessions,
        builder: (_, _) => const SessionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.templates,
        builder: (_, _) => const TemplatesScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.vocabulary,
        builder: (_, _) => const VocabularyScreen(),
      ),
      GoRoute(
        path: AppRoutes.review,
        builder: (_, _) => const ReviewScreen(),
      ),
      GoRoute(
        path: AppRoutes.stats,
        builder: (_, _) => const StatsScreen(),
      ),
      GoRoute(
        path: AppRoutes.pronunciation,
        builder: (_, _) => const PronunciationScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.chat}/:sessionId',
        builder: (_, state) => ChatScreen(
          sessionId: state.pathParameters['sessionId']!,
          initialTitle: state.uri.queryParameters['title'],
        ),
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}
