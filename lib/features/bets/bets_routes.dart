import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import 'bet_detail_screen.dart';
import 'bets_screen.dart';
import 'create_bet_screen.dart';
import 'ledger_screen.dart';

/// Routes of the bets feature. Full-screen routes above the shell.
///
/// `new` and `ledger` are declared BEFORE `:id` so they are never parsed as a
/// bet id. `/bets/new` accepts `?buddy=<uid>`.
final List<RouteBase> betsRoutes = [
  GoRoute(
    path: AppRoutes.bets,
    builder: (context, state) => const BetsScreen(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) =>
            CreateBetScreen(presetBuddyUid: state.uri.queryParameters['buddy']),
      ),
      GoRoute(
        path: 'ledger',
        builder: (context, state) => const LedgerScreen(),
      ),
      GoRoute(
        path: ':id',
        builder: (context, state) => BetDetailScreen(betId: state.pathParameters['id']!),
      ),
    ],
  ),
];
