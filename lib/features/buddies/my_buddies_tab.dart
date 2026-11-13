import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_directory.dart';
import 'buddy_dialogs.dart';
import 'buddy_navigation.dart';
import 'buddy_ui_actions.dart';
import 'my_buddies_view_model.dart';

/// "My buddies" tab: accepted buddies with Challenge / Step bet shortcuts and
/// Remove / Report.
class MyBuddiesTab extends StatelessWidget {
  const MyBuddiesTab({super.key, this.onFindBuddies});

  /// Called by the empty state's button (switches to the finder tab).
  final VoidCallback? onFindBuddies;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyBuddiesViewModel>();
    if (vm.error != null) {
      return ErrorState(message: vm.error!.message, onRetry: vm.retry);
    }
    final list = vm.buddies;
    if (list == null) return const LoadingState();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.group_add_outlined,
        title: 'No buddies yet',
        message: 'Find a student with similar goals and send a buddy request.',
        actionLabel: onFindBuddies == null ? null : 'Find buddies',
        onAction: onFindBuddies,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md - 4),
      itemBuilder: (context, i) => _BuddyTile(key: ValueKey('mybuddy_${list[i].uid}'), buddy: list[i]),
    );
  }
}

enum _BuddyMenu { remove, report }

class _BuddyTile extends StatelessWidget {
  const _BuddyTile({super.key, required this.buddy});

  final BuddySummary buddy;

  Future<void> _remove(BuildContext context, MyBuddiesViewModel vm) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmRemoveBuddy(context, buddy.displayName);
    if (!ok) return;
    showBuddyResult(messenger, await vm.remove(buddy));
  }

  Future<void> _report(BuildContext context, MyBuddiesViewModel vm) async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showReportDialog(context, buddy.displayName);
    if (choice == null) return;
    showBuddyResult(
      messenger,
      await vm.report(buddy, choice.reason, details: choice.details),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MyBuddiesViewModel>();
    final t = Theme.of(context).textTheme;
    final hostel = vm.hostelName(buddy.hostelId);
    final busy = vm.isBusy(buddy.uid);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarCircle(name: buddy.displayName, photoUrl: buddy.photoUrl, radius: 24),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buddy.displayName,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hostel != null)
                      Text(
                        hostel,
                        style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                PopupMenuButton<_BuddyMenu>(
                  tooltip: 'More options',
                  onSelected: (m) => switch (m) {
                    _BuddyMenu.remove => _remove(context, vm),
                    _BuddyMenu.report => _report(context, vm),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _BuddyMenu.remove, child: Text('Remove buddy')),
                    PopupMenuItem(value: _BuddyMenu.report, child: Text('Report profile')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Challenge',
                  icon: Icons.emoji_events_outlined,
                  onPressed: () => openBuddyChallenge(context, buddy.uid),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Step bet',
                  icon: Icons.casino_outlined,
                  onPressed: () => openBuddyBet(context, buddy.uid),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
