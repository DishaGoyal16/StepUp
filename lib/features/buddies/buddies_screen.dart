import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_dependencies.dart';
import '../../core/router/app_routes.dart';
import '../../core/widgets/widgets.dart';
import '../../data/buddies/buddies_repository.dart';
import '../auth/session_controller.dart';
import 'buddy_finder_tab.dart';
import 'buddy_finder_view_model.dart';
import 'buddy_requests_view_model.dart';
import 'my_buddies_tab.dart';
import 'my_buddies_view_model.dart';

/// Buddies tab: "Find buddies" and "My buddies" segments, and a "Requests"
/// button whose badge shows the pending incoming requests
/// ([BuddyRequestsCount], provided here).
class BuddiesScreen extends StatefulWidget {
  const BuddiesScreen({super.key});

  @override
  State<BuddiesScreen> createState() => _BuddiesScreenState();
}

class _BuddiesScreenState extends State<BuddiesScreen> {
  BuddyFinderViewModel? _finder;
  MyBuddiesViewModel? _mine;
  BuddyRequestsCount? _count;
  String? _uid;
  int _segment = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final uid = session.profile?.uid ?? session.user?.uid;
    if (uid == null) return;
    if (_uid != uid) {
      _disposeModels();
      _uid = uid;
      final repo = context.read<BuddiesRepository>();
      final deps = context.read<AppDependencies>();
      _finder = BuddyFinderViewModel(
        repository: repo,
        uid: uid,
        loadHostels: deps.hostels.load,
      )..start();
      _mine = MyBuddiesViewModel(repository: repo, uid: uid, loadHostels: deps.hostels.load)
        ..start();
      _count = BuddyRequestsCount(repository: repo, uid: uid)..start();
    }
  }

  void _disposeModels() {
    _finder?.dispose();
    _mine?.dispose();
    _count?.dispose();
    _finder = null;
    _mine = null;
    _count = null;
  }

  @override
  void dispose() {
    _disposeModels();
    super.dispose();
  }

  Future<void> _openRequests() async {
    final finder = _finder;
    await context.push(AppRoutes.buddyRequests);
    // Requests may have been answered meanwhile: refresh relations.
    if (mounted) finder?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final finder = _finder;
    final mine = _mine;
    final count = _count;
    if (finder == null || mine == null || count == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Buddies')),
        body: const LoadingState(),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BuddyFinderViewModel>.value(value: finder),
        ChangeNotifierProvider<MyBuddiesViewModel>.value(value: mine),
        ChangeNotifierProvider<BuddyRequestsCount>.value(value: count),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buddies'),
          actions: [
            _RequestsButton(onPressed: _openRequests),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, icon: Icon(Icons.search), label: Text('Find buddies')),
                      ButtonSegment(value: 1, icon: Icon(Icons.group), label: Text('My buddies')),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) => setState(() => _segment = s.first),
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _segment,
                  children: [
                    const BuddyFinderTab(),
                    MyBuddiesTab(onFindBuddies: () => setState(() => _segment = 0)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Requests" header button with the live pending-request count as a badge.
class _RequestsButton extends StatelessWidget {
  const _RequestsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final count = context.watch<BuddyRequestsCount>().count;
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      offset: const Offset(-4, 2),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.mail_outline),
        label: const Text('Requests'),
      ),
    );
  }
}
