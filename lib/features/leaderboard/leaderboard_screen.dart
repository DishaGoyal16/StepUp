import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/leaderboard/leaderboard_models.dart';
import '../../data/leaderboard/leaderboard_repository.dart';
import '../auth/session_controller.dart';
import 'leaderboard_format.dart';
import 'leaderboard_list.dart';
import 'leaderboard_view_model.dart';

/// Leaderboard tab: scope + period selectors, podium, ranked list, the
/// user's own rank pinned at the bottom when they are outside the list.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LeaderboardViewModel? _vm;
  String? _vmUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = Provider.of<SessionController>(context).profile;
    if (profile == null) return;
    if (_vm == null || _vmUid != profile.uid) {
      _vm?.dispose();
      final deps = context.read<AppDependencies>();
      _vmUid = profile.uid;
      _vm = LeaderboardViewModel(
        repository: context.read<LeaderboardRepository>(),
        uid: profile.uid,
        myHostelId: profile.hostelId.isEmpty ? null : profile.hostelId,
        myName: profile.displayName,
        dailyGoal: profile.dailyGoal,
        loadHostels: deps.hostels.load,
      )..start();
    }
  }

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leaderboard')),
        body: const LoadingState(),
      );
    }
    final clock = context.read<AppDependencies>().clock;
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: vm.refresh,
                      child: ListView(
                        key: const Key('leaderboard-scroll'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          _Selectors(vm: vm),
                          const SizedBox(height: 12),
                          _Body(vm: vm, now: clock.now()),
                          const SizedBox(height: 8),
                          const _Footnotes(),
                        ],
                      ),
                    ),
                  ),
                  if (vm.showPinnedMe) _PinnedMe(vm: vm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Selectors extends StatelessWidget {
  const _Selectors({required this.vm});

  final LeaderboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChipsRow<LeaderboardScope>(
          options: LeaderboardScope.values,
          selected: vm.scope,
          onSelected: vm.selectScope,
          labelOf: (s) => s.label,
        ),
        FilterChipsRow<LeaderboardPeriod>(
          options: LeaderboardPeriod.values,
          selected: vm.period,
          onSelected: vm.selectPeriod,
          labelOf: (p) => p.label,
        ),
        if (vm.isHostelBoard) ...[
          const SizedBox(height: 8),
          Text('Hostel ranking metric', style: t.labelMedium?.copyWith(color: AppColors.textMuted)),
          FilterChipsRow<HostelMetric>(
            options: HostelMetric.values,
            selected: vm.hostelMetric,
            onSelected: vm.selectHostelMetric,
            labelOf: (m) => m.label,
          ),
        ],
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vm, required this.now});

  final LeaderboardViewModel vm;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    switch (vm.status) {
      case LeaderboardStatus.loading:
        return const SizedBox(height: 260, child: LoadingState(label: 'Loading leaderboard'));
      case LeaderboardStatus.error:
        return SizedBox(
          height: 300,
          child: ErrorState(
            message: vm.error?.message ?? 'Could not load the leaderboard.',
            onRetry: vm.refresh,
          ),
        );
      case LeaderboardStatus.ready:
        final r = vm.result!;
        final t = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              metaLine(r, now),
              key: const Key('leaderboard-meta'),
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            if (vm.refreshError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Could not refresh. ${vm.refreshError!.message}',
                  key: const Key('leaderboard-refresh-error'),
                  style: t.bodySmall?.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 12),
            if (r.isEmpty)
              _EmptyBoard(vm: vm)
            else ...[
              AppCard(
                child: PodiumWidget(
                  entries: [for (final e in r.entries.take(3)) _podiumEntry(vm, e)],
                ),
              ),
              const SectionHeader('Rankings'),
              LeaderboardList(
                entries: r.entries,
                isMine: vm.isMine,
                hostelNameOf: vm.hostelNameOf,
                progressBase: vm.progressBase,
                hostelMetric: r.query.hostelMetric,
              ),
              if (vm.notRanked) const _NotRankedHint(),
            ],
          ],
        );
    }
  }

  PodiumEntry _podiumEntry(LeaderboardViewModel vm, LeaderboardEntry e) {
    final value = formatSteps(e.value);
    final label = e.isHostel
        ? (vm.hostelMetric == HostelMetric.average ? '$value avg' : '$value total')
        : '$value steps';
    return PodiumEntry(
      name: e.isHostel ? (vm.hostelNameOf(e.hostelId) ?? e.name) : e.name,
      valueLabel: label,
      photoUrl: e.isHostel ? null : e.photoUrl,
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.vm});

  final LeaderboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final String message = switch (vm.scope) {
      LeaderboardScope.buddies =>
        'Add buddies to compare verified steps with them. Only accepted buddies appear here.',
      LeaderboardScope.myHostel => 'No one from your hostel has verified steps in this period yet.',
      LeaderboardScope.hostels => 'No hostel has verified steps in this period yet.',
      LeaderboardScope.campus => 'No one has verified steps in this period yet.',
    };
    return SizedBox(
      height: 260,
      child: EmptyState(
        title: 'No rankings yet',
        message: message,
        icon: Icons.leaderboard_outlined,
      ),
    );
  }
}

class _NotRankedHint extends StatelessWidget {
  const _NotRankedHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: AppCard(
        key: const Key('leaderboard-not-ranked'),
        color: AppColors.mint,
        shadow: false,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are not on this board yet. Verified steps in this period will place you here.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedMe extends StatelessWidget {
  const _PinnedMe({required this.vm});

  final LeaderboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final e = vm.myPinnedEntry;
    final r = vm.result;
    if (e == null || r == null) return const SizedBox.shrink();
    final leader = r.leaderValue;
    return Container(
      key: const Key('leaderboard-your-rank'),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.grey)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              e.isHostel ? 'Your hostel\'s rank' : 'Your rank',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          LeaderboardRow(
            entry: e,
            isMine: true,
            hostelName: vm.hostelNameOf(e.hostelId),
            progressBase: vm.progressBase ?? (leader > 0 ? leader : (e.value > 0 ? e.value : 1)),
            hostelMetric: r.query.hostelMetric,
          ),
        ],
      ),
    );
  }
}

class _Footnotes extends StatelessWidget {
  const _Footnotes();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Only verified steps are ranked.', style: style),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Students who hide themselves from leaderboards are not shown.',
                style: style,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
