import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import 'admin_support.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';

class AdminChallengesScreen extends StatelessWidget {
  const AdminChallengesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChallengesViewModel>(
      create: (c) => ChallengesViewModel(c.read<AdminRepository>())..load(),
      child: const _ChallengesView(),
    );
  }
}

class _ChallengesView extends StatelessWidget {
  const _ChallengesView();

  static String _filterLabel(String? s) => switch (s) {
        null => 'All',
        'ACTIVE' => 'Active',
        'UPCOMING' => 'Upcoming',
        'COMPLETED' => 'Completed',
        'CANCELLED' => 'Cancelled',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChallengesViewModel>();
    return AdminPage(
      title: 'Challenges',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push(AdminPaths.newChallenge);
          if (context.mounted) vm.load();
        },
        icon: const Icon(Icons.add),
        label: const Text('New challenge'),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: FilterChipsRow<String?>(
              options: ChallengesViewModel.filters,
              selected: vm.statusFilter,
              onSelected: vm.setFilter,
              labelOf: _filterLabel,
            ),
          ),
          Expanded(
            child: AdminAsyncBody(
              loading: vm.loading,
              error: vm.error,
              denied: vm.denied,
              hasData: vm.all.isNotEmpty,
              onRetry: vm.load,
              child: vm.visible.isEmpty
                  ? const EmptyState(
                      icon: Icons.emoji_events_outlined,
                      title: 'No challenges here',
                      message: 'Create a campus, inter-hostel or individual challenge.',
                    )
                  : RefreshIndicator(
                      onRefresh: vm.load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 96),
                        itemCount: vm.visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _ChallengeTile(challenge: vm.visible[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeTile extends StatelessWidget {
  const _ChallengeTile({required this.challenge});

  final AdminChallenge challenge;

  static Color _color(String s) => switch (s) {
        'ACTIVE' => AppColors.primary,
        'UPCOMING' => AppColors.warning,
        'CANCELLED' => AppColors.error,
        _ => AppColors.textMuted,
      };

  String get _window {
    final c = challenge;
    if (c.windowMode == 'ROLLING') return '${c.durationDays ?? '?'} days from joining';
    final s = c.startAt, e = c.endAt;
    if (s == null || e == null) return 'Fixed window';
    // endAt is the IST midnight after the last day.
    return '${formatIst(s).split(' ').take(3).join(' ')} to '
        '${formatIst(e.subtract(const Duration(days: 1))).split(' ').take(3).join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChallengesViewModel>();
    final c = challenge;
    final t = Theme.of(context).textTheme;
    final target = c.metric == 'TOTAL_STEPS'
        ? '${groupDigits(c.target)} steps'
        : '${c.target} days at ${groupDigits(c.dailyTarget ?? 0)} steps/day';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.title, style: t.titleMedium)),
              StatusPill(c.status, color: _color(c.status)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.typeLabel}  -  ${c.metricLabel}  -  $target',
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          Text(_window, style: t.bodySmall),
          if (c.type == 'INTER_HOSTEL')
            Text(
              '${c.hostelIds.length} hostels, ${c.hostelAggregation == 'TOTAL' ? 'total' : 'average per participant'}',
              style: t.bodySmall,
            ),
          Text(
            '${c.participantCount} participant(s)'
            '${c.rewardPoints != null ? '  -  ${c.rewardPoints} pts reward' : ''}',
            style: t.bodySmall,
          ),
          if (c.canCancel) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: vm.busy.contains(c.id)
                    ? null
                    : () async {
                        final ok = await confirmAction(
                          context,
                          title: 'Cancel "${c.title}"?',
                          message: 'Students can no longer join or earn from this challenge. '
                              'This cannot be undone.',
                          confirmLabel: 'Cancel challenge',
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        final r = await vm.cancel(c);
                        showAdminResultOn(messenger, r);
                      },
                icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
                label: const Text('Cancel challenge', style: TextStyle(color: AppColors.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `/admin/challenges/new`.
class CreateChallengeScreen extends StatelessWidget {
  const CreateChallengeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CreateChallengeViewModel>(
      create: (c) => CreateChallengeViewModel(c.read<AdminRepository>())..loadHostels(),
      child: const _CreateView(),
    );
  }
}

class _CreateView extends StatefulWidget {
  const _CreateView();

  @override
  State<_CreateView> createState() => _CreateViewState();
}

class _CreateViewState extends State<_CreateView> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _target = TextEditingController();
  final _daily = TextEditingController();
  final _duration = TextEditingController();
  final _reward = TextEditingController();

  @override
  void dispose() {
    for (final c in [_title, _desc, _target, _daily, _duration, _reward]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _now(BuildContext c) => c.read<AppDependencies>().clock.now();

  static DateTime _dateOf(String dayKey) => DateTime(
        int.parse(dayKey.substring(0, 4)),
        int.parse(dayKey.substring(4, 6)),
        int.parse(dayKey.substring(6, 8)),
      );

  static String _keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String _label(String? dayKey) {
    if (dayKey == null) return 'Pick a date';
    final d = _dateOf(dayKey);
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _pick(BuildContext context, CreateChallengeViewModel vm, {required bool start}) async {
    final today = _dateOf(CreateChallengeViewModel.todayKey(_now(context)));
    final current = start ? vm.startDayKey : vm.lastDayKey;
    final first = start ? today : _dateOf(vm.startDayKey ?? _keyOf(today));
    var initial = current != null ? _dateOf(current) : first;
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(today.year + 2, today.month, today.day),
      helpText: start ? 'First day (IST)' : 'Last day, included (IST)',
    );
    if (picked == null) return;
    final key = _keyOf(picked);
    start ? vm.setStart(key) : vm.setLastDay(key);
  }

  Future<void> _submit(BuildContext context, CreateChallengeViewModel vm) async {
    final now = _now(context);
    vm.showErrors = true;
    final errs = vm.errors(now);
    if (errs.isNotEmpty) {
      vm.touch();
      showAdminResult(context, AdminResult.fail(errs.values.first));
      return;
    }
    final d = vm.draft;
    final lines = <String>[
      '${d.type.label} challenge "${d.title.trim()}"',
      d.metric == AdminChallengeMetric.totalSteps
          ? 'Goal: ${groupDigits(d.target!)} verified steps'
          : 'Goal: ${d.target} days (${d.metric == AdminChallengeMetric.streakDays ? 'streak of' : 'reaching'} '
              '${groupDigits(d.dailyTarget!)} steps a day)',
      d.isRolling
          ? 'Window: ${d.durationDays} days from when a student joins'
          : 'Window: ${_label(d.startDayKey)} to ${_label(d.lastDayKey)} (IST)',
      if (d.type == AdminChallengeType.interHostel)
        '${d.hostelIds.length} hostels, ${d.aggregation.label.toLowerCase()}',
      if (d.rewardPoints != null) 'Reward: ${d.rewardPoints} points',
    ];
    final ok = await confirmAction(
      context,
      title: 'Create this challenge?',
      message: lines.join('\n'),
      confirmLabel: 'Create',
    );
    if (!ok || !context.mounted) return;
    final r = await vm.submit(now);
    if (!context.mounted) return;
    showAdminResult(context, r);
    if (r.ok) {
      final router = GoRouter.maybeOf(context);
      if (router != null && router.canPop()) {
        router.pop();
      } else if (router != null) {
        router.go(AppRoutes.adminChallenges);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateChallengeViewModel>();
    final now = _now(context);
    final errs = vm.showErrors ? vm.errors(now) : const <String, String>{};
    final t = Theme.of(context).textTheme;
    final isInter = vm.type == AdminChallengeType.interHostel;
    final isIndividual = vm.type == AdminChallengeType.individual;
    return AdminPage(
      title: 'New challenge',
      parent: AppRoutes.adminChallenges,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Type', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AdminChallengeType>(
            segments: [
              for (final ty in AdminChallengeType.values)
                ButtonSegment(value: ty, label: Text(ty.label)),
            ],
            selected: {vm.type},
            onSelectionChanged: (s) => vm.setType(s.first),
          ),
          if (isIndividual)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Individual challenges are open to every student and can start when each student joins.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 80,
            onChanged: (v) {
              vm.title = v;
              vm.touch();
            },
            decoration: InputDecoration(labelText: 'Title', errorText: errs['title']),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _desc,
            maxLength: 400,
            maxLines: 3,
            onChanged: (v) {
              vm.description = v;
              vm.touch();
            },
            decoration: InputDecoration(labelText: 'Description (optional)', errorText: errs['description']),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AdminChallengeMetric>(
            initialValue: vm.metric,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Metric'),
            items: [
              for (final m in AdminChallengeMetric.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) {
              if (m != null) vm.setMetric(m);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            onChanged: (v) {
              vm.targetText = v;
              vm.touch();
            },
            decoration: InputDecoration(
              labelText: vm.metric == AdminChallengeMetric.totalSteps ? 'Target (total steps)' : 'Target (days)',
              errorText: errs['target'],
            ),
          ),
          if (vm.metric != AdminChallengeMetric.totalSteps) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _daily,
              keyboardType: TextInputType.number,
              onChanged: (v) {
                vm.dailyTargetText = v;
                vm.touch();
              },
              decoration: InputDecoration(labelText: 'Daily target (steps per day)', errorText: errs['dailyTarget']),
            ),
          ],
          const SizedBox(height: 20),
          Text('Window', style: t.titleMedium),
          if (isIndividual)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts when a student joins'),
              subtitle: const Text('Rolling window instead of fixed dates'),
              value: vm.rolling,
              onChanged: vm.setRolling,
            ),
          if (vm.draft.isRolling)
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              onChanged: (v) {
                vm.durationText = v;
                vm.touch();
              },
              decoration: InputDecoration(labelText: 'Duration (days, 1-90)', errorText: errs['duration']),
            )
          else ...[
            const SizedBox(height: 8),
            _DateField(
              label: 'First day',
              value: _label(vm.startDayKey),
              error: errs['start'],
              onTap: () => _pick(context, vm, start: true),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Last day (included)',
              value: _label(vm.lastDayKey),
              error: errs['end'],
              onTap: () => _pick(context, vm, start: false),
            ),
            const SizedBox(height: 4),
            Text(
              'Days start and end at midnight IST.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (isInter) ...[
            const SizedBox(height: 20),
            Text('Competing hostels', style: t.titleMedium),
            const SizedBox(height: 8),
            _HostelPicker(error: errs['hostels']),
            const SizedBox(height: 16),
            Text('Hostel score', style: t.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<HostelAggregation>(
              segments: [
                for (final a in HostelAggregation.values) ButtonSegment(value: a, label: Text(a.label)),
              ],
              selected: {vm.aggregation},
              onSelectionChanged: (s) => vm.setAggregation(s.first),
            ),
            const SizedBox(height: 4),
            Text(
              vm.aggregation == HostelAggregation.averagePerParticipant
                  ? 'Fair for hostels of different sizes (recommended).'
                  : 'Larger hostels have an advantage.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _reward,
            keyboardType: TextInputType.number,
            onChanged: (v) {
              vm.rewardText = v;
              vm.touch();
            },
            decoration: InputDecoration(
              labelText: 'Reward points (optional)',
              helperText: 'Virtual points for the winner / completers',
              errorText: errs['rewardPoints'],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Create challenge',
            icon: Icons.check,
            loading: vm.submitting,
            onPressed: () => _submit(context, vm),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.error});

  final String label;
  final String value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.button),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
    );
  }
}

class _HostelPicker extends StatelessWidget {
  const _HostelPicker({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreateChallengeViewModel>();
    if (vm.loadingHostels) return const Padding(padding: EdgeInsets.all(16), child: LoadingState());
    if (vm.hostelsError != null) {
      return ErrorState(message: vm.hostelsError!, onRetry: vm.loadHostels, compact: true);
    }
    final active = vm.activeHostels;
    if (active.isEmpty) {
      return const Text('There are no active hostels. Add or load hostels first.');
    }
    final t = Theme.of(context).textTheme;
    Widget group(String title, Iterable<MapEntry<String, String>> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(title, style: t.labelLarge),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in items)
                  FilterChip(
                    label: Text(e.value),
                    selected: vm.selected.contains(e.key),
                    onSelected: (_) => vm.toggleHostel(e.key),
                  ),
              ],
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChipsRow<HostelPreset>(
          options: HostelPreset.values,
          selected: vm.preset,
          onSelected: vm.setPreset,
          labelOf: (p) => p.label,
        ),
        const SizedBox(height: 4),
        group('General hostels',
            [for (final h in active.where((h) => !h.isGirls)) MapEntry(h.id, h.displayName)]),
        group("Girls' hostels", [for (final h in active.where((h) => h.isGirls)) MapEntry(h.id, h.displayName)]),
        const SizedBox(height: 6),
        Text('${vm.selected.length} selected', style: t.bodySmall),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!, style: t.bodySmall?.copyWith(color: AppColors.error)),
          ),
      ],
    );
  }
}
