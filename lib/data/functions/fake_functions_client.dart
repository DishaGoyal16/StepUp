import '../../core/errors/app_exception.dart';
import 'functions_client.dart';

/// A recorded call to [FakeFunctionsClient].
class FakeCall {
  const FakeCall(this.name, this.params);

  final String name;
  final Map<String, dynamic> params;
}

/// Scriptable [FunctionsClient] for tests.
///
/// ```dart
/// final fn = FakeFunctionsClient()
///   ..on('registerDevice', (p) => {'isRewardDevice': true})
///   ..failNext('syncStepBuckets', AppException.fromCallable(code: 'unavailable'));
/// ```
class FakeFunctionsClient implements FunctionsClient {
  final Map<String, Map<String, dynamic> Function(Map<String, dynamic> params)> _handlers = {};
  final Map<String, List<Object>> _failures = {};

  /// Every call made, in order.
  final List<FakeCall> calls = [];

  /// Registers a handler returning the callable's result.
  void on(String name, Map<String, dynamic> Function(Map<String, dynamic> params) handler) {
    _handlers[name] = handler;
  }

  /// Queues an error thrown by the next call to [name].
  void failNext(String name, Object error) {
    (_failures[name] ??= []).add(error);
  }

  Iterable<FakeCall> callsTo(String name) => calls.where((c) => c.name == name);

  @override
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> params = const {}]) async {
    calls.add(FakeCall(name, Map<String, dynamic>.from(params)));
    final queue = _failures[name];
    if (queue != null && queue.isNotEmpty) {
      throw queue.removeAt(0);
    }
    final handler = _handlers[name];
    if (handler == null) {
      throw AppException.fromCallable(code: 'not-found', message: 'No fake handler for $name');
    }
    return handler(params);
  }
}
