import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../core/errors/app_exception.dart';
import 'challenge_models.dart';

/// Read-only access to the challenge documents the client may read
/// (see `firestore.rules`):
///
/// * `challenges` - everything except BUDDY challenges, which are readable
///   only by their two participants (so they are fetched by id, after finding
///   them through my own `challengeParticipants` documents);
/// * `challengeParticipants` - only my own documents (`uid == me`);
/// * `challengeResults` - same visibility as the challenge.
///
/// All failures surface as [AppException].
abstract class ChallengeReader {
  /// UPCOMING / ACTIVE challenges of a non-buddy [type]. For INDIVIDUAL this is the catalogue templates
  /// (`isTemplate == true`) plus any individual challenge an admin created (`isTemplate == false`).
  Future<List<Challenge>> fetchOpenChallenges(ChallengeType type);

  /// One-shot read of all my participation documents.
  Future<List<ChallengeParticipation>> fetchMyParticipations(String uid);

  /// Live list of all my participation documents.
  Stream<List<ChallengeParticipation>> watchMyParticipations(String uid);

  /// Live `challengeParticipants/{challengeId}_{uid}`; `null` when absent.
  Stream<ChallengeParticipation?> watchParticipation(String challengeId, String uid);

  /// `null` when the challenge does not exist (or is not visible to me).
  Future<Challenge?> fetchChallenge(String id);

  /// Fetches many challenges by id; missing / unreadable ones are skipped.
  Future<List<Challenge>> fetchChallenges(Iterable<String> ids);

  /// `challengeResults/{id}`; `null` until the server finalized the challenge.
  Future<ChallengeResult?> fetchResult(String challengeId);
}

/// Maps any read failure to the app's single error type.
AppException mapReadError(Object error) {
  if (error is AppException) return error;
  if (error is FirebaseException) {
    return AppException.fromCallable(code: error.code, message: error.message);
  }
  if (error is TimeoutException) return AppException.fromCallable(code: 'deadline-exceeded');
  return AppException.fromCallable(code: 'unavailable');
}

/// Stream transformer converting every error into an [AppException].
StreamTransformer<T, T> mapStreamErrors<T>() => StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stack, sink) => sink.addError(mapReadError(error), stack),
    );
