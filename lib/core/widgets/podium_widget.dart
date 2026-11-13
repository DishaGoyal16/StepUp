import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'avatar_circle.dart';

/// One podium place.
class PodiumEntry {
  const PodiumEntry({required this.name, required this.valueLabel, this.photoUrl});

  final String name;

  /// Preformatted value, e.g. `12,345 steps`.
  final String valueLabel;
  final String? photoUrl;
}

/// Top-3 podium. [entries] must be ordered by rank (index 0 = 1st place);
/// fewer than three entries are fine. Layout: 2nd | 1st | 3rd.
class PodiumWidget extends StatelessWidget {
  const PodiumWidget({super.key, required this.entries});

  final List<PodiumEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    PodiumEntry? at(int i) => i < entries.length ? entries[i] : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _Place(entry: at(1), rank: 2, height: 84)),
        Expanded(child: _Place(entry: at(0), rank: 1, height: 116)),
        Expanded(child: _Place(entry: at(2), rank: 3, height: 64)),
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.entry, required this.rank, required this.height});

  final PodiumEntry? entry;
  final int rank;
  final double height;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final t = Theme.of(context).textTheme;
    if (e == null) return SizedBox(height: height);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarCircle(name: e.name, photoUrl: e.photoUrl, radius: rank == 1 ? 30 : 24),
          const SizedBox(height: 6),
          Text(e.name, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            e.valueLabel,
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            height: height,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: rank == 1 ? AppColors.secondary : AppColors.mint,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text('$rank', style: t.titleLarge),
          ),
        ],
      ),
    );
  }
}
