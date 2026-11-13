import '../../domain/profile_draft.dart';
import '../../domain/step_models.dart';
import 'functions_client.dart';

/// Typed helpers for the callables used by the foundation (profile, device
/// registration, step sync). Feature engineers add their own typed wrappers
/// next to their feature code using [FunctionsClient.call].
class Callables {
  Callables(this._client);

  final FunctionsClient _client;

  Future<void> createProfile(ProfileDraft draft, {String? photoUrl}) async {
    await _client.call('createProfile', draft.toCallablePayload(photoUrl: photoUrl));
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    await _client.call('updateProfile', fields);
  }

  /// Returns `isRewardDevice`.
  Future<bool> registerDevice({
    required String deviceId,
    required String model,
    required String appVersion,
    String? fcmToken,
  }) async {
    final r = await _client.call('registerDevice', {
      'deviceId': deviceId,
      'model': model,
      'appVersion': appVersion,
      'fcmToken': ?fcmToken,
    });
    return r['isRewardDevice'] == true;
  }

  Future<SyncResponse> syncStepBuckets({
    required String deviceId,
    required List<EngineBucket> buckets,
  }) async {
    final r = await _client.call('syncStepBuckets', {
      'deviceId': deviceId,
      'buckets': [for (final b in buckets) b.toSyncJson()],
    });
    return SyncResponse.fromMap(r);
  }

  Future<void> markNotificationsRead([List<String>? ids]) async {
    await _client.call('markNotificationsRead', {'ids': ?ids});
  }
}
