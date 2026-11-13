import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/user_profile.dart';
import '../auth/session_controller.dart';
import 'campus_activity_widget.dart';
import 'daily_progress_card.dart';
import 'home_view_model.dart';
import 'step_breakdown_card.dart';
import 'step_tracking_card.dart';
import 'team_credits.dart';

/// Home dashboard (tab 1).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeViewModel? _vm;
  String? _vmUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = Provider.of<SessionController>(context);
    final profile = session.profile;
    if (profile == null) return;
    if (_vm == null || _vmUid != profile.uid) {
      _vm?.dispose();
      final deps = context.read<AppDependencies>();
      _vmUid = profile.uid;
      _vm = HomeViewModel(
        uid: profile.uid,
        hostelId: profile.hostelId,
        firestore: deps.firestore,
        notifications: deps.notificationsCount,
        campus: deps.campusActivity,
        hostels: deps.hostels,
        tracking: deps.stepTracking,
        sync: deps.stepSync,
        clock: deps.clock,
      )..start();
      deps.stepTracking.attach();
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
      return const Scaffold(body: LoadingState());
    }
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, vm.tracking, vm.sync]),
          builder: (context, _) => RefreshIndicator(
            onRefresh: vm.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _GreetingRow(profile: profile, hostelName: vm.hostelName, unread: vm.unread),
                const SizedBox(height: 12),
                const _HeroBanner(),
                const SizedBox(height: 16),
                DailyProgressCard(
                  verified: vm.todayVerified,
                  goal: profile.dailyGoal,
                  streak: profile.currentStreak,
                  bars: vm.weeklyBars(),
                  weeklyLoaded: vm.summariesLoaded,
                ),
                if (vm.summariesFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Could not load your history. Pull down to retry.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.stepHistory),
                    child: const Text('View step history'),
                  ),
                ),
                StepBreakdownCard(
                  breakdown: vm.breakdown,
                  engineAvailable: vm.tracking.engineAvailable,
                ),
                const SizedBox(height: 16),
                StepTrackingCard(tracking: vm.tracking, sync: vm.sync),
                const SectionHeader('Quick actions'),
                const _QuickActions(),
                const SizedBox(height: 8),
                HomeCampusActivity(activity: vm.campusActivity, loading: !vm.campusLoaded),
                const SizedBox(height: 24),
                const TeamCredits(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({required this.profile, required this.hostelName, required this.unread});

  final UserProfile profile;
  final String? hostelName;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        AvatarCircle(name: profile.displayName, photoUrl: profile.photoUrl, radius: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi, ${profile.firstName}', style: t.titleLarge),
              if (hostelName != null)
                Text(hostelName!, style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
        IconButton(
          tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_outlined, size: 28),
          ),
        ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      color: AppColors.mint,
      shadow: false,
      child: Row(
        children: [
          const Icon(Icons.directions_walk_rounded, size: 40, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome to StepUp', style: t.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Your campus. Your fitness. Your community.',
                  style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.group_add_outlined, 'Find a Buddy', () => context.go(AppRoutes.buddies)),
      (Icons.emoji_events_outlined, 'Join Challenge', () => context.go(AppRoutes.challenges)),
      (Icons.leaderboard_outlined, 'View Leaderboard', () => context.go(AppRoutes.leaderboard)),
      (Icons.casino_outlined, 'Create Step Bet', () => context.push(AppRoutes.betsCreate)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        for (final (icon, label, onTap) in items)
          AppCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
