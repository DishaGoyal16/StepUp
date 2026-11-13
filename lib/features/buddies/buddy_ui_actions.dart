import 'package:flutter/material.dart';

import '../../data/buddies/buddy_models.dart';
import 'buddy_action_result.dart';
import 'buddy_dialogs.dart';
import 'buddy_finder_view_model.dart';

/// Shows [result] in a snackbar of [messenger] (skipped when the messenger is
/// already gone, e.g. the profile sheet was closed meanwhile).
void showBuddyResult(ScaffoldMessengerState messenger, BuddyActionResult result) {
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.message)));
}

/// The student-level actions shared by the finder cards and the profile
/// sheet. Each one asks for confirmation / input when needed, calls the view
/// model and reports the outcome in a snackbar.
abstract final class BuddyFinderActions {
  static Future<void> sendRequest(
    BuildContext context,
    BuddyFinderViewModel vm,
    BuddyProfile p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await showSendRequestDialog(context, p.displayName);
    if (message == null) return;
    showBuddyResult(messenger, await vm.sendRequest(p, message: message));
  }

  static Future<void> cancelRequest(
    BuildContext context,
    BuddyFinderViewModel vm,
    BuddyProfile p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    showBuddyResult(messenger, await vm.cancelRequest(p));
  }

  static Future<void> respond(
    BuildContext context,
    BuddyFinderViewModel vm,
    BuddyProfile p, {
    required bool accept,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    showBuddyResult(messenger, await vm.respond(p, accept: accept));
  }

  static Future<void> remove(
    BuildContext context,
    BuddyFinderViewModel vm,
    BuddyProfile p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmRemoveBuddy(context, p.displayName);
    if (!ok) return;
    showBuddyResult(messenger, await vm.removeBuddy(p));
  }

  static Future<void> report(
    BuildContext context,
    BuddyFinderViewModel vm,
    BuddyProfile p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showReportDialog(context, p.displayName);
    if (choice == null) return;
    showBuddyResult(
      messenger,
      await vm.report(p, choice.reason, details: choice.details),
    );
  }
}
