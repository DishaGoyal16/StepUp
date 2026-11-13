import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_models.dart';
import 'buddy_labels.dart';

/// Small rounded label (sport, goal, weekday...).
class BuddyPill extends StatelessWidget {
  const BuddyPill(this.text, {super.key, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primary : AppColors.mint,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: highlight ? Colors.white : AppColors.text,
        ),
      ),
    );
  }
}

/// "Buddy" / "Pending" / "Wants to connect" status badge (nothing for NONE).
class RelationBadge extends StatelessWidget {
  const RelationBadge(this.relation, {super.key});

  final BuddyRelation relation;

  @override
  Widget build(BuildContext context) {
    if (relation == BuddyRelation.none) return const SizedBox.shrink();
    final isBuddy = relation == BuddyRelation.buddy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBuddy ? AppColors.mint : AppColors.grey,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: isBuddy ? Border.all(color: AppColors.secondary) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isBuddy ? Icons.check_circle : Icons.hourglass_top,
            size: 14,
            color: isBuddy ? AppColors.primary : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              relationBadgeLabel(relation),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isBuddy ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The buttons that match a student's [BuddyProfile.relation]:
/// NONE -> Send Buddy Request, REQUEST_SENT -> Cancel request,
/// REQUEST_RECEIVED -> Reject / Accept, BUDDY -> nothing (badge only).
class BuddyRelationActions extends StatelessWidget {
  const BuddyRelationActions({
    super.key,
    required this.relation,
    required this.busy,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.onReject,
  });

  final BuddyRelation relation;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    switch (relation) {
      case BuddyRelation.none:
        return PrimaryButton(
          label: 'Send Buddy Request',
          icon: Icons.person_add_alt_1,
          loading: busy,
          onPressed: onSend,
        );
      case BuddyRelation.requestSent:
        return SecondaryButton(
          label: 'Cancel request',
          icon: Icons.close,
          onPressed: busy ? null : onCancel,
        );
      case BuddyRelation.requestReceived:
        return Row(
          children: [
            Expanded(child: SecondaryButton(label: 'Reject', onPressed: busy ? null : onReject)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: PrimaryButton(label: 'Accept', loading: busy, onPressed: onAccept)),
          ],
        );
      case BuddyRelation.buddy:
        return const SizedBox.shrink();
    }
  }
}

/// A student in the finder list. Shows only public-profile data: name,
/// avatar, hostel (when shared), fitness level, sports, weekly verified steps
/// (when shared), preferred activity and bio. Never e-mail or location.
class BuddyProfileCard extends StatelessWidget {
  const BuddyProfileCard({
    super.key,
    required this.profile,
    required this.hostelName,
    required this.busy,
    required this.onView,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.onReject,
  });

  final BuddyProfile profile;
  final String? hostelName;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  static const int _maxSports = 4;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = profile;
    final prefs = preferenceSummary(p);
    final shownSports = p.sportsInterests.take(_maxSports).toList();
    final extra = p.sportsInterests.length - shownSports.length;
    return AppCard(
      onTap: onView,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarCircle(name: p.displayName, photoUrl: p.photoUrl, radius: 26),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName,
                      style: t.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hostelName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.apartment, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                hostelName!,
                                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (p.fitnessLevel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          p.fitnessLevel!.label,
                          style: t.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (p.relation != BuddyRelation.none)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: RelationBadge(p.relation),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (shownSports.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm + 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in shownSports) BuddyPill(s),
                if (extra > 0) BuddyPill('+$extra'),
              ],
            ),
          ],
          if (p.weeklyVerifiedSteps != null || prefs != null) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            if (p.weeklyVerifiedSteps != null)
              _InfoLine(
                icon: Icons.directions_walk,
                text: '${formatSteps(p.weeklyVerifiedSteps!)} verified steps this week',
              ),
            if (prefs != null) _InfoLine(icon: Icons.schedule, text: prefs),
          ],
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(p.bio, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (p.relation != BuddyRelation.buddy) ...[
            const SizedBox(height: AppSpacing.md - 4),
            BuddyRelationActions(
              relation: p.relation,
              busy: busy,
              onSend: onSend,
              onCancel: onCancel,
              onAccept: onAccept,
              onReject: onReject,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onView, child: const Text('View profile')),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
