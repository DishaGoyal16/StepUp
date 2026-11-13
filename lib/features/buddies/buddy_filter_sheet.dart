import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_models.dart';
import '../../domain/hostel.dart';
import '../../domain/profile_enums.dart';
import 'buddy_labels.dart';

/// Bottom sheet with every finder filter. Returns the new filters when the
/// student taps "Apply" (an empty [BuddyFilters] for "Clear all"), or null
/// when it is dismissed.
Future<BuddyFilters?> showBuddyFilterSheet(
  BuildContext context, {
  required BuddyFilters current,
  required HostelDirectory? hostels,
}) {
  return showModalBottomSheet<BuddyFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(current: current, hostels: hostels),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.hostels});

  final BuddyFilters current;
  final HostelDirectory? hostels;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late BuddyFilters _draft = widget.current;

  Set<String> _toggle(Set<String> set, String value) {
    final next = {...set};
    if (!next.remove(value)) next.add(value);
    return next;
  }

  Widget _multi(List<String> options, Set<String> selected, ValueChanged<String> onToggle,
      {String Function(String)? label}) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(label?.call(o) ?? o),
            selected: selected.contains(o),
            onSelected: (_) => onToggle(o),
          ),
      ],
    );
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hostels = widget.hostels;
    final hostelList = hostels == null
        ? const <Hostel>[]
        : [...hostels.general, ...hostels.girls];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text('Filters', style: Theme.of(context).textTheme.titleLarge),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(BuddyFilters.empty),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _section(
                'Fitness level',
                FilterChipsRow<FitnessLevel?>(
                  options: const [null, ...FitnessLevel.values],
                  selected: _draft.fitnessLevel,
                  onSelected: (v) => setState(() => _draft = _draft.copyWith(fitnessLevel: v)),
                  labelOf: (v) => v?.label ?? 'Any',
                ),
              ),
              _section(
                'Sports',
                _multi(
                  kSportsOptions,
                  _draft.sports,
                  (s) => setState(() => _draft = _draft.copyWith(sports: _toggle(_draft.sports, s))),
                ),
              ),
              _section(
                'Hostel',
                DropdownButtonFormField<String?>(
                  key: ValueKey('hostel_${_draft.hostelId}'),
                  initialValue: _draft.hostelId,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'Any hostel'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Any hostel')),
                    for (final h in hostelList)
                      DropdownMenuItem<String?>(
                        value: h.id,
                        child: Text(h.displayName, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(hostelId: v)),
                ),
              ),
              _section(
                'Preferred activity time',
                FilterChipsRow<PreferredTime?>(
                  options: const [null, ...PreferredTime.values],
                  selected: _draft.preferredTime,
                  onSelected: (v) => setState(() => _draft = _draft.copyWith(preferredTime: v)),
                  labelOf: (v) => v?.label ?? 'Any',
                ),
              ),
              _section(
                'Fitness goals',
                _multi(
                  BuddyFilters.goalOptions,
                  _draft.goals,
                  (s) => setState(() => _draft = _draft.copyWith(goals: _toggle(_draft.goals, s))),
                ),
              ),
              _section(
                'Available on',
                _multi(
                  BuddyFilters.weekdays,
                  _draft.availability,
                  (s) => setState(
                    () => _draft = _draft.copyWith(availability: _toggle(_draft.availability, s)),
                  ),
                  label: dayLabel,
                ),
              ),
              _section(
                'Buddy type',
                FilterChipsRow<BuddyType?>(
                  options: const [null, ...BuddyFilters.buddyTypeOptions],
                  selected: _draft.buddyType,
                  onSelected: (v) => setState(() => _draft = _draft.copyWith(buddyType: v)),
                  labelOf: (v) => v == null ? 'Any' : (v == BuddyType.individual ? 'Individual' : 'Group'),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: PrimaryButton(
              label: _draft.activeCount == 0 ? 'Show all students' : 'Apply ${_draft.activeCount} filter${_draft.activeCount == 1 ? '' : 's'}',
              onPressed: () => Navigator.of(context).pop(_draft),
            ),
          ),
        ),
      ],
    );
  }
}
