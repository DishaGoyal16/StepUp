import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/daily_step_summary.dart';
import '../../domain/day_key.dart';
import '../auth/session_controller.dart';
import 'daily_progress_card.dart';

/// Step history (`/home/history`): the last 30 days of server-confirmed totals
/// from `dailyStepSummaries`, raw vs verified.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Stream<List<DailySummaryRow>>? _stream;
  int _attempt = 0;

  void _load() {
    final deps = context.read<AppDependencies>();
    final uid = context.read<SessionController>().user?.uid;
    if (uid == null) return;
    final days = DayKey.lastDays(deps.clock.now(), 30).reversed.toList(); // newest first
    _stream = deps.firestore.watchDailySummaries(uid, limit: 30).map((list) {
      final byKey = {for (final s in list) s.dayKey: s};
      return [
        for (final k in days) DailySummaryRow(k, byKey[k] ?? DailyStepSummary(dayKey: k)),
      ];
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Step history')),
      body: SafeArea(
        child: _stream == null
            ? const LoadingState()
            : AsyncStreamBuilder<List<DailySummaryRow>>(
                key: ValueKey(_attempt),
                stream: _stream!,
                errorMessage: 'Could not load your step history.',
                onRetry: () => setState(() {
                  _attempt++;
                  _load();
                }),
                isEmpty: (rows) => rows.every((r) => r.summary.rawSteps == 0 && r.summary.verifiedSteps == 0),
                empty: const EmptyState(
                  icon: Icons.directions_walk,
                  title: 'No synced steps yet',
                  message: 'Turn on step tracking on the Home tab. Days appear here after your steps are synced and verified.',
                ),
                builder: (context, rows) => _HistoryList(rows: rows),
              ),
      ),
    );
  }
}

/// A day and its server-confirmed summary.
class DailySummaryRow {
  const DailySummaryRow(this.dayKey, this.summary);

  final String dayKey;
  final DailyStepSummary summary;
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.rows});

  final List<DailySummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final maxRaw = rows.fold<int>(
      1,
      (m, r) => [m, r.summary.rawSteps, r.summary.verifiedSteps].reduce((a, b) => a > b ? a : b),
    );
    final totalVerified = rows.fold<int>(0, (s, r) => s + r.summary.verifiedSteps);
    final activeDays = rows.where((r) => r.summary.verifiedSteps > 0).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: StatTile(label: 'Verified (30 days)', value: formatSteps(totalVerified)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Average / active day',
                  value: formatSteps(activeDays == 0 ? 0 : totalVerified ~/ activeDays),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const _Legend(color: AppColors.grey, label: 'Raw'),
              const SizedBox(width: 16),
              const _Legend(color: AppColors.primary, label: 'Verified'),
              const Spacer(),
              Text('Only verified counts', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
        for (final r in rows) _DayRow(row: r, maxValue: maxRaw),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.row, required this.maxValue});

  final DailySummaryRow row;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = row.summary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        label: '${DayKey.label(row.dayKey)}: ${s.verifiedSteps} verified of ${s.rawSteps} raw steps',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(DayKey.label(row.dayKey), style: t.labelLarge)),
                Text('${formatSteps(s.verifiedSteps)} verified', style: t.labelLarge),
                Text(' / ${formatSteps(s.rawSteps)} raw', style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 4),
            _Bars(raw: s.rawSteps, verified: s.verifiedSteps, maxValue: maxValue),
          ],
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.raw, required this.verified, required this.maxValue});

  final int raw;
  final int verified;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        double w(int v) => c.maxWidth * (v / maxValue).clamp(0.0, 1.0);
        return SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(
                width: w(raw),
                decoration: BoxDecoration(color: AppColors.grey, borderRadius: BorderRadius.circular(5)),
              ),
              Container(
                width: w(verified),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(5)),
              ),
            ],
          ),
        );
      },
    );
  }
}
