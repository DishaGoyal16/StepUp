import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/step_models.dart';
import 'step_engine_channel.dart';

/// Tracks which user the native step ledger is bound to. Everything that reads
/// the engine on behalf of a user (sync, today's summary, starting tracking)
/// waits on [whenReady] first, so nothing runs under an unbound or previous
/// user. Binds are serialized: switching A -> B always binds B after A.
class StepEngineBinding extends ChangeNotifier {
  StepEngineBinding(this._engine);

  final StepEngineChannel _engine;

  String? _uid;
  bool _ready = false;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _pending;
  BindResult? _lastResult;
  AppException? _error;

  /// The user the app wants the engine bound to (null = signed out).
  String? get uid => _uid;

  /// True once the engine confirmed the binding for [uid].
  bool get isReady => _ready;

  BindResult? get lastResult => _lastResult;
  AppException? get error => _error;

  /// Starts binding [uid]. The returned future completes when the attempt
  /// finished (successfully or not); check [isReady].
  Future<void> bind(String uid) {
    _uid = uid;
    _ready = false;
    _error = null;
    _notify();
    return _enqueue(uid);
  }

  Future<void> _enqueue(String uid) {
    final run = _tail.then((_) => _doBind(uid));
    _tail = run;
    _pending = run;
    return run;
  }

  Future<void> _doBind(String uid) async {
    if (_uid != uid) return; // superseded by a newer bind / unbind
    try {
      final r = await _engine.bindUser(uid);
      if (_uid == uid) {
        _ready = true;
        _lastResult = r;
        _error = null;
      }
    } on AppException catch (e) {
      if (_uid == uid) _error = e;
    } catch (_) {
      if (_uid == uid) {
        _error = const AppException(code: 'engine-error', message: 'The step engine could not be bound.');
      }
    }
    _notify();
  }

  /// Marks the engine as unbound (signed out / switching user).
  void unbind() {
    _uid = null;
    _ready = false;
    _error = null;
    _notify();
  }

  /// Waits for any in-flight bind and returns whether the engine is bound.
  /// A failed bind is retried once here.
  Future<bool> whenReady() async {
    await _pending;
    final u = _uid;
    if (u != null && !_ready && _error != null) {
      await bind(u);
    }
    return _ready;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
