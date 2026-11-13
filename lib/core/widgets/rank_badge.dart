import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Circular rank marker. Ranks 1-3 get gold / silver / bronze tints, others a
/// neutral grey. Rank is always shown as a number (not colour alone).
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank, this.size = 32});

  final int rank;
  final double size;

  Color get _bg => switch (rank) {
        1 => const Color(0xFFFFE9A8),
        2 => const Color(0xFFE3E8EA),
        3 => const Color(0xFFF2D2B6),
        _ => AppColors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rank $rank',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
        child: Text(
          '$rank',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: size * 0.42,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}
