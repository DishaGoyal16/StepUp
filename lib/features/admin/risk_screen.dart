import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/admin/admin_models.dart';
import '../../data/admin/admin_repository.dart';
import 'admin_view_models.dart';
import 'admin_widgets.dart';
import 'reports_screen.dart' show shortUid;

/// Suspicious step activity (`riskEvents`). These never feed rewards; an
/// admin only reviews them.
class RiskScreen extends StatelessWidget {
  const RiskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RiskViewModel>(
      create: (c) => RiskViewModel(c.read<AdminRepository>())..load(),
      child: const _RiskView(),
    );
  }
}

class _RiskView extends StatelessWidget {
  const _RiskView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RiskViewModel>();
    return AdminPage(
      title: 'Suspicious activity',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: vm.loading ? null : () => vm.load(),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: FilterChipsRow<RiskStatus>(
              options: RiskStatus.values,
              selected: vm.filter,
              onSelected: (s) => vm.load(filter: s),
              labelOf: (s) => s.label,
            ),
          ),
          Expanded(
            child: AdminAsyncBody(
              loading: vm.loading,
              error: vm.error,
              denied: vm.denied,
              onRetry: () => vm.load(),
              child: vm.events.isEmpty
                  ? EmptyState(
                      icon: Icons.shield_outlined,
                      title: 'No ${vm.filter.label.toLowerCase()} events',
                    )
                  : RefreshIndicator(
                      onRefresh: () => vm.load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
                        itemCount: vm.events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _RiskTile(event: vm.events[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({required this.event});

  final RiskEvent event;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = event;
    return AppCard(
      onTap: () {
        final vm = context.read<RiskViewModel>();
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ChangeNotifierProvider<RiskViewModel>.value(
            value: vm,
            child: _RiskSheet(event: e, messenger: ScaffoldMessenger.of(context)),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.kindLabel, style: t.titleMedium)),
              StatusPill(e.status.label,
                  color: e.status == RiskStatus.open ? AppColors.warning : AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text('Student ${shortUid(e.uid)}  -  ${e.dayLabel ?? 'unknown day'}', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _RiskSheet extends StatelessWidget {
  const _RiskSheet({required this.event, required this.messenger});

  final RiskEvent event;
  final ScaffoldMessengerState messenger;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RiskViewModel>();
    final e = event;
    final t = Theme.of(context).textTheme;
    final rows = describeDetail(e.detail);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.kindLabel, style: t.titleLarge),
            const SizedBox(height: 8),
            _row(context, 'Kind', e.kind),
            _row(context, 'Student', e.uid),
            _row(context, 'Day', e.dayLabel == null ? '-' : '${e.dayLabel} (${e.dayKey})'),
            _row(context, 'Recorded', formatIst(e.createdAt)),
            _row(context, 'Status', e.status.label),
            const SizedBox(height: 12),
            Text('Evidence', style: t.titleMedium),
            const SizedBox(height: 4),
            if (rows.isEmpty)
              const Text('The server recorded no further detail.')
            else
              for (final r in rows) _row(context, r.$1, r.$2),
            const SizedBox(height: 4),
            Text(
              'These records are signals for a human to review, not proof of cheating. '
              'Flagged steps are already excluded from rewards by the server.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            if (e.status == RiskStatus.open) ...[
              PrimaryButton(
                label: 'Mark as reviewed',
                icon: Icons.visibility_outlined,
                loading: vm.busy,
                onPressed: () => _resolve(context, vm, RiskStatus.reviewed),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Clear (no concern)',
                icon: Icons.check_circle_outline,
                onPressed: vm.busy ? null : () => _resolve(context, vm, RiskStatus.cleared),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  Future<void> _resolve(BuildContext context, RiskViewModel vm, RiskStatus status) async {
    final cleared = status == RiskStatus.cleared;
    final ok = await confirmAction(
      context,
      title: cleared ? 'Clear this event?' : 'Mark as reviewed?',
      message: cleared
          ? 'You are recording that this activity is not a concern.'
          : 'You are recording that you looked at this activity.',
      confirmLabel: cleared ? 'Clear' : 'Mark reviewed',
    );
    if (!ok) return;
    final res = await vm.resolve(event, status);
    showAdminResultOn(messenger, res);
    if (res.ok && context.mounted) Navigator.pop(context);
  }
}

/// Turns the server's free-form `detail` map into `(label, value)` lines:
/// keys are humanised, nested maps are flattened (`Outer / inner`), lists are
/// joined and numbers are digit-grouped.
List<(String, String)> describeDetail(Map<String, dynamic> detail, [String prefix = '']) {
  final out = <(String, String)>[];
  for (final e in detail.entries) {
    final label = prefix.isEmpty ? humanizeKey(e.key) : '$prefix / ${humanizeKey(e.key)}';
    final v = e.value;
    if (v is Map) {
      out.addAll(describeDetail({for (final x in v.entries) x.key.toString(): x.value}, label));
    } else if (v is List) {
      out.add((label, v.isEmpty ? 'none' : v.map(_scalar).join(', ')));
    } else {
      out.add((label, _scalar(v)));
    }
  }
  return out;
}

String _scalar(Object? v) {
  if (v == null) return '-';
  if (v is int) return groupDigits(v);
  if (v is double) return v == v.roundToDouble() ? groupDigits(v.toInt()) : v.toStringAsFixed(2);
  if (v is bool) return v ? 'yes' : 'no';
  if (v is Map) return describeDetail({for (final x in v.entries) x.key.toString(): x.value}).map((r) => '${r.$1}: ${r.$2}').join('; ');
  return v.toString();
}
