import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_models.dart';
import 'buddy_finder_view_model.dart';
import 'buddy_labels.dart';
import 'buddy_navigation.dart';
import 'buddy_profile_card.dart';
import 'buddy_ui_actions.dart';

/// Opens the full public profile of [uid] (taken live from [vm]) in a bottom
/// sheet with the same actions as the card.
Future<void> showBuddyProfileSheet(
  BuildContext context, {
  required BuddyFinderViewModel vm,
  required String uid,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<BuddyFinderViewModel>.value(
      value: vm,
      child: BuddyProfileSheet(uid: uid),
    ),
  );
}

class BuddyProfileSheet extends StatelessWidget {
  const BuddyProfileSheet({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BuddyFinderViewModel>();
    final p = vm.profileById(uid);
    // The sheet has its own messenger so snackbars show above it.
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: p == null
            ? const EmptyState(title: 'Profile not available', icon: Icons.person_off_outlined)
            : _SheetBody(vm: vm, profile: p),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.vm, required this.profile});

  final BuddyFinderViewModel vm;
  final BuddyProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = profile;
    final hostel = vm.hostelName(p.hostelId);
    final prefs = preferenceSummary(p);
    final busy = vm.isBusy(p.uid);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: [
        Center(child: AvatarCircle(name: p.displayName, photoUrl: p.photoUrl, radius: 40)),
        const SizedBox(height: AppSpacing.sm + 4),
        Text(p.displayName, style: t.titleLarge, textAlign: TextAlign.center),
        if (hostel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hostel,
              style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            RelationBadge(p.relation),
            if (p.fitnessLevel != null) BuddyPill(p.fitnessLevel!.label, highlight: true),
            if (p.buddyType != null) BuddyPill(p.buddyType!.label),
          ],
        ),
        if (p.weeklyVerifiedSteps != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            color: AppColors.mint,
            shadow: false,
            child: Row(
              children: [
                const Icon(Icons.directions_walk, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Text(
                    '${formatSteps(p.weeklyVerifiedSteps!)} verified steps this week',
                    style: t.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (p.bio.isNotEmpty) _Section('About', child: Text(p.bio, style: t.bodyMedium)),
        if (p.sportsInterests.isNotEmpty)
          _Section('Sports', child: _PillWrap(p.sportsInterests)),
        if (prefs != null) _Section('Preferred activity', child: Text(prefs, style: t.bodyMedium)),
        if (p.goals.isNotEmpty) _Section('Fitness goals', child: _PillWrap(p.goals)),
        if (p.availability.isNotEmpty)
          _Section(
            'Available on',
            child: _PillWrap([
              for (final d in BuddyFilters.weekdays)
                if (p.availability.contains(d)) dayLabel(d),
            ]),
          ),
        const SizedBox(height: AppSpacing.md),
        BuddyRelationActions(
          relation: p.relation,
          busy: busy,
          onSend: () => BuddyFinderActions.sendRequest(context, vm, p),
          onCancel: () => BuddyFinderActions.cancelRequest(context, vm, p),
          onAccept: () => BuddyFinderActions.respond(context, vm, p, accept: true),
          onReject: () => BuddyFinderActions.respond(context, vm, p, accept: false),
        ),
        if (p.relation == BuddyRelation.buddy) ...[
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Challenge',
                  icon: Icons.emoji_events_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    openBuddyChallenge(context, p.uid);
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Step bet',
                  icon: Icons.casino_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    openBuddyBet(context, p.uid);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Remove buddy',
            icon: Icons.person_remove_outlined,
            onPressed: busy ? null : () => BuddyFinderActions.remove(context, vm, p),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton.icon(
            onPressed: busy ? null : () => BuddyFinderActions.report(context, vm, p),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Report profile'),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _PillWrap extends StatelessWidget {
  const _PillWrap(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final s in items) BuddyPill(s)],
      );
}
