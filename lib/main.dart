import 'package:flutter/material.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/not_configured_screen.dart';
import 'data/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  if (!config.isConfigured) {
    runApp(MaterialApp(
      title: 'StepUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const BackendNotConfiguredScreen(),
    ));
    return;
  }

  try {
    await initializeFirebase(config);
  } catch (e) {
    runApp(MaterialApp(
      title: 'StepUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _StartupFailed(error: '$e'),
    ));
    return;
  }
  runApp(StepUpApp(deps: AppDependencies.firebase(config)));
}

class _StartupFailed extends StatelessWidget {
  const _StartupFailed({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Could not start StepUp', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'Firebase failed to initialise with the supplied configuration.\n$error',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
