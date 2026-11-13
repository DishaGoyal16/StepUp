import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Credits shown at the bottom of Home. TEXT ONLY - these names are not
/// accounts, roles or permissions. Kashish is intentionally shown smaller and
/// lighter than the rest of the team.
class TeamCredits extends StatelessWidget {
  const TeamCredits({super.key});

  static const List<String> team = ['Disha', 'Raghav', 'Bhavya', 'Sanveer', 'Anvi'];
  static const String lowProminenceMember = 'Kashish';

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
            Text(
              lowProminenceMember,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6F8277),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
