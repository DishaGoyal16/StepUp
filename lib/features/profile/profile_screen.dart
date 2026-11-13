import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/profile_extras/extras_models.dart';
import '../../domain/user_profile.dart';
import '../auth/session_controller.dart';
import 'profile_format.dart';
import 'profile_providers.dart';
import 'profile_routes.dart';
import 'profile_sections.dart';
import 'profile_view_model.dart';

/// Profile tab (`/profile`): identity, verified-step summary, campus rank,
/// virtual points, achievements, completed challenges and buddies.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileViewModel? _vm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = Provider.of<SessionController>(context).profile;
    if (profile == null) return;
    if (_vm == null || _vm!.uid != profile.uid || _vm!.hostelId != profile.hostelId) {
      _vm?.dispose();
      final deps = context.read<AppDependencies>();
      _vm = ProfileViewModel(
        uid: profile.uid,
        hostelId: profile.hostelId,
        sources: context.read<ProfileDataSources>(),
        firestore: deps.firestore,
        hostels: deps.hostels,
        clock: deps.clock,
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
    final profile = context.watch<SessionController>().profile;
    if (vm == null || profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const LoadingState(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => context.push(AppRoutes.notifications),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(ProfileRoutes.settings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => RefreshIndicator(
            onRefresh: vm.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ProfileHeaderCard(profile: profile, hostelName: vm.hostelName),
                        const SizedBox(height: 16),
                        StepsSummaryCard(profile: profile, vm: vm),
                        const SizedBox(height: 16),
                        RankCard(state: vm.rank, onRetry: vm.refresh),
                        const SizedBox(height: 16),
                        PointsCard(profile: profile, ledger: vm.ledger),
                        const SizedBox(height: 8),
                        AchievementsSection(state: vm.badges, onRetry: vm.refresh),
                        const SizedBox(height: 8),
                        CompletedChallengesSection(state: vm.completed, onRetry: vm.refresh),
                        const SizedBox(height: 8),
                        BuddiesSection(state: vm.buddies, onRetry: vm.refresh),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({super.key, required this.profile, required this.hostelName});

  final UserProfile profile;
  final String? hostelName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hostel = hostelName ?? (profile.hostelId.isEmpty ? null : profile.hostelId);
    return AppCard(
      child: Column(
        children: [
          AvatarCircle(name: profile.displayName, photoUrl: profile.photoUrl, radius: 44),
          const SizedBox(height: 12),
          Text(profile.displayName, style: t.titleLarge, textAlign: TextAlign.center),
          if (hostel != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apartment, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    hostel,
                    style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (profile.fitnessLevel != null || profile.sportsInterests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (profile.fitnessLevel != null)
                  Chip(
                    avatar: const Icon(Icons.speed, size: 18, color: AppColors.primary),
                    label: Text(profile.fitnessLevel!.label),
                    backgroundColor: AppColors.mint,
                  ),
                for (final s in profile.sportsInterests) Chip(label: Text(s)),
              ],
            ),
          ],
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(profile.bio, style: t.bodyMedium, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Edit profile',
            icon: Icons.edit_outlined,
            onPressed: () => context.push(ProfileRoutes.edit),
          ),
        ],
      ),
    );
  }
}

class StepsSummaryCard extends StatelessWidget {
  const StepsSummaryCard({super.key, required this.profile, required this.vm});

  final UserProfile profile;
  final ProfileViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = vm.steps.data;
    String windowValue(int? v) => vm.steps.failed ? '-' : (v == null ? '...' : formatCount(v));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verified steps', style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            'Only steps confirmed by the server count.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.directions_walk,
                  label: 'Lifetime',
                  value: formatCount(profile.lifetimeVerifiedSteps),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(label: 'Last 7 days', value: windowValue(s?.last7Days)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(label: 'Last 30 days', value: windowValue(s?.last30Days)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.local_fire_department,
                  label: 'Current streak',
                  value: '${profile.currentStreak} d',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(label: 'Best streak', value: '${profile.bestStreak} d'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(label: 'Daily goal', value: formatCount(profile.dailyGoal)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'View step history',
            icon: Icons.bar_chart,
            onPressed: () => context.push(AppRoutes.stepHistory),
          ),
        ],
      ),
    );
  }
}

class RankCard extends StatelessWidget {
  const RankCard({super.key, required this.state, required this.onRetry});

  final SectionState<CampusRank?> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final Widget content;
    if (state.loading) {
      content = const SectionLoading();
    } else if (state.failed) {
      content = SectionError(message: 'Rank unavailable right now.', onRetry: onRetry);
    } else if (state.data == null) {
      content = Text(
        'Not ranked yet. Verified steps this week put you on the board.',
        style: t.bodyMedium,
      );
    } else {
      final r = state.data!;
      content = Row(
        children: [
          RankBadge(rank: r.rank, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${r.rank} on campus', style: t.titleMedium),
                Text(
                  '${formatCount(r.value)} verified steps this week',
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AppCard(
      onTap: () => context.go(AppRoutes.leaderboard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Campus rank (this week)', style: t.titleMedium)),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}

class PointsCard extends StatelessWidget {
  const PointsCard({super.key, required this.profile, required this.ledger});

  final UserProfile profile;
  final SectionState<List<LedgerEntry>> ledger;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final entries = ledger.data ?? const <LedgerEntry>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Virtual points', style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            'Points are virtual and only used for step bets. They have no cash value.',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.stars_outlined,
                  label: 'Available',
                  value: formatCount(profile.pointsBalance),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  icon: Icons.lock_clock_outlined,
                  label: 'Reserved in bets',
                  value: formatCount(profile.pointsReserved),
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.note.isEmpty ? e.label : '${e.label} - ${e.note}',
                        style: t.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatSigned(e.delta),
                      style: t.labelLarge?.copyWith(
                        color: e.delta < 0 ? AppColors.error : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Points history',
            icon: Icons.receipt_long_outlined,
            onPressed: () => context.push(ProfileRoutes.pointsLedger),
          ),
        ],
      ),
    );
  }
}
