import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Display-only project credits.
class TeamCredits extends StatelessWidget {
  const TeamCredits({super.key});

  static const List<String> team = ['Disha', 'Raghav', 'Anvi', 'Kashish'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          'Built for a healthier campus — Project Lead: Disha',
          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text('Team', style: t.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final n in team)
              Text(
                n,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
          ],
        ),
      ],
    );
  }
}
