import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/motion_sensor_service.dart';
import '../../core/services/health_data_service.dart';
import '../../data/models/activity_models.dart';
import '../../features/integrity/activity_integrity_detector.dart';
import '../../widgets/common_widgets.dart';

// ─────────────────────────────────────────────────────────
// ACTIVITY DETAIL SCREEN — shows full integrity report
// ─────────────────────────────────────────────────────────
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demoResults = DemoActivityData.todayRecords().map((r) {
      final isRunning =
          r.activityType == 'running' && (r.cadenceStepsPerMin ?? 0) >= 140;
      final isSuspicious =
          r.activityType == 'walking' && (r.cadenceStepsPerMin ?? 0) > 140;
      return IntegrityResult(
        activityRecordId: r.id,
        classification: isSuspicious
            ? ActivityClass.phoneShaking
            : isRunning
                ? ActivityClass.genuineRunning
                : ActivityClass.genuineWalking,
        confidence: isSuspicious ? 0.22 : 0.91,
        verifiedSteps: isSuspicious ? 0 : r.steps,
        suspiciousSteps: isSuspicious ? r.steps : 0,
        positiveReasons: isSuspicious
            ? []
            : ['Cadence in normal walking range', 'Speed consistent with human movement'],
        negativeReasons: isSuspicious
            ? ['Cadence too high for stationary walking', 'No GPS distance recorded']
            : [],
        detectorVersion: 'rule_based_v1',
        evaluatedAt: DateTime.now(),
        isBaseline: true,
        isDemoData: true,
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Integrity Report')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _DisclaimerBanner(),
          const SizedBox(height: 16),
          ...demoResults.map((result) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _IntegrityResultCard(result: result),
              )),
        ],
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔬', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prototype Integrity Engine',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This is a rule-based prototype (v1). Classifications use '
                  'cadence, speed, and sensor heuristics — not a trained ML model. '
                  'Results are indicative, not definitive.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntegrityResultCard extends StatelessWidget {
  final IntegrityResult result;
  const _IntegrityResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isGenuine = result.classification.isGenuine;
    final color = isGenuine ? AppColors.primary : AppColors.danger;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl)),
            ),
            child: Row(
              children: [
                Text(result.classification.emoji,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.classification.label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color,
                          )),
                      Text(
                        '${(result.confidence * 100).round()}% confidence',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isGenuine
                          ? '+${result.verifiedSteps} ✅'
                          : '${result.suspiciousSteps} ⚠️',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text('steps',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          // Reasons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.positiveReasons.isNotEmpty) ...[
                  const Text('✅ Evidence For:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  ...result.positiveReasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.check_rounded,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(r,
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      )),
                  const SizedBox(height: 10),
                ],
                if (result.negativeReasons.isNotEmpty) ...[
                  const Text('⚠️ Evidence Against:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger)),
                  const SizedBox(height: 6),
                  ...result.negativeReasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.close_rounded,
                              size: 12, color: AppColors.danger),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(r,
                                  style:
                                      Theme.of(context).textTheme.bodySmall)),
                        ]),
                      )),
                ],
                const SizedBox(height: 8),
                Text(
                  'Engine: ${result.detectorVersion}${result.isBaseline ? " (Prototype)" : ""}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }
}

// ─────────────────────────────────────────────────────────
// VERIFIED SESSION SCREEN — live sensor session
// ─────────────────────────────────────────────────────────
enum SessionState { idle, running, processing, done }

final sessionStateProvider =
    StateProvider<SessionState>((_) => SessionState.idle);
final sessionStepCountProvider = StateProvider<int>((_) => 0);
final sessionLiveAccelProvider = StateProvider<double>((_) => 9.8);
final sessionResultProvider =
    StateProvider<IntegrityResult?>((_) => null);
final sessionElapsedProvider = StateProvider<Duration>((_) => Duration.zero);

class VerifiedSessionScreen extends ConsumerStatefulWidget {
  const VerifiedSessionScreen({super.key});

  @override
  ConsumerState<VerifiedSessionScreen> createState() =>
      _VerifiedSessionScreenState();
}

class _VerifiedSessionScreenState
    extends ConsumerState<VerifiedSessionScreen> {
  late final MotionSensorService _sensorService;
  Timer? _timer;
  Timer? _accelTimer;
  int _elapsedSeconds = 0;
  int _mockSteps = 0;
  StreamSubscription? _accelSub;

  @override
  void initState() {
    super.initState();
    _sensorService = MotionSensorServiceFactory.create();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accelTimer?.cancel();
    _accelSub?.cancel();
    if (_sensorService.isSessionActive) {
      _sensorService.stopSession();
    }
    super.dispose();
  }

  void _startSession() {
    ref.read(sessionStateProvider.notifier).state = SessionState.running;
    _elapsedSeconds = 0;
    _mockSteps = 0;

    _sensorService.startSession();

    // Live accelerometer display
    _accelSub = _sensorService.liveAccelMagnitude.listen((mag) {
      if (mounted) {
        ref.read(sessionLiveAccelProvider.notifier).state = mag;
      }
    });

    // Timer for elapsed + mock step estimation
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      // Simulate ~1.7 steps/sec for walking demo
      _mockSteps += 2;
      if (mounted) {
        ref.read(sessionElapsedProvider.notifier).state =
            Duration(seconds: _elapsedSeconds);
        ref.read(sessionStepCountProvider.notifier).state = _mockSteps;
      }
    });
  }

  Future<void> _stopSession() async {
    _timer?.cancel();
    _accelSub?.cancel();
    ref.read(sessionStateProvider.notifier).state = SessionState.processing;

    final samples = _sensorService.stopSession();
    final deviceSteps = ref.read(sessionStepCountProvider);
    final elapsed = ref.read(sessionElapsedProvider);

    // Build a record from the session
    final now = DateTime.now();
    final record = ActivityRecord(
      id: 'session_${now.millisecondsSinceEpoch}',
      startTime: now.subtract(elapsed),
      endTime: now,
      steps: deviceSteps,
      distanceMeters: deviceSteps * 0.75,
      activityType: 'walking',
      platform: 'session',
    );

    final detector = RuleBasedIntegrityDetector();
    final result = await detector.evaluateSessionRecord(
      record: record,
      sensorSamples: samples,
      deviceStepCount: deviceSteps,
    );

    ref.read(sessionResultProvider.notifier).state = result;
    ref.read(sessionStateProvider.notifier).state = SessionState.done;
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionStateProvider);
    final steps = ref.watch(sessionStepCountProvider);
    final elapsed = ref.watch(sessionElapsedProvider);
    final accel = ref.watch(sessionLiveAccelProvider);
    final result = ref.watch(sessionResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verified Session'),
        leading: sessionState == SessionState.idle ||
                sessionState == SessionState.done
            ? null
            : const SizedBox.shrink(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DemoModeBanner(),
            const SizedBox(height: 24),
            _SessionDisplay(
              sessionState: sessionState,
              steps: steps,
              elapsed: elapsed,
              accel: accel,
              result: result,
            ),
            const Spacer(),
            if (sessionState == SessionState.idle)
              GradientButton(
                text: '▶  Start Verified Session',
                onPressed: _startSession,
                gradient: AppColors.primaryGradient,
              ),
            if (sessionState == SessionState.running)
              GradientButton(
                text: '⏹  Stop Session',
                onPressed: _stopSession,
                gradient: AppColors.battleGradient,
              ),
            if (sessionState == SessionState.processing)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('Analysing session data…',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            if (sessionState == SessionState.done)
              GradientButton(
                text: 'Done',
                onPressed: () => context.go('/activity'),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SessionDisplay extends StatelessWidget {
  final SessionState sessionState;
  final int steps;
  final Duration elapsed;
  final double accel;
  final IntegrityResult? result;

  const _SessionDisplay({
    required this.sessionState,
    required this.steps,
    required this.elapsed,
    required this.accel,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    if (sessionState == SessionState.done && result != null) {
      return _ResultDisplay(result: result!);
    }

    final isRunning = sessionState == SessionState.running;
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        Text(
          isRunning ? 'Session Active 🔴' : 'Ready to Start',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: isRunning ? AppColors.danger : AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 32),
        Text(
          '$mm:$ss',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ).animate(onPlay: (c) => c.repeat()).shimmer(
            duration: const Duration(seconds: 2),
            color: AppColors.primary.withOpacity(isRunning ? 0.5 : 0)),
        const SizedBox(height: 8),
        Text('$steps steps',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 24),
        if (isRunning) ...[
          Text(
            'Accel: ${accel.toStringAsFixed(2)} m/s²',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Sensor: ${MotionSensorServiceFactory.create().platformName}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ],
        if (!isRunning && sessionState == SessionState.idle) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              children: const [
                _InfoRow('📱', 'Keep phone in pocket or hand'),
                SizedBox(height: 8),
                _InfoRow('🔬', 'Sensor data processed on-device only'),
                SizedBox(height: 8),
                _InfoRow('🗑', 'Raw sensor data discarded after analysis'),
                SizedBox(height: 8),
                _InfoRow('⏱', 'Minimum 30 seconds for valid analysis'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String emoji;
  final String text;
  const _InfoRow(this.emoji, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _ResultDisplay extends StatelessWidget {
  final IntegrityResult result;
  const _ResultDisplay({required this.result});

  @override
  Widget build(BuildContext context) {
    final isGenuine = result.classification.isGenuine;
    final color = isGenuine ? AppColors.primary : AppColors.warning;

    return Column(
      children: [
        Text(result.classification.emoji,
                style: const TextStyle(fontSize: 64))
            .animate()
            .scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 16),
        Text(
          result.classification.label,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(result.confidence * 100).round()}% confidence',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ResultStat(
              label: 'Verified Steps',
              value: '${result.verifiedSteps}',
              color: AppColors.primary,
            ),
            _ResultStat(
              label: 'Suspicious',
              value: '${result.suspiciousSteps}',
              color: AppColors.danger,
            ),
            _ResultStat(
              label: 'XP Earned',
              value: '+${result.verifiedSteps ~/ 10}',
              color: AppColors.secondary,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (result.positiveReasons.isNotEmpty)
          ...result.positiveReasons.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(r, style: Theme.of(context).textTheme.bodySmall),
                ]),
              )),
      ],
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ResultStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ignore: unused_element
typedef StreamSubscription = dynamic;
