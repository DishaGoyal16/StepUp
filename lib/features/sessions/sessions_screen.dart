import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/sport_models.dart';
import '../../data/repositories/local_repositories.dart';
import '../../widgets/common_widgets.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────
// SESSIONS SCREEN
// ─────────────────────────────────────────────────────────
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.read(localSessionRepositoryProvider).getDemoSessions();
    final user = ref.read(localUserRepositoryProvider).getCurrentUser() ??
        ref.read(localUserRepositoryProvider).createDemoUser();

    return Scaffold(
      appBar: AppBar(title: const Text('Sport Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/sport-buddy/sessions/create'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Session',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _VerificationNotice(),
          Expanded(
            child: sessions.isEmpty
                ? _EmptySessions()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, i) => _SessionCard(
                      session: sessions[i],
                      userId: user.id,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VerificationNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border:
            Border.all(color: AppColors.secondary.withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Text('🤝', style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sessions are verified by mutual check-in — both players confirm attendance.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SportSession session;
  final String userId;
  const _SessionCard({required this.session, required this.userId});

  @override
  Widget build(BuildContext context) {
    final isUpcoming =
        session.status == SessionStatus.upcoming;
    final isOrganizer = session.organizerId == userId;
    final isConfirmed = session.isConfirmedBy(userId);
    final spotsFilled =
        '${session.currentCount}/${session.maxParticipants}';
    final scheduledStr =
        DateFormat('EEE d MMM, h:mm a').format(session.scheduledAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isConfirmed
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_sportEmoji(session.sport),
                  style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.sport,
                        style:
                            Theme.of(context).textTheme.titleMedium),
                    Text(session.location,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusChip(session.status),
                  const SizedBox(height: 4),
                  Text('👥 $spotsFilled',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(scheduledStr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              XPDisplay(amount: session.xpReward, fontSize: 12),
              const SizedBox(width: 12),
              CoinDisplay(amount: session.coinReward, fontSize: 12),
              const Spacer(),
              if (isUpcoming && !isOrganizer)
                _JoinButton(
                  isJoined: session.participantIds.contains(userId),
                  isFull: session.isFull,
                ),
              if (isOrganizer)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        AppColors.secondary.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  child: const Text('Organizer',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          if (isConfirmed) ...[
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.check_circle_rounded,
                    size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Text('You confirmed attendance',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.primary)),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  String _sportEmoji(String sport) {
    const map = {
      'Badminton': '🏸',
      'Cricket': '🏏',
      'Football': '⚽',
      'Basketball': '🏀',
      'Volleyball': '🏐',
      'Running': '🏃',
      'Table Tennis': '🏓',
      'Tennis': '🎾',
      'Gym/Workout': '💪',
    };
    return map[sport] ?? '🏟️';
  }
}

class _StatusChip extends StatelessWidget {
  final SessionStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final label = status.name[0].toUpperCase() + status.name.substring(1);
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  Color _color() {
    switch (status) {
      case SessionStatus.upcoming:
        return AppColors.secondary;
      case SessionStatus.active:
        return AppColors.primary;
      case SessionStatus.completed:
        return AppColors.accent;
      case SessionStatus.cancelled:
        return AppColors.danger;
      case SessionStatus.disputed:
        return AppColors.warning;
    }
  }
}

class _JoinButton extends StatelessWidget {
  final bool isJoined;
  final bool isFull;
  const _JoinButton({required this.isJoined, required this.isFull});

  @override
  Widget build(BuildContext context) {
    if (isFull && !isJoined) {
      return const Text('Full',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.warning));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: isJoined ? null : AppColors.primaryGradient,
        color: isJoined ? AppColors.darkBorder : null,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        isJoined ? '✓ Joined' : 'Join',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color:
              isJoined ? AppColors.textSecondary : Colors.black,
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏟️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No sessions yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('Create a session and invite your sport buddies',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// CREATE SESSION SCREEN
// ─────────────────────────────────────────────────────────
class CreateSessionScreen extends ConsumerStatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  ConsumerState<CreateSessionScreen> createState() =>
      _CreateSessionScreenState();
}

class _CreateSessionScreenState
    extends ConsumerState<CreateSessionScreen> {
  String _sport = AppConstants.supportedSports.first;
  String _location = '';
  int _maxParticipants = 4;
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 2));
  final _locationController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a location'),
            backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() => _isCreating = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final user =
        ref.read(localUserRepositoryProvider).getCurrentUser() ??
            ref.read(localUserRepositoryProvider).createDemoUser();

    final session = SportSession(
      id: _uuid.v4(),
      organizerId: user.id,
      organizerName: user.name,
      sport: _sport,
      location: _locationController.text.trim(),
      scheduledAt: _scheduledAt,
      maxParticipants: _maxParticipants,
      participantIds: [user.id],
      participantNames: [user.name],
      status: SessionStatus.upcoming,
      xpReward: AppConstants.xpSportSession,
      coinReward: AppConstants.coinsSportSession,
      isDemoData: true,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Session created! (Demo — not persisted)'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.go('/sport-buddy/sessions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Session')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel('Sport'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _sport,
              dropdownColor: AppColors.darkCard,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(),
              items: AppConstants.supportedSports
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _sport = v!),
            ),
            const SizedBox(height: 20),
            _FieldLabel('Location'),
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              style:
                  const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'e.g. Sports Complex — Court 3',
              ),
            ),
            const SizedBox(height: 20),
            _FieldLabel('Date & Time'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _scheduledAt,
                  firstDate: DateTime.now(),
                  lastDate:
                      DateTime.now().add(const Duration(days: 30)),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.dark(
                        primary: AppColors.primary,
                        surface: AppColors.darkCard,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (date != null && mounted) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime:
                        TimeOfDay.fromDateTime(_scheduledAt),
                  );
                  if (time != null) {
                    setState(() => _scheduledAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute));
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius:
                      BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('EEE d MMM, h:mm a')
                          .format(_scheduledAt),
                      style: const TextStyle(
                          fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_rounded,
                        size: 14,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _FieldLabel('Max Participants'),
                Text(
                  '$_maxParticipants players',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Slider(
              value: _maxParticipants.toDouble(),
              min: 2,
              max: 20,
              divisions: 18,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.darkBorder,
              onChanged: (v) =>
                  setState(() => _maxParticipants = v.round()),
            ),
            const SizedBox(height: 24),
            _RewardPreview(),
            const SizedBox(height: 24),
            GradientButton(
              text: 'Create Session 🏸',
              onPressed: _create,
              isLoading: _isCreating,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: AppColors.textSecondary));
  }
}

class _RewardPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:
            Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _RewardItem('⚡ ${AppConstants.xpSportSession} XP',
              'on completion'),
          _RewardItem('🪙 ${AppConstants.coinsSportSession}',
              'StepCoins earned'),
          _RewardItem('🏆 Session', 'Badge possible'),
        ],
      ),
    );
  }
}

class _RewardItem extends StatelessWidget {
  final String value;
  final String label;
  const _RewardItem(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
