import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/steps/step_permissions.dart';
import '../../data/steps/step_sync_service.dart';
import '../../data/steps/step_tracking_controller.dart';
import '../../domain/step_reasons.dart';

/// Tracking switch, permission state, last sync and the "why are some steps
/// not counted" explanation.
class StepTrackingCard extends StatelessWidget {
  const StepTrackingCard({super.key, required this.tracking, required this.sync});

  final StepTrackingController tracking;
  final StepSyncService sync;

  String _permissionText() {
    final p = tracking.permissionStatus;
    if (p == null) return 'Permissions not checked yet';
    if (!p.canTrack) {
      return p.activityPermanentlyDenied
          ? 'Activity permission blocked - open settings to allow it'
          : 'Activity permission needed';
    }
    if (p.notifications != StepPermissionState.granted) {
      return 'Activity allowed - notifications off (tracking still works)';
    }
    return 'Activity and notification permissions allowed';
  }

  String _syncText() {
    final at = sync.lastSyncAt;
    if (sync.syncing) return 'Syncing...';
    if (at == null) return 'Not synced yet';
    return 'Last synced ${DateFormat.jm().format(at.toLocal())}';
  }

  Future<bool> _rationale(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow step tracking?'),
        content: const Text(
          'StepUp counts your steps with your phone\'s step counter and checks them against '
          'its movement sensors so only genuine walking counts. Android will ask for '
          '"Physical activity" access, and for notifications so a small "tracking" '
          'notice can stay visible while it runs. Nothing about your location is collected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _toggle(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await tracking.setTracking(on, rationale: () => _rationale(context));
    if (!context.mounted) return;
    switch (result) {
      case TrackingChange.started || TrackingChange.stopped:
        break;
      case TrackingChange.permissionPermanentlyDenied:
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission needed'),
            content: const Text(
              'Step tracking needs the "Physical activity" permission. It is blocked, '
              'so please allow it in the app settings.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
                onPressed: () {
                  Navigator.pop(ctx);
                  tracking.openSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
      case TrackingChange.permissionDenied:
        messenger.showSnackBar(
          const SnackBar(content: Text('Step tracking needs the Physical activity permission.')),
        );
      case TrackingChange.unsupported:
        messenger.showSnackBar(
          const SnackBar(content: Text('This phone has no step counter, so tracking is not available.')),
        );
      case TrackingChange.startFailed:
        messenger.showSnackBar(
          const SnackBar(content: Text('Step tracking could not start. Please try again in a moment.')),
        );
      case TrackingChange.failed:
        messenger.showSnackBar(
          SnackBar(content: Text(tracking.engineError?.message ?? 'Could not change step tracking.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unavailable = !tracking.engineAvailable;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Step tracking', style: t.titleMedium)),
              Switch(
                key: const ValueKey('tracking-switch'),
                value: tracking.tracking,
                onChanged: (unavailable || tracking.busy) ? null : (v) => _toggle(context, v),
              ),
            ],
          ),
          Text(
            unavailable
                ? (tracking.engineError?.message ?? 'Step tracking is not available on this device.')
                : (tracking.tracking ? 'On - counting your steps' : 'Off - turn on to count steps'),
            style: t.bodyMedium,
          ),
          if (tracking.liveLabel.isNotEmpty && tracking.tracking)
            Text(tracking.liveLabel, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.shield_outlined, text: _permissionText()),
          _InfoRow(icon: Icons.sync, text: _syncText()),
          if (sync.lastError != null)
            _InfoRow(
              icon: Icons.error_outline,
              text: 'Last sync problem: ${sync.lastError}',
              color: AppColors.error,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => showWhyNotCountedSheet(context),
                  icon: const Icon(Icons.help_outline, size: 18),
                  label: const Text('Why are some steps not counted?'),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                ),
              ),
              TextButton(
                onPressed: sync.syncing ? null : () => sync.syncNow(force: true),
                child: const Text('Sync now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c))),
        ],
      ),
    );
  }
}

/// Bottom sheet explaining verified / pending / rejected / suspicious /
/// unwitnessed steps and the engine's rejection reasons in plain language.
Future<void> showWhyNotCountedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Why are some steps not counted?', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Your phone counts every step it feels, but StepUp checks each ten-second window '
              'against the movement sensors. Only steps that look like real walking or running '
              'are verified, and only verified steps count for challenges, bets, leaderboards '
              'and rewards.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('What the numbers mean', style: t.titleMedium),
            const SizedBox(height: 8),
            for (final (title, text) in kStepCategoryGlossary)
              _Entry(title: title, text: text),
            const SizedBox(height: 16),
            Text('Why steps get rejected', style: t.titleMedium),
            const SizedBox(height: 8),
            for (final r in kStepReasons) _Entry(title: r.title, text: r.explanation, code: r.code),
            const SizedBox(height: 16),
            Text(
              'No step checker is perfect. If you think genuine steps were missed, '
              'keep the phone on you while walking (pocket or hand) and keep tracking on.',
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    },
  );
}

class _Entry extends StatelessWidget {
  const _Entry({required this.title, required this.text, this.code});

  final String title;
  final String text;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleSmall),
          Text(text, style: t.bodyMedium),
          if (code != null)
            Text(code!, style: t.bodySmall?.copyWith(color: AppColors.textMuted, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
