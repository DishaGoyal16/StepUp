import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/leaderboard/leaderboard_models.dart';
import 'leaderboard_format.dart';

/// Reusable ranked list of leaderboard rows (students or hostels). It does not
/// scroll by itself: place it inside a `ListView` / `Column`. Other screens
/// (e.g. challenge leaderboards) can use it with their own
/// [LeaderboardEntry]s.
///
/// * [isMine] marks the signed-in user's row (highlighted, "You" tag).
/// * [hostelNameOf] resolves `hostelId` to a display name.
/// * [progressBase]: progress-bar denominator (e.g. the daily goal); by
///   default each bar is relative to the leader (the highest value shown).
/// * [hostelMetric] says which hostel figure is the ranking metric and is
///   therefore emphasised on hostel rows.
class LeaderboardList extends StatelessWidget {
  const LeaderboardList({
    super.key,
    required this.entries,
    this.isMine,
    this.hostelNameOf,
    this.progressBase,
    this.hostelMetric = HostelMetric.average,
    this.unit = 'steps',
  });

  final List<LeaderboardEntry> entries;
  final bool Function(LeaderboardEntry entry)? isMine;
  final String? Function(String? hostelId)? hostelNameOf;
  final num? progressBase;
  final HostelMetric hostelMetric;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final leader = entries.fold<num>(0, (m, e) => e.value > m ? e.value : m);
    final base = progressBase ?? leader;
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: LeaderboardRow(
              key: ValueKey('leaderboard-row-${e.id}-${e.rank}'),
              entry: e,
              isMine: isMine?.call(e) ?? false,
              hostelName: hostelNameOf?.call(e.hostelId),
              progressBase: base,
              hostelMetric: hostelMetric,
              unit: unit,
            ),
          ),
      ],
    );
  }
}

/// One row: rank, avatar, name, hostel, verified steps and a progress bar.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.progressBase,
    this.isMine = false,
    this.hostelName,
    this.hostelMetric = HostelMetric.average,
    this.unit = 'steps',
  });

  final LeaderboardEntry entry;
  final num progressBase;
  final bool isMine;

  /// Display name of the entry's hostel (student rows) shown under the name.
  final String? hostelName;
  final HostelMetric hostelMetric;
  final String unit;

  double get _progress {
    if (progressBase <= 0) return 0;
    final p = entry.value / progressBase;
    return p.isNaN ? 0 : p.clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = entry;
    final valueText = formatSteps(e.value);
    final caption = e.isHostel
        ? (hostelMetric == HostelMetric.average ? 'avg per participant' : 'total steps')
        : unit;
    return AppCard(
      color: isMine ? AppColors.mint : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankBadge(rank: e.rank),
              const SizedBox(width: 8),
              if (e.isHostel)
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.mint,
                  child: Icon(Icons.apartment_rounded, color: AppColors.primary),
                )
              else
                AvatarCircle(name: e.name, photoUrl: e.photoUrl, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wrap: on very narrow screens the "You" tag moves to the
                    // next line instead of overflowing.
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          e.name,
                          style: t.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isMine) _YouTag(color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                    if (!e.isHostel && hostelName != null)
                      Text(
                        hostelName!,
                        style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 52, maxWidth: 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        valueText,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      caption,
                      style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                      maxLines: 2,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (e.isHostel) ...[
            const SizedBox(height: 6),
            _HostelFigures(entry: e, metric: hostelMetric),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: AppColors.grey,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _YouTag extends StatelessWidget {
  const _YouTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'You',
        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// `14 participants`, `Total 12,345`, `Avg 1,234` with the ranking metric bold.
class _HostelFigures extends StatelessWidget {
  const _HostelFigures({required this.entry, required this.metric});

  final LeaderboardEntry entry;
  final HostelMetric metric;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = t.bodySmall?.copyWith(color: AppColors.textMuted);
    final strong = base?.copyWith(fontWeight: FontWeight.w800, color: AppColors.text);
    final avgIsMetric = metric == HostelMetric.average;
    final average = entry.average ?? (avgIsMetric ? entry.value : null);
    final total = entry.total ?? (!avgIsMetric ? entry.value : null);
    final spans = <InlineSpan>[];
    void add(String text, TextStyle? style) {
      if (spans.isNotEmpty) spans.add(TextSpan(text: ' · ', style: base));
      spans.add(TextSpan(text: text, style: style));
    }

    if (entry.participants != null) {
      final n = entry.participants!;
      add('$n participant${n == 1 ? '' : 's'}', base);
    }
    if (total != null) add('Total ${formatSteps(total)}', avgIsMetric ? base : strong);
    if (average != null) add('Avg ${formatSteps(average)}', avgIsMetric ? strong : base);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}
