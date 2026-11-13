import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../challenges/challenges_routes.dart';

/// Location of the "challenge a buddy" form with [buddyUid] pre-selected
/// (`/challenges/new-buddy?buddy=<uid>`, owned by the challenges feature).
String buddyChallengeLocation(String buddyUid) => ChallengesRoutes.newBuddyFor(buddyUid);

/// Location of the step-bet creation screen with [buddyUid] pre-selected
/// (`/bets/new?buddy=<uid>`).
String buddyBetLocation(String buddyUid) =>
    Uri(path: AppRoutes.betsCreate, queryParameters: {'buddy': buddyUid}).toString();

/// Opens the buddy-challenge form (inside the Challenges tab) for [buddyUid].
void openBuddyChallenge(BuildContext context, String buddyUid) =>
    context.go(buddyChallengeLocation(buddyUid));

/// Opens the step-bet creation screen (above the shell) for [buddyUid].
void openBuddyBet(BuildContext context, String buddyUid) =>
    context.push(buddyBetLocation(buddyUid));
