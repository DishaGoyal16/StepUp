import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import 'daily_progress_card.dart';
import 'home_view_model.dart';

/// Two equal-width tiles with the same (content-driven) height.
Widget _tileRow(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );

/// Raw / Verified / Pending / Rejected (+ suspicious) for today.
class StepBreakdownCard extends StatelessWidget {
  const StepBreakdownCard({super.key, required this.breakdown, this.engineAvailable = true});

  final StepBreakdown breakdown;
  final bool engineAvailable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final b = breakdown;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step breakdown', style: t.titleMedium),
          const SizedBox(height: 12),
          // Content-sized rows (a fixed childAspectRatio grid overflowed the tiles on a real 360 dp phone:
          // by 1.3 px for the plain tiles and by 19 px for "Rejected" with its caption).
          _tileRow(
            StatTile(label: 'Raw', value: formatSteps(b.raw), icon: Icons.directions_walk),
            StatTile(label: 'Verified', value: formatSteps(b.verified), icon: Icons.verified_outlined),
          ),
          const SizedBox(height: 12),
          _tileRow(
            StatTile(
              label: 'Pending',
              value: formatSteps(b.pending),
              icon: Icons.hourglass_empty,
              accent: AppColors.warning,
            ),
            StatTile(
              label: 'Rejected',
              value: formatSteps(b.rejected),
              caption: '${formatSteps(b.suspicious)} suspicious',
              icon: Icons.block,
              accent: AppColors.error,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Only verified steps count for competitions',
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (!engineAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Live step tracking is not available on this device, so only server-confirmed totals are shown.',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
