import 'package:cloud_functions/cloud_functions.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';

/// Thin typed wrapper over Cloud Functions callables (region
/// `AppConfig.functionsRegion`). EVERY server call in the app goes through
/// this interface so that errors are uniform (`AppException`) and features can
/// be tested with `FakeFunctionsClient`.
///
/// ```dart
/// final res = await functions.call('searchBuddies', {'limit': 20});
/// final profiles = (res['profiles'] as List).cast<Map<String, dynamic>>();
/// ```
abstract class FunctionsClient {
  /// Calls the callable [name] and returns its result map. Throws
  /// [AppException] (`code`, `reason`, `message`) on any failure.
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> params = const {}]);
}

/// Recursively converts the platform channel's `Map<Object?, Object?>` /
/// `List<Object?>` structures into `Map<String, dynamic>` / `List<dynamic>`.
Object? normalizeCallableData(Object? v) {
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): normalizeCallableData(e.value)};
  }
  if (v is List) return [for (final e in v) normalizeCallableData(e)];
  return v;
}

/// `cloud_functions` implementation.
class FirebaseFunctionsClient implements FunctionsClient {
  FirebaseFunctionsClient({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> params = const {}]) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(params);
      final data = normalizeCallableData(result.data);
      if (data is Map<String, dynamic>) return data;
      return {'result': data};
    } on FirebaseFunctionsException catch (e) {
      throw AppException.fromCallable(
        code: e.code,
        message: e.message,
        details: normalizeCallableData(e.details),
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException.fromCallable(code: 'unavailable');
    }
  }
}
