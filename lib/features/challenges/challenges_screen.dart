import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/challenges/challenge_models.dart';
import '../../data/challenges/challenge_repository.dart';
import '../auth/session_controller.dart';
import 'challenge_logic.dart';
import 'challenge_widgets.dart';
import 'challenges_routes.dart';
import 'challenges_view_model.dart';

/// The Challenges tab: Individual / Buddy / Inter-Hostel / Campus discovery
/// plus "My challenges".
class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) {
      return const Scaffold(body: LoadingState());
    }
    return ChangeNotifierProvider<ChallengesViewModel>(
      key: ValueKey(user.uid),
      create: (c) => ChallengesViewModel(
        repository: c.read<ChallengeRepository>(),
        uid: user.uid,
        myHostelId: session.profile?.hostelId,
      )..start(),
      child: const _ChallengesView(),
    );
  }
}

class _ChallengesView extends StatelessWidget {
  const _ChallengesView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChallengesViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('Challenges')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChipsRow<ChallengeSegment>(
                  options: ChallengeSegment.values,
                  selected: vm.segment,
                  onSelected: vm.selectSegment,
                  labelOf: (s) => s.label,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => runAction(context, () => vm.refresh()),
                child: _SegmentBody(vm: vm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrollable that always supports pull-to-refresh, even when empty.
class _Scroll extends StatelessWidget {
  const _Scroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: children,
    );
  }
}

Widget _gap() => const SizedBox(height: AppSpacing.sm + 4);

class _SegmentBody extends StatelessWidget {
  const _SegmentBody({required this.vm});

  final ChallengesViewModel vm;

  @override
  Widget build(BuildContext context) {
    switch (vm.segment) {
      case ChallengeSegment.individual:
        return _OpenList(
          vm: vm,
          type: ChallengeType.individual,
          items: vm.individualCatalogue,
          note: 'Join a challenge and walk. Only verified steps count.',
          emptyTitle: 'No individual challenges yet',
          emptyMessage: 'New challenges appear here when they are published.',
        );
      case ChallengeSegment.interHostel:
        return _OpenList(
          vm: vm,
          type: ChallengeType.interHostel,
          items: vm.competitions(ChallengeType.interHostel),
          note: 'Hostels compete against each other. Competitions are created by the admin team.',
          emptyTitle: 'No hostel competitions right now',
          emptyMessage: 'Check back soon - upcoming hostel competitions are listed here.',
        );
      case ChallengeSegment.campus:
        return _OpenList(
          vm: vm,
          type: ChallengeType.campus,
          items: vm.competitions(ChallengeType.campus),
          note: 'Everyone on campus competes together. Campus challenges are created by the admin team.',
          emptyTitle: 'No campus challenges right now',
          emptyMessage: 'Check back soon - campus-wide challenges are listed here.',
        );
      case ChallengeSegment.buddy:
        return _BuddySegment(vm: vm);
      case ChallengeSegment.mine:
        return _MineSegment(vm: vm);
    }
  }
}

void _openDetail(BuildContext context, String id) => context.push(AppRoutes.challengeDetail(id));

class _OpenList extends StatelessWidget {
  const _OpenList({
    required this.vm,
    required this.type,
    required this.items,
    required this.note,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final ChallengesViewModel vm;
  final ChallengeType type;
  final List<Challenge> items;
  final String note;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final state = vm.open(type);
    if (state.loading) return const LoadingState();
    if (state.error != null) {
      return _Scroll(children: [
        ErrorState(message: state.error!, onRetry: () => vm.refresh()),
      ]);
    }
    final now = context.read<AppDependencies>().clock.now();
    if (items.isEmpty) {
      return _Scroll(children: [
        EmptyState(
          icon: Icons.emoji_events_outlined,
          title: emptyTitle,
          message: emptyMessage,
        ),
      ]);
    }
    return _Scroll(children: [
      NoteBanner(text: note),
      _gap(),
      for (final c in items) ...[
        ChallengeCard(
          key: ValueKey('challenge-${c.id}'),
          challenge: c,
          now: now,
          mine: vm.progressOf(c.id),
          caption: _caption(c),
          onTap: () => _openDetail(context, c.id),
        ),
        _gap(),
      ],
    ]);
  }

  String? _caption(Challenge c) {
    if (c.type != ChallengeType.interHostel) return null;
    final mine = vm.myHostelId;
    final competing = mine != null && c.hostelIds.contains(mine);
    return competing
        ? 'Your hostel is competing. ${aggregationRule(c)}'
        : 'Your hostel is not part of this competition. ${aggregationRule(c)}';
  }
}

class _BuddySegment extends StatelessWidget {
  const _BuddySegment({required this.vm});

  final ChallengesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final state = vm.mineState;
    final now = context.read<AppDependencies>().clock.now();
    final header = PrimaryButton(
      label: 'Challenge a buddy',
      icon: Icons.sports_score_outlined,
      onPressed: () => context.push(ChallengesRoutes.newBuddy),
    );
    if (state.loading) return const LoadingState();
    if (state.error != null) {
      return _Scroll(children: [ErrorState(message: state.error!, onRetry: () => vm.refresh())]);
    }
    final invites = vm.invitations;
    final sent = vm.sentInvitations;
    final active = vm.activeBuddyChallenges;
    final history = vm.buddyHistory;
    final empty = invites.isEmpty && sent.isEmpty && active.isEmpty && history.isEmpty;
    return _Scroll(children: [
      header,
      _gap(),
      if (vm.challengesError != null) ...[
        ErrorState(message: vm.challengesError!, onRetry: () => vm.refresh(), compact: true),
        _gap(),
      ],
      if (vm.loadingChallenges) const LinearProgressIndicator(),
      if (empty && !vm.loadingChallenges && vm.challengesError == null)
        const EmptyState(
          icon: Icons.sports_kabaddi_outlined,
          title: 'No buddy challenges yet',
          message: 'Challenge one of your buddies to see who walks more verified steps.',
        ),
      if (invites.isNotEmpty) ...[
        const SectionHeader('Invitations', subtitle: 'Your buddies challenged you'),
        for (final e in invites) ...[
          _InviteCard(vm: vm, entry: e, now: now),
          _gap(),
        ],
      ],
      if (sent.isNotEmpty) ...[
        const SectionHeader('Waiting for your buddy'),
        for (final e in sent) ...[
          ChallengeCard(
            key: ValueKey('challenge-${e.challenge.id}'),
            challenge: e.challenge,
            now: now,
            caption: 'It starts at the next midnight (IST) after your buddy accepts.',
            onTap: () => _openDetail(context, e.challenge.id),
          ),
          _gap(),
        ],
      ],
      if (active.isNotEmpty) ...[
        const SectionHeader('Active and upcoming'),
        for (final e in active) ...[
          ChallengeCard(
            key: ValueKey('challenge-${e.challenge.id}'),
            challenge: e.challenge,
            now: now,
            mine: e.mine,
            onTap: () => _openDetail(context, e.challenge.id),
          ),
          _gap(),
        ],
      ],
      if (history.isNotEmpty) ...[
        const SectionHeader('History'),
        for (final e in history) ...[
          ChallengeCard(
            key: ValueKey('challenge-${e.challenge.id}'),
            challenge: e.challenge,
            now: now,
            mine: e.mine != null && e.mine!.hasProgress ? e.mine : null,
            onTap: () => _openDetail(context, e.challenge.id),
          ),
          _gap(),
        ],
      ],
    ]);
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.vm, required this.entry, required this.now});

  final ChallengesViewModel vm;
  final ChallengeEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final id = entry.challenge.id;
    final busy = vm.isBusy(id);
    return ChallengeCard(
      key: ValueKey('invite-$id'),
      challenge: entry.challenge,
      now: now,
      onTap: () => _openDetail(context, id),
      footer: Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: 'Decline',
              onPressed: busy
                  ? null
                  : () => runAction(context, () => vm.respondToInvite(id, accept: false)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Accept',
              loading: busy,
              onPressed: () => runAction(context, () => vm.respondToInvite(id, accept: true)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MineSegment extends StatelessWidget {
  const _MineSegment({required this.vm});

  final ChallengesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final state = vm.mineState;
    if (state.loading) return const LoadingState();
    if (state.error != null) {
      return _Scroll(children: [ErrorState(message: state.error!, onRetry: () => vm.refresh())]);
    }
    final now = context.read<AppDependencies>().clock.now();
    final list = vm.myChallenges;
    if (list.isEmpty) {
      return _Scroll(children: [
        if (vm.challengesError != null)
          ErrorState(message: vm.challengesError!, onRetry: () => vm.refresh())
        else if (vm.loadingChallenges)
          const LoadingState()
        else
          EmptyState(
            icon: Icons.directions_walk,
            title: 'You have not joined a challenge yet',
            message: 'Pick a challenge and start walking. Only verified steps count.',
            actionLabel: 'Browse challenges',
            onAction: () => vm.selectSegment(ChallengeSegment.individual),
          ),
      ]);
    }
    return _Scroll(children: [
      for (final e in list) ...[
        ChallengeCard(
          key: ValueKey('challenge-${e.challenge.id}'),
          challenge: e.challenge,
          now: now,
          mine: e.mine,
          onTap: () => _openDetail(context, e.challenge.id),
        ),
        _gap(),
      ],
    ]);
  }
}
