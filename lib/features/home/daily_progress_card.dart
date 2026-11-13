import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'home_view_model.dart';

final NumberFormat _num = NumberFormat.decimalPattern('en_US');

/// Formats a step count with thousands separators (`12,345`).
String formatSteps(int n) => _num.format(n);

/// Progress ring (verified today / goal), percent, remaining steps, streak and
/// the 7-day bar chart.
class DailyProgressCard extends StatelessWidget {
  const DailyProgressCard({
    super.key,
    required this.verified,
    required this.goal,
    required this.streak,
    required this.bars,
    this.weeklyLoaded = true,
  });

  final int verified;
  final int goal;
  final int streak;
  final List<DayBar> bars;
  final bool weeklyLoaded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final safeGoal = goal <= 0 ? 1 : goal;
    final progress = verified / safeGoal;
    final percent = (progress * 100).floor();
    final remaining = (goal - verified).clamp(0, 1 << 31);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Today', style: t.titleMedium),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              label: '$verified of $goal verified steps today, $percent percent',
              child: ProgressRing(
                progress: progress,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatSteps(verified), style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text('of ${formatSteps(goal)}', style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text('$percent%', style: t.titleMedium?.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Remaining',
                  value: remaining == 0 ? 'Goal reached' : formatSteps(remaining),
                  icon: Icons.flag_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Streak',
                  value: streak == 1 ? '1 day' : '$streak days',
                  icon: Icons.local_fire_department_outlined,
                  accent: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('This week', style: t.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: WeeklyBarChart(bars: bars, goal: goal),
          ),
          if (weeklyLoaded && bars.every((b) => b.verified == 0))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No verified steps recorded this week yet.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom-painted 7-day bar chart of verified steps with a goal line.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({super.key, required this.bars, required this.goal});

  final List<DayBar> bars;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final summary = bars
        .map((b) => '${b.label}: ${b.verified} verified steps')
        .join(', ');
    return Semantics(
      label: 'Weekly verified steps. $summary',
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarsPainter(bars: bars, goal: goal),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.bars, required this.goal});

  final List<DayBar> bars;
  final int goal;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = bars.fold<int>(goal > 0 ? goal : 1, (m, b) => b.verified > m ? b.verified : m);
    final slot = size.width / bars.length;
    final barW = slot * 0.5;

    final goalY = chartH - chartH * (goal / maxV);
    final goalPaint = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, goalY), Offset(x + 4, goalY), goalPaint);
    }

    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final h = chartH * (b.verified / maxV);
      final left = slot * i + (slot - barW) / 2;
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, barW, chartH),
        const Radius.circular(8),
      );
      canvas.drawRRect(track, Paint()..color = AppColors.mint);
      if (h > 0) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, chartH - h, barW, h),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          rect,
          Paint()..color = b.isToday ? AppColors.primary : AppColors.secondary,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: b.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: b.isToday ? FontWeight.w700 : FontWeight.w500,
            color: b.isToday ? AppColors.text : AppColors.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left + (barW - tp.width) / 2, chartH + 3));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.bars != bars || old.goal != goal;
}
