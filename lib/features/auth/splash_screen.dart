import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/widgets/stepup_logo.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/auth_state.dart';
import 'session_controller.dart';

/// Shown while auth/profile state resolves. If loading the profile failed it
/// offers Retry and Sign out instead of spinning forever.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final failed = session.state.profileStatus == ProfileStatus.error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StepUpLogo(size: 56),
                    const SizedBox(height: 24),
                    ErrorState(
                      message: 'We could not load your profile. Check your connection.',
                      onRetry: session.retryProfile,
                    ),
                    TextButton(
                      onPressed: () => context.read<AppDependencies>().signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StepUpLogo(),
                    SizedBox(height: 32),
                    CircularProgressIndicator(),
                  ],
                ),
        ),
      ),
    );
  }
}
