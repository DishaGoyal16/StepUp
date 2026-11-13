/// Route paths for the WHOLE app (all features). Feature engineers use these
/// constants for navigation (`context.go(AppRoutes.buddies)`) and for their
/// `GoRoute.path` definitions. Sub-routes are declared relative to their
/// parent (e.g. `GoRoute(path: 'requests')` under `/buddies`).
abstract final class AppRoutes {
  // --- auth / bootstrap (outside the shell) ---
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String verifyEmail = '/verify-email';
  static const String onboarding = '/onboarding';

  // --- shell tab 1: Home ---
  static const String home = '/home';
  static const String stepHistory = '/home/history';

  // --- shell tab 2: Buddies ---
  static const String buddies = '/buddies';
  static const String buddyRequests = '/buddies/requests';

  // --- shell tab 3: Challenges ---
  static const String challenges = '/challenges';
  static const String challengeDetailPattern = '/challenges/:id';
  static String challengeDetail(String id) => '/challenges/$id';

  // --- shell tab 4: Leaderboard ---
  static const String leaderboard = '/leaderboard';

  // --- shell tab 5: Profile ---
  static const String profile = '/profile';

  // --- full-screen routes above the shell ---
  static const String bets = '/bets';
  static const String betsCreate = '/bets/new';
  static const String betDetailPattern = '/bets/:id';
  static String betDetail(String id) => '/bets/$id';

  static const String notifications = '/notifications';

  static const String admin = '/admin';
  static const String adminStudents = '/admin/students';
  static const String adminHostels = '/admin/hostels';
  static const String adminChallenges = '/admin/challenges';
  static const String adminReports = '/admin/reports';
  static const String adminRisk = '/admin/risk';
  static const String adminSettings = '/admin/settings';

  /// Paths only reachable while signed out / not set up.
  static const Set<String> publicAuthPaths = {login, register, forgotPassword};

  /// Auth + bootstrap paths a fully set-up user is bounced away from.
  static const Set<String> preAppPaths = {
    splash,
    login,
    register,
    forgotPassword,
    verifyEmail,
    onboarding,
  };
}
