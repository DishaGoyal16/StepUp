import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddy_models.dart';
import '../../domain/profile_enums.dart';
import 'buddy_filter_sheet.dart';
import 'buddy_finder_view_model.dart';
import 'buddy_labels.dart';
import 'buddy_profile_card.dart';
import 'buddy_profile_sheet.dart';
import 'buddy_ui_actions.dart';

/// "Find buddies" tab: search box, filters, result list with pagination.
class BuddyFinderTab extends StatefulWidget {
  const BuddyFinderTab({super.key});

  @override
  State<BuddyFinderTab> createState() => _BuddyFinderTabState();
}

class _BuddyFinderTabState extends State<BuddyFinderTab> {
  final TextEditingController _search = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      _seeded = true;
      _search.text = context.read<BuddyFinderViewModel>().filters.query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters(BuddyFinderViewModel vm) async {
    final next = await showBuddyFilterSheet(context, current: vm.filters, hostels: vm.hostels);
    if (next != null) await vm.applyFilters(next);
  }

  void _clearAll(BuddyFinderViewModel vm) {
    _search.clear();
    vm.setQuery('');
    vm.clearFilters();
  }

  List<({String label, BuddyFilters Function(BuddyFilters) remove})> _activeFilters(
    BuddyFinderViewModel vm,
  ) {
    final f = vm.filters;
    return [
      if (f.fitnessLevel != null)
        (label: f.fitnessLevel!.label, remove: (x) => x.copyWith(fitnessLevel: null)),
      if (f.sports.isNotEmpty)
        (label: (f.sports.toList()..sort()).join(', '), remove: (x) => x.copyWith(sports: {})),
      if (f.hostelId != null)
        (label: vm.hostelName(f.hostelId) ?? f.hostelId!, remove: (x) => x.copyWith(hostelId: null)),
      if (f.preferredTime != null)
        (label: f.preferredTime!.label, remove: (x) => x.copyWith(preferredTime: null)),
      if (f.goals.isNotEmpty)
        (label: (f.goals.toList()..sort()).join(', '), remove: (x) => x.copyWith(goals: {})),
      if (f.availability.isNotEmpty)
        (label: daysSummary(f.availability), remove: (x) => x.copyWith(availability: {})),
      if (f.buddyType != null)
        (
          label: f.buddyType == BuddyType.individual ? 'Individual' : 'Group',
          remove: (x) => x.copyWith(buddyType: null),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BuddyFinderViewModel>();
    final active = _activeFilters(vm);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('buddySearchField'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  maxLength: BuddyFilters.maxQueryLength,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  onChanged: (v) {
                    vm.setQuery(v);
                    setState(() {});
                  },
                  onSubmitted: (_) => vm.refresh(),
                  decoration: InputDecoration(
                    hintText: 'Search students by name',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              vm.setQuery('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Badge(
                isLabelVisible: vm.filters.activeCount > 0,
                label: Text('${vm.filters.activeCount}'),
                child: IconButton.filledTonal(
                  key: const Key('openFilters'),
                  tooltip: 'Filters',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _openFilters(vm),
                ),
              ),
            ],
          ),
        ),
        if (active.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
              children: [
                for (final a in active)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(a.label),
                      onDeleted: () => vm.applyFilters(a.remove(vm.filters)),
                    ),
                  ),
                ActionChip(label: const Text('Clear all'), onPressed: () => _clearAll(vm)),
              ],
            ),
          ),
        Expanded(child: _Results(vm: vm, onClearAll: () => _clearAll(vm))),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.vm, required this.onClearAll});

  final BuddyFinderViewModel vm;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    switch (vm.status) {
      case FinderStatus.idle:
      case FinderStatus.loading:
        return const LoadingState(label: 'Finding students...');
      case FinderStatus.error:
        return ErrorState(
          message: vm.error?.message ?? 'Could not load students.',
          onRetry: vm.retry,
        );
      case FinderStatus.ready:
        break;
    }
    if (vm.profiles.isEmpty) {
      final filtered = vm.filters.hasAny;
      return RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            EmptyState(
              icon: Icons.search_off,
              title: 'No students found',
              message: filtered
                  ? 'Try a different name or remove some filters.'
                  : 'No other students are discoverable yet. Check back soon.',
              actionLabel: filtered ? 'Clear filters' : null,
              onAction: filtered ? onClearAll : null,
            ),
          ],
        ),
      );
    }
    final items = vm.profiles;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300) vm.loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: vm.refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md - 4),
          itemBuilder: (context, i) {
            if (i == items.length) return _Footer(vm: vm);
            final p = items[i];
            return BuddyProfileCard(
              key: ValueKey('buddy_${p.uid}'),
              profile: p,
              hostelName: vm.hostelName(p.hostelId),
              busy: vm.isBusy(p.uid),
              onView: () => showBuddyProfileSheet(context, vm: vm, uid: p.uid),
              onSend: () => BuddyFinderActions.sendRequest(context, vm, p),
              onCancel: () => BuddyFinderActions.cancelRequest(context, vm, p),
              onAccept: () => BuddyFinderActions.respond(context, vm, p, accept: true),
              onReject: () => BuddyFinderActions.respond(context, vm, p, accept: false),
            );
          },
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.vm});

  final BuddyFinderViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ErrorState(message: vm.loadMoreError!.message, onRetry: vm.loadMore, compact: true),
      );
    }
    if (vm.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(
          child: SecondaryButton(
            label: 'Load more',
            expand: false,
            icon: Icons.expand_more,
            onPressed: vm.loadMore,
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Text('That is everyone for now.', style: TextStyle(color: AppColors.textMuted)),
      ),
    );
  }
}
