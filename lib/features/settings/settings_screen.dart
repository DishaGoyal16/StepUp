import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/settings_service.dart';
import '../../widgets/common_widgets.dart';

// ─────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final stepGoal = ref.watch(dailyStepGoalProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          _SettingsSection('Appearance', [
            _ToggleTile(
              icon: Icons.dark_mode_rounded,
              title: 'Dark Mode',
              value: isDark,
              onChanged: (v) {
                ref.read(themeModeProvider.notifier).state =
                    v ? ThemeMode.dark : ThemeMode.light;
              },
            ),
          ]),
          const SizedBox(height: 20),
          _SettingsSection('Activity Goals', [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.directions_walk_rounded,
                              size: 18, color: AppColors.primary),
                          SizedBox(width: 12),
                          Text('Daily Step Goal',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text(
                        '${(stepGoal / 1000).toStringAsFixed(stepGoal % 1000 == 0 ? 0 : 1)}K steps',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: stepGoal.toDouble(),
                  min: AppConstants.minDailyStepGoal.toDouble(),
                  max: AppConstants.maxDailyStepGoal.toDouble(),
                  divisions: 28,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.darkBorder,
                  onChanged: (v) {
                    ref.read(dailyStepGoalProvider.notifier).state =
                        v.round();
                  },
                ),
              ],
            ),
          ]),
          const SizedBox(height: 20),
          _SettingsSection('Developer & Testing', [
            _NavigationTile(
              icon: Icons.science_rounded,
              title: 'Demo Mode',
              subtitle: 'Preview app with simulated data',
              color: AppColors.accent,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DemoModeScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _SettingsSection('About', [
            _InfoTile(
              icon: Icons.info_outline_rounded,
              title: 'Version',
              value: AppConstants.version,
            ),
            _InfoTile(
              icon: Icons.code_rounded,
              title: 'Integrity Engine',
              value: 'Rule-Based v1 (Prototype)',
            ),
            _InfoTile(
              icon: Icons.school_rounded,
              title: 'Campus',
              value: 'TIET Patiala',
            ),
          ]),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                )),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// PRIVACY SCREEN
// ─────────────────────────────────────────────────────────
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Data')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _PrivacySection(
            title: '📱 Health Data',
            points: [
              'Step data is read from Health Connect (Android) or Apple Health (iOS)',
              'Only step count, distance, and activity type are read — not heart rate or other health metrics',
              'Data is processed on-device only — never sent to external servers in this prototype',
              'You can revoke health permissions at any time from your device Settings',
            ],
          ),
          SizedBox(height: 16),
          _PrivacySection(
            title: '📍 Location',
            points: [
              'No GPS tracking — we never record your location or route',
              'Campus zone (e.g. "Hostel Zone A") is self-reported during onboarding and used only for sport buddy matching',
              'Zone can be updated or removed at any time in your profile',
            ],
          ),
          SizedBox(height: 16),
          _PrivacySection(
            title: '🔬 Sensor Data',
            points: [
              'Accelerometer and gyroscope data is collected only during explicit Verified Sessions',
              'Raw sensor samples are processed locally and immediately discarded after feature extraction',
              'We store only the derived integrity classification result — never raw sensor data',
            ],
          ),
          SizedBox(height: 16),
          _PrivacySection(
            title: '👥 Social Features',
            points: [
              'Sport buddy profiles are visible to other students only when you enable visibility',
              'Leaderboards show your display name and department only — never your email',
              'You can hide your sport profile or delete your account at any time',
            ],
          ),
          SizedBox(height: 16),
          _PrivacySection(
            title: '🪙 StepCoins & Betting',
            points: [
              'StepCoins are a virtual in-app currency with no real monetary value',
              'No real money is involved in Step Battles — this is a prototype motivation system',
              'All StepCoin transactions are stored locally on your device only',
            ],
          ),
          SizedBox(height: 16),
          _PrivacySection(
            title: '🔐 Data Storage',
            points: [
              'All user data is stored locally on your device using Hive (key-value store)',
              'No backend servers are used in this prototype version',
              'You can delete all local data by uninstalling the app',
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final String title;
  final List<String> points;
  const _PrivacySection({required this.title, required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 10),
          ...points.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_rounded,
                          size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(height: 1.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    ).animate().fadeIn();
  }
}

// ─────────────────────────────────────────────────────────
// DEMO MODE SCREEN
// ─────────────────────────────────────────────────────────
class DemoModeScreen extends ConsumerWidget {
  const DemoModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemoMode = ref.watch(demoModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Demo Mode 🔬')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border:
                  Border.all(color: AppColors.accent.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text('🔬', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('Demo Mode',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppColors.accent)),
                const SizedBox(height: 8),
                const Text(
                  'Enables simulated health data and pre-populated scenarios '
                  'so you can explore all features without a real health app or campus context.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isDemoMode ? 'DEMO MODE ON' : 'DEMO MODE OFF',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDemoMode
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Switch(
                      value: isDemoMode,
                      onChanged: (v) {
                        ref.read(demoModeProvider.notifier).state = v;
                      },
                      activeColor: AppColors.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'What Demo Mode Shows'),
          const SizedBox(height: 12),
          ..._demoFeatures.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DemoFeatureTile(title: f.title, desc: f.desc),
              )),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: const Text(
              '⚠️ Demo data is clearly labeled throughout the app. '
              'All integrity classifications on demo data use the same rule-based engine as real data, '
              'so you can see exactly how the system evaluates each activity type.',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoFeatureTile extends StatelessWidget {
  final String title;
  final String desc;
  const _DemoFeatureTile({required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoItem {
  final String title;
  final String desc;
  const _DemoItem(this.title, this.desc);
}

const _demoFeatures = [
  _DemoItem(
    '🚶 Genuine Walking Session',
    '3,421 steps · cadence 97.7 steps/min · 4.25 km/h · classified as genuine',
  ),
  _DemoItem(
    '🏃 Genuine Running Session',
    '4,210 steps · cadence 163 steps/min · 8.2 km/h · classified as genuine',
  ),
  _DemoItem(
    '📱 Phone Shaking (Suspicious)',
    '711 steps · cadence 142 steps/min · 0 km/h · flagged as suspicious',
  ),
  _DemoItem(
    '🏆 Active Challenges',
    'Daily, weekly, campus, and hostel challenges with realistic progress',
  ),
  _DemoItem(
    '⚔️ Active Step Battle',
    'Live bet vs demo opponent with step progress visualization',
  ),
  _DemoItem(
    '🤝 Sport Buddy Matches',
    'Three ranked matches with full score breakdown for Badminton',
  ),
  _DemoItem(
    '🏸 Scheduled Sessions',
    'Two upcoming sessions with participants and mutual check-in flow',
  ),
  _DemoItem(
    '📊 Leaderboard',
    'Hostel leaderboard with 5 ranked students including your position',
  ),
];
