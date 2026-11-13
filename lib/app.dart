import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'app_dependencies.dart';
import 'app_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/notifications/push_service.dart';

/// Root widget: providers + router + theme (light only) and app-lifecycle
/// wiring for step tracking / sync / push.
class StepUpApp extends StatefulWidget {
  const StepUpApp({super.key, required this.deps, this.initialLocation});

  final AppDependencies deps;

  /// For tests / deep links; defaults to the splash screen.
  final String? initialLocation;

  @override
  State<StepUpApp> createState() => _StepUpAppState();
}

class _StepUpAppState extends State<StepUpApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  late final List<SingleChildWidget> _providers;
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<PushMessage>? _pushSub;
  String? _activeUid;
  bool _pushStarted = false;

  AppDependencies get _deps => widget.deps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _providers = appProviders(_deps);
    _router = buildRouter(_deps, initialLocation: widget.initialLocation);
    _deps.session.addListener(_onSession);
    _deps.session.start();
    _pushSub = _deps.push.foregroundMessages.listen(_showPush);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deps.session.removeListener(_onSession);
    _pushSub?.cancel();
    _deps.stepSync.stop();
    _deps.stepTracking.detach();
    _router.dispose();
    super.dispose();
  }

  /// Starts/stops background work as the signed-in, set-up user changes.
  void _onSession() {
    final s = _deps.session.state;
    final uid = s.isReady ? s.user!.uid : null;
    if (uid == _activeUid) return;
    final previous = _activeUid;
    _activeUid = uid;
    if (uid == null) {
      _deps.stepSync.deactivateUser();
      _deps.stepTracking.detach();
      return;
    }
    // Bind the native ledger to this user BEFORE any summary/sync/tracking.
    if (previous != null) _deps.stepTracking.detach();
    unawaited(_deps.stepSync.activateUser(uid).then((_) {
      if (_activeUid == uid) _foregroundWork();
    }));
    if (!_pushStarted) {
      _pushStarted = true;
      unawaited(_deps.push.init(onToken: (token) {
        _deps.stepSync.updateFcmToken(token);
        if (_activeUid != null) unawaited(_deps.stepSync.syncNow(force: true));
      }));
    }
  }

  void _foregroundWork() {
    if (_activeUid == null) return;
    _deps.stepTracking.attach();
    unawaited(_deps.stepTracking.refresh());
    _deps.stepSync.start();
    unawaited(_deps.stepSync.syncNow(force: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foregroundWork();
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _deps.stepSync.stop();
        _deps.stepTracking.detach();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _showPush(PushMessage m) {
    final text = [m.title, m.body].whereType<String>().where((s) => s.isNotEmpty).join(' - ');
    if (text.isEmpty) return;
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _providers,
      child: MaterialApp.router(
        title: 'StepUp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        scaffoldMessengerKey: _messengerKey,
        routerConfig: _router,
      ),
    );
  }
}
