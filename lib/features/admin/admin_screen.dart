import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_repository.dart';
import 'admin_support.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

/// `/admin` dashboard: key numbers from `adminStats` and a card for every
/// admin area. The route guard only hides this from non-admins; every call
/// is checked again by the backend.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>(
      create: (c) => DashboardViewModel(c.read<AdminRepository>())..load(),
      child: const _DashboardView(),
    );
  }
}

class _Area {
  const _Area(this.title, this.subtitle, this.icon, this.path, {this.statKey});

  final String title;
  final String subtitle;
  final IconData icon;
  final String path;
  final String? statKey;
}

const _areas = <_Area>[
  _Area('Students', 'Search, suspend, roles', Icons.groups_outlined, AppRoutes.adminStudents),
  _Area('Hostels', 'Add, edit, activate', Icons.apartment_outlined, AppRoutes.adminHostels),
  _Area('Challenges', 'Create and cancel', Icons.emoji_events_outlined, AppRoutes.adminChallenges,
      statKey: 'challenges'),
  _Area('Reports', 'Student reports', Icons.flag_outlined, AppRoutes.adminReports, statKey: 'reports'),
  _Area('Suspicious activity', 'Step risk events', Icons.shield_outlined, AppRoutes.adminRisk,
      statKey: 'risk'),
  _Area('Settings', 'Limits and points', Icons.tune_outlined, AppRoutes.adminSettings),
  _Area('Badges', 'Titles and points', Icons.military_tech_outlined, AdminPaths.badges),
];

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    return AdminPage(
      title: 'Admin',
      parent: AppRoutes.home,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: vm.loading ? null : vm.load,
        ),
      ],
      child: AdminAsyncBody(
        loading: vm.loading,
        error: vm.error,
        denied: vm.denied,
        hasData: vm.stats != null,
        onRetry: vm.load,
        child: RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (vm.hostelsEmpty) const _SeedBanner(),
              if (vm.stats != null) _StatsGrid(vm),
              const SectionHeader('Manage'),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 560 ? 3 : 2;
                  const gap = 12.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final a in _areas)
                        SizedBox(width: w, child: _AreaCard(area: a, vm: vm)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeedBanner extends StatelessWidget {
  const _SeedBanner();

  @override
  Widget build(BuildContext context) {
    final vm = context.read<DashboardViewModel>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        color: AppColors.mint,
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No hostels yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'The hostel list is empty, so students cannot finish registration. '
              'Load the default hostels, settings, badges and challenge templates.',
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Load default data',
              icon: Icons.download_outlined,
              expand: false,
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: 'Load default data?',
                  message: 'Creates the 18 default hostels, settings, badges and challenge '
                      'templates. Anything that already exists is left untouched.',
                  confirmLabel: 'Load defaults',
                );
                if (!ok || !context.mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                final r = await vm.seed();
                showAdminResultOn(messenger, r);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid(this.vm);

  final DashboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.stats!;
    final tiles = <Widget>[
      StatTile(
        label: 'Registered students',
        value: groupDigits(s.users),
        icon: Icons.groups_outlined,
      ),
      StatTile(
        label: 'Active accounts',
        value: groupDigits(s.activeUsers),
        caption: s.deletionRequests > 0 ? '${s.deletionRequests} deletion request(s)' : null,
        icon: Icons.check_circle_outline,
      ),
      StatTile(
        label: 'Challenges running',
        value: groupDigits(s.activeChallenges),
        icon: Icons.emoji_events_outlined,
      ),
      StatTile(
        label: 'Open reports',
        value: groupDigits(s.openReports),
        icon: Icons.flag_outlined,
        accent: s.openReports > 0 ? AppColors.warning : AppColors.primary,
      ),
      StatTile(
        label: 'Open risk events',
        value: groupDigits(s.openRiskEvents),
        icon: Icons.shield_outlined,
        accent: s.openRiskEvents > 0 ? AppColors.warning : AppColors.primary,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 3 : 2;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area, required this.vm});

  final _Area area;
  final DashboardViewModel vm;

  int? get _badge {
    final s = vm.stats;
    if (s == null) return null;
    return switch (area.statKey) {
      'reports' => s.openReports,
      'risk' => s.openRiskEvents,
      'challenges' => s.activeChallenges,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    return AppCard(
      onTap: () => context.push(area.path),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(area.icon, color: AppColors.primary),
              const Spacer(),
              if (badge != null && badge > 0) StatusPill('$badge', color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 12),
          Text(area.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            area.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
