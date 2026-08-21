import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/health_data_service.dart';
import '../../core/services/settings_service.dart';
import '../../data/models/activity_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../features/integrity/activity_integrity_detector.dart';
import '../../widgets/common_widgets.dart';
import 'activity_detail_screen.dart';

// ─────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────
final activitySummaryProvider =
    StateProvider<DailyActivitySummary?>((ref) => null);

final rawRecordsProvider =
    StateProvider<List<ActivityRecord>>((ref) => []);

final integrityResultsProvider =
    StateProvider<List<IntegrityResult>>((ref) => []);

final isSyncingProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────
// ACTIVITY SCREEN
// ─────────────────────────────────────────────────────────
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemoMode = ref.watch(demoModeProvider);
    final summary = ref.watch(activitySummaryProvider);
    final records = ref.watch(rawRecordsProvider);
    final results = ref.watch(integrityResultsProvider);
    final isSyncing = ref.watch(isSyncingProvider);

    // Load demo data on first render if nothing loaded
    final displaySummary = summary ??
        ref.read(localActivityRepositoryProvider).demoTodaySummary();
    final displayRecords =
        records.isNotEmpty ? records : DemoActivityData.todayRecords();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            floating: true,
            title: const Text('Activity'),
            actions: [
              IconButton(
                icon: const Icon(Icons.play_circle_outline_rounded,
                    color: AppColors.primary),
                tooltip: 'Start Verified Session',
                onPressed: () => context.go('/activity/session'),
              ),
              IconButton(
                icon: isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.sync_rounded,
                        color: AppColors.textSecondary),
                tooltip: 'Sync from Health App',
                onPressed:
                    isSyncing ? null : () => _syncActivity(context, ref),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDemoMode || displaySummary.isDemoData)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: DemoModeBanner(),
                    ),
                  _TodaySummaryCard(summary: displaySummary),
                  const SizedBox(height: 20),
                  _VerifiedSessionBanner(),
                  const SizedBox(height: 20),
                  _IntegrityBreakdownCard(
                    summary: displaySummary,
                    results: results.isNotEmpty
                        ? results
                        : _buildDemoResults(displayRecords),
                  ),
                  const SizedBox(height: 20),
                  _RecordsList(
                    records: displayRecords,
                    results: results.isNotEmpty
                        ? results
                        : _buildDemoResults(displayRecords),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncActivity(
      BuildContext context, WidgetRef ref) async {
    ref.read(isSyncingProvider.notifier).state = true;
    try {
      final service = HealthDataServiceFactory.create();
      final hasPerms = await service.hasPermissions;
      if (!hasPerms) {
        final granted = await service.requestPermissions();
        if (!granted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Health permissions required to sync step data.'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
          return;
        }
      }

      final records = await service.fetchTodayRecords();
      final detector = RuleBasedIntegrityDetector();
      final results = <IntegrityResult>[];

      for (final record in records) {
        final result = await detector.evaluateImportedRecord(record);
        results.add(result);
      }

      final totalImported = records.fold<int>(0, (s, r) => s + r.steps);
      final totalVerified =
          results.fold<int>(0, (s, r) => s + r.verifiedSteps);
      final totalSuspicious =
          results.fold<int>(0, (s, r) => s + r.suspiciousSteps);
      final integrityScore =
          totalImported > 0 ? totalVerified / totalImported : 0.0;

      final summary = DailyActivitySummary(
        date: DateTime.now(),
        importedSteps: totalImported,
        verifiedSteps: totalVerified,
        suspiciousSteps: totalSuspicious,
        distanceMeters:
            records.fold<double>(0, (s, r) => s + r.distanceMeters),
        walkingMinutes: records
            .where((r) => r.activityType == 'walking')
            .fold<int>(0, (s, r) => s + r.durationMinutes.round()),
        runningMinutes: records
            .where((r) => r.activityType == 'running')
            .fold<int>(0, (s, r) => s + r.durationMinutes.round()),
        integrityScore: integrityScore.toDouble(),
        xpEarned: totalVerified ~/ 10,
        coinsEarned: totalVerified ~/ 100,
        recordIds: records.map((r) => r.id).toList(),
      );

      ref.read(activitySummaryProvider.notifier).state = summary;
      ref.read(rawRecordsProvider.notifier).state = records;
      ref.read(integrityResultsProvider.notifier).state = results;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Synced ${records.length} records — $totalVerified verified steps'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } finally {
      ref.read(isSyncingProvider.notifier).state = false;
    }
  }

  List<IntegrityResult> _buildDemoResults(List<ActivityRecord> records) {
    final detector = RuleBasedIntegrityDetector();
    final results = <IntegrityResult>[];
    for (final r in records) {
      // Synchronous mock evaluation (simplified)
      final isWalking = r.activityType == 'walking' &&
          (r.cadenceStepsPerMin ?? 0) >= 60 &&
          (r.cadenceStepsPerMin ?? 0) <= 140;
      final isRunning = r.activityType == 'running' &&
          (r.cadenceStepsPerMin ?? 0) >= 140;
      final isSuspicious = !isWalking && !isRunning;
      results.add(IntegrityResult(
        activityRecordId: r.id,
        classification: isSuspicious
            ? ActivityClass.phoneShaking
            : isRunning
                ? ActivityClass.genuineRunning
                : ActivityClass.genuineWalking,
        confidence: isSuspicious ? 0.22 : 0.91,
        verifiedSteps: isSuspicious ? 0 : r.steps,
        suspiciousSteps: isSuspicious ? r.steps : 0,
        positiveReasons:
            isSuspicious ? [] : ['Plausible cadence', 'Normal speed'],
        negativeReasons: isSuspicious
            ? ['Cadence outside normal range', 'No distance recorded']
            : [],
        detectorVersion: 'rule_based_v1',
        evaluatedAt: DateTime.now(),
        isBaseline: true,
        isDemoData: r.isDemoData,
      ));
    }
    return results;
  }
}

// ─────────────────────────────────────────────────────────
// TODAY SUMMARY CARD
// ─────────────────────────────────────────────────────────
class _TodaySummaryCard extends StatelessWidget {
  final DailyActivitySummary summary;
  const _TodaySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Text(DateFormat('EEEE, d MMM').format(summary.date),
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IntegrityBadge(
                label: summary.integrityLabel,
                score: summary.integrityScore,
              ),
            ],
          ),
          const SizedBox(height: 20),
          StepProgressRing(
            progress: summary.importedSteps > 0
                ? summary.verifiedSteps / summary.importedSteps
                : 0,
            currentSteps: summary.verifiedSteps,
            goalSteps: summary.importedSteps,
            size: 180,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              StatCard(
                label: 'Verified',
                value: _fmt(summary.verifiedSteps),
                emoji: '✅',
                valueColor: AppColors.primary,
              ),
              StatCard(
                label: 'Suspicious',
                value: _fmt(summary.suspiciousSteps),
                emoji: '⚠️',
                valueColor: AppColors.danger,
              ),
              StatCard(
                label: 'XP Earned',
                value: '+${summary.xpEarned}',
                emoji: '⚡',
                valueColor: AppColors.secondary,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  static String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toString();
}

// ─────────────────────────────────────────────────────────
// VERIFIED SESSION BANNER
// ─────────────────────────────────────────────────────────
class _VerifiedSessionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/activity/session'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.glow(AppColors.primary),
        ),
        child: Row(
          children: [
            const Text('🎯', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Start Verified Session',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Uses phone sensors + step counter for higher integrity score',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }
}

// ─────────────────────────────────────────────────────────
// INTEGRITY BREAKDOWN CARD
// ─────────────────────────────────────────────────────────
class _IntegrityBreakdownCard extends StatelessWidget {
  final DailyActivitySummary summary;
  final List<IntegrityResult> results;

  const _IntegrityBreakdownCard({
    required this.summary,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    final classGroups = <ActivityClass, int>{};
    for (final r in results) {
      classGroups[r.classification] =
          (classGroups[r.classification] ?? 0) + r.verifiedSteps + r.suspiciousSteps;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '🔬 Integrity Breakdown',
          actionLabel: 'Full Report',
          onAction: () => context.go('/activity/detail'),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prototype Integrity Engine (Rule-Based v1)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 12),
              ...classGroups.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(e.key.emoji,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key.label,
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 2),
                              LinearProgressIndicator(
                                value: summary.importedSteps > 0
                                    ? e.value / summary.importedSteps
                                    : 0,
                                backgroundColor: AppColors.darkBorder,
                                valueColor: AlwaysStoppedAnimation(
                                  e.key.isGenuine
                                      ? AppColors.primary
                                      : AppColors.danger,
                                ),
                                borderRadius: BorderRadius.circular(3),
                                minHeight: 5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${e.value}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: e.key.isGenuine
                                  ? AppColors.primary
                                  : AppColors.danger,
                            )),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }
}

// ─────────────────────────────────────────────────────────
// RECORDS LIST
// ─────────────────────────────────────────────────────────
class _RecordsList extends StatelessWidget {
  final List<ActivityRecord> records;
  final List<IntegrityResult> results;

  const _RecordsList({required this.records, required this.results});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final resultMap = {for (final r in results) r.activityRecordId: r};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '📋 Today\'s Records'),
        const SizedBox(height: 10),
        ...records.asMap().entries.map((e) {
          final record = e.value;
          final result = resultMap[record.id];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecordTile(record: record, result: result),
          );
        }),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }
}

class _RecordTile extends StatelessWidget {
  final ActivityRecord record;
  final IntegrityResult? result;

  const _RecordTile({required this.record, this.result});

  @override
  Widget build(BuildContext context) {
    final cls = result?.classification;
    final isGenuine = cls?.isGenuine ?? false;
    final color = isGenuine ? AppColors.primary : AppColors.danger;
    final start = DateFormat('h:mm a').format(record.startTime);
    final end = DateFormat('h:mm a').format(record.endTime);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(cls?.emoji ?? '❓',
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cls?.label ?? 'Unknown',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text('$start – $end  ·  ${record.steps} steps',
                    style: Theme.of(context).textTheme.bodySmall),
                if (record.sourceApp != null)
                  Text('Source: ${record.sourceApp}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textHint,
                            fontSize: 10,
                          )),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isGenuine
                    ? '+${result!.verifiedSteps}'
                    : '${result?.suspiciousSteps ?? 0}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '${(((result?.confidence ?? 0) * 100)).round()}% conf.',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
