import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_card.dart';
import 'stepup_logo.dart';

/// Shown by `main()` when the Firebase `--dart-define` values are missing.
/// StepUp never fakes a backend: without configuration there is nothing to
/// sign in to.
class BackendNotConfiguredScreen extends StatelessWidget {
  const BackendNotConfiguredScreen({super.key});

  static const String productionCommand = 'flutter run \\\n'
      '  --dart-define=FIREBASE_API_KEY=<api key> \\\n'
      '  --dart-define=FIREBASE_APP_ID=<app id> \\\n'
      '  --dart-define=FIREBASE_PROJECT_ID=<project id> \\\n'
      '  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender id> \\\n'
      '  --dart-define=FIREBASE_STORAGE_BUCKET=<bucket>';

  static const String emulatorCommand = 'flutter run \\\n'
      '  --dart-define=USE_FIREBASE_EMULATOR=true \\\n'
      '  --dart-define=EMULATOR_HOST=10.0.2.2';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: StepUpLogo(size: 56)),
                  const SizedBox(height: 24),
                  Text('Backend not configured', style: t.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'This build has no Firebase project settings, so StepUp cannot sign anyone in. '
                    'Nothing is faked: provide the settings when you run or build the app.',
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text('Real Firebase project', style: t.titleMedium),
                  const SizedBox(height: 8),
                  const _Command(text: productionCommand),
                  const SizedBox(height: 16),
                  Text('Local Firebase emulators (project demo-stepup)', style: t.titleMedium),
                  const SizedBox(height: 8),
                  const _Command(text: emulatorCommand),
                  const SizedBox(height: 8),
                  Text(
                    'On a physical phone run "adb reverse" for the emulator ports and use EMULATOR_HOST=127.0.0.1. '
                    'See FIREBASE_SETUP.md for the full steps.',
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Command extends StatelessWidget {
  const _Command({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.mint,
      shadow: false,
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppColors.text),
      ),
    );
  }
}
