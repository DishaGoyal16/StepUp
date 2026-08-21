import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/hive_keys.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

const _uuid = Uuid();

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Form state
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _department = AppConstants.departments.first;
  String _year = AppConstants.years.first;
  String _hostel = AppConstants.hostels.first;
  final _selectedSports = <String>{};
  final _skillLevels = <String, String>{};
  final _selectedDays = <String>{};
  final _selectedTimes = <String>{};
  String _campusZone = AppConstants.campusZones.first;
  int _groupMin = 2;
  int _groupMax = 4;
  bool _isSaving = false;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _times = [
    'Morning (6–8 AM)',
    'Lunch Break (12–2 PM)',
    '4 PM – 6 PM',
    '6 PM – 8 PM',
    'Evening (8–10 PM)',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  bool get _canProceed {
    switch (_currentPage) {
      case 0:
        return true;
      case 1:
        return _nameController.text.trim().length >= 2 &&
            _emailController.text.contains('@thapar.edu');
      case 2:
        return true;
      case 3:
        return _selectedSports.isNotEmpty;
      case 4:
        return _selectedDays.isNotEmpty && _selectedTimes.isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _finish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = UserModel(
        id: _uuid.v4(),
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        department: _department,
        year: _year,
        hostel: _hostel,
        xp: 0,
        level: 1,
        stepCoins: AppConstants.startingWalletBalance,
        sports: _selectedSports.toList(),
        skillLevels: _skillLevels,
        availableDays: _selectedDays.toList(),
        availableTimes: _selectedTimes.toList(),
        preferredGroupSizeMin: _groupMin,
        preferredGroupSizeMax: _groupMax,
        campusZone: _campusZone,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );

      await ref.read(localUserRepositoryProvider).saveUser(user);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(HiveKeys.onboardingDone, true);

      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgress(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WelcomePage(onNext: _nextPage),
                  _ProfilePage(
                    nameController: _nameController,
                    emailController: _emailController,
                    department: _department,
                    year: _year,
                    hostel: _hostel,
                    onDepartmentChanged: (v) =>
                        setState(() => _department = v!),
                    onYearChanged: (v) => setState(() => _year = v!),
                    onHostelChanged: (v) => setState(() => _hostel = v!),
                    onChanged: () => setState(() {}),
                  ),
                  _PrivacyPage(onNext: _nextPage),
                  _SportPage(
                    selectedSports: _selectedSports,
                    skillLevels: _skillLevels,
                    onToggleSport: (sport) {
                      setState(() {
                        if (_selectedSports.contains(sport)) {
                          _selectedSports.remove(sport);
                          _skillLevels.remove(sport);
                        } else {
                          _selectedSports.add(sport);
                          _skillLevels[sport] = 'Intermediate';
                        }
                      });
                    },
                    onSkillChanged: (sport, skill) =>
                        setState(() => _skillLevels[sport] = skill),
                  ),
                  _AvailabilityPage(
                    selectedDays: _selectedDays,
                    selectedTimes: _selectedTimes,
                    campusZone: _campusZone,
                    groupMin: _groupMin,
                    groupMax: _groupMax,
                    onDayToggle: (d) => setState(() {
                      _selectedDays.contains(d)
                          ? _selectedDays.remove(d)
                          : _selectedDays.add(d);
                    }),
                    onTimeToggle: (t) => setState(() {
                      _selectedTimes.contains(t)
                          ? _selectedTimes.remove(t)
                          : _selectedTimes.add(t);
                    }),
                    onZoneChanged: (z) =>
                        setState(() => _campusZone = z!),
                    onGroupSizeChanged: (min, max) =>
                        setState(() {
                          _groupMin = min;
                          _groupMax = max;
                        }),
                    days: _days,
                    times: _times,
                  ),
                ],
              ),
            ),
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(5, (i) {
          final active = i == _currentPage;
          final done = i < _currentPage;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              decoration: BoxDecoration(
                color: done || active
                    ? AppColors.primary
                    : AppColors.darkBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          if (_currentPage > 0)
            IconButton(
              onPressed: _prevPage,
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textSecondary),
            ),
          const Spacer(),
          SizedBox(
            width: 160,
            child: GradientButton(
              text: _currentPage == 4 ? 'Get Started 🚀' : 'Continue',
              onPressed: _canProceed ? _nextPage : null,
              isLoading: _isSaving,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 0: Welcome ───────────────────────────────────────
class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Text('🏃', style: const TextStyle(fontSize: 72))
              .animate()
              .scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            'Thapar StepUp',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'Your Campus. Your Steps.\nYour Challenge.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 350.ms),
          const SizedBox(height: 48),
          _FeatureRow(
            emoji: '🛡',
            title: 'Verified Steps Only',
            subtitle:
                'Our integrity engine filters fake steps from shaking or vehicles',
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            emoji: '🏆',
            title: 'Campus Challenges',
            subtitle:
                'Compete in daily, weekly, and hostel-wide step challenges',
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            emoji: '🤝',
            title: 'Sport Buddy Matching',
            subtitle: 'Find skill-matched sports partners across campus',
          ),
          const SizedBox(height: 20),
          _FeatureRow(
            emoji: '⚔️',
            title: 'Step Battles',
            subtitle:
                'Wager StepCoins on verified step counts vs friends',
          ),
        ].animate(interval: 80.ms).fadeIn().slideY(begin: 0.2),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  const _FeatureRow(
      {required this.emoji, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.5,
                      )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Page 1: Profile ────────────────────────────────────────
class _ProfilePage extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final String department;
  final String year;
  final String hostel;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onYearChanged;
  final ValueChanged<String?> onHostelChanged;
  final VoidCallback onChanged;

  const _ProfilePage({
    required this.nameController,
    required this.emailController,
    required this.department,
    required this.year,
    required this.hostel,
    required this.onDepartmentChanged,
    required this.onYearChanged,
    required this.onHostelChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Create Your Profile',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Your Thapar campus identity',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  )),
          const SizedBox(height: 28),
          _inputField(context, 'Full Name', nameController,
              hint: 'e.g. Disha Goyal', onChanged: (_) => onChanged()),
          const SizedBox(height: 16),
          _inputField(context, 'Thapar Email', emailController,
              hint: 'yourname@thapar.edu',
              keyboard: TextInputType.emailAddress,
              onChanged: (_) => onChanged()),
          const SizedBox(height: 16),
          _dropdownField(
            context,
            'Department',
            department,
            AppConstants.departments,
            onDepartmentChanged,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _dropdownField(
                  context, 'Year', year, AppConstants.years, onYearChanged),
            ),
          ]),
          const SizedBox(height: 16),
          _dropdownField(
            context,
            'Hostel',
            hostel,
            AppConstants.hostels,
            onHostelChanged,
          ),
        ],
      ),
    );
  }

  Widget _inputField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _dropdownField(
    BuildContext context,
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: AppColors.darkCard,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: const InputDecoration(),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ─── Page 2: Privacy ────────────────────────────────────────
class _PrivacyPage extends StatelessWidget {
  final VoidCallback onNext;
  const _PrivacyPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('🔐 Privacy First',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          _PrivacyCard(
            emoji: '📱',
            title: 'Health Data Stays on Device',
            body:
                'Step data is read from Health Connect (Android) or Apple Health (iOS). '
                'Raw sensor data from verified sessions is processed locally and '
                'immediately discarded — we never store accelerometer samples.',
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            emoji: '📍',
            title: 'No GPS Tracking',
            body:
                'We ask only for coarse campus zone (e.g. "Hostel Zone A"). '
                'We never track your GPS location or movement routes.',
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            emoji: '🤝',
            title: 'Sport Profile is Optional',
            body:
                'Your sport buddy profile is only visible to other students when you '
                'enable it. You can hide or delete it at any time in Settings.',
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            emoji: '🏆',
            title: 'Leaderboards Use Display Names',
            body:
                'Leaderboards show your display name and department only. '
                'Email addresses are never shown publicly.',
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            emoji: '🔬',
            title: 'Integrity Engine Transparency',
            body:
                'The activity integrity system uses a rule-based classifier (Prototype v1). '
                'Every classification decision is visible to you with full reasoning. '
                'No hidden scoring.',
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  const _PrivacyCard(
      {required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 4),
                Text(body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.5,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 3: Sport Selection ─────────────────────────────────
class _SportPage extends StatelessWidget {
  final Set<String> selectedSports;
  final Map<String, String> skillLevels;
  final void Function(String) onToggleSport;
  final void Function(String, String) onSkillChanged;

  const _SportPage({
    required this.selectedSports,
    required this.skillLevels,
    required this.onToggleSport,
    required this.onSkillChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Your Sports',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Select sports you play and your skill level',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppConstants.supportedSports.map((sport) {
              final selected = selectedSports.contains(sport);
              return GestureDetector(
                onTap: () => onToggleSport(sport),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.darkBorder,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    sport,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (selectedSports.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('Skill Levels',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...selectedSports.map((sport) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sport,
                          style: Theme.of(context).textTheme.bodyMedium),
                      DropdownButton<String>(
                        value: skillLevels[sport] ?? 'Intermediate',
                        dropdownColor: AppColors.darkCard,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        underline: const SizedBox(),
                        items: AppConstants.skillLevels
                            .map((l) => DropdownMenuItem(
                                value: l, child: Text(l)))
                            .toList(),
                        onChanged: (v) => onSkillChanged(sport, v!),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ─── Page 4: Availability ────────────────────────────────────
class _AvailabilityPage extends StatelessWidget {
  final Set<String> selectedDays;
  final Set<String> selectedTimes;
  final String campusZone;
  final int groupMin;
  final int groupMax;
  final void Function(String) onDayToggle;
  final void Function(String) onTimeToggle;
  final ValueChanged<String?> onZoneChanged;
  final void Function(int, int) onGroupSizeChanged;
  final List<String> days;
  final List<String> times;

  const _AvailabilityPage({
    required this.selectedDays,
    required this.selectedTimes,
    required this.campusZone,
    required this.groupMin,
    required this.groupMax,
    required this.onDayToggle,
    required this.onTimeToggle,
    required this.onZoneChanged,
    required this.onGroupSizeChanged,
    required this.days,
    required this.times,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Availability & Preferences',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Used for sport buddy matching — no GPS required',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Text('Available Days',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: days.map((day) {
              final sel = selectedDays.contains(day);
              return GestureDetector(
                onTap: () => onDayToggle(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.secondary.withOpacity(0.2)
                        : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: sel
                            ? AppColors.secondary
                            : AppColors.darkBorder),
                  ),
                  child: Text(day,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel
                            ? AppColors.secondary
                            : AppColors.textPrimary,
                      )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Preferred Times',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...times.map((time) {
            final sel = selectedTimes.contains(time);
            return GestureDetector(
              onTap: () => onTimeToggle(time),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.secondary.withOpacity(0.12)
                      : AppColors.darkCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: sel
                          ? AppColors.secondary
                          : AppColors.darkBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      sel
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: sel
                          ? AppColors.secondary
                          : AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(time,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Campus Zone',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: campusZone,
                      dropdownColor: AppColors.darkCard,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(),
                      items: AppConstants.campusZones
                          .map((z) =>
                              DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: onZoneChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Group Size Preference',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$groupMin – $groupMax players',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.primary)),
          RangeSlider(
            values: RangeValues(groupMin.toDouble(), groupMax.toDouble()),
            min: 2,
            max: 10,
            divisions: 8,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.darkBorder,
            onChanged: (v) =>
                onGroupSizeChanged(v.start.round(), v.end.round()),
          ),
        ],
      ),
    );
  }
}
