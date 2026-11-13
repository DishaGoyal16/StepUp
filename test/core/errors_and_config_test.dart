import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/core/config/app_config.dart';
import 'package:stepup/core/errors/app_exception.dart';
import 'package:stepup/data/auth/auth_errors.dart';
import 'package:stepup/data/functions/fake_functions_client.dart';
import 'package:stepup/data/functions/functions_client.dart';
import 'package:stepup/domain/validators.dart';

void main() {
  group('AppException.fromCallable (callable error mapping)', () {
    test('uses details.reason and the server message for business errors', () {
      final e = AppException.fromCallable(
        code: 'failed-precondition',
        message: 'You are not buddies with this student.',
        details: {'reason': 'NOT_BUDDIES'},
      );
      expect(e.code, 'failed-precondition');
      expect(e.reason, 'NOT_BUDDIES');
      expect(e.message, 'You are not buddies with this student.');
    });

    test('invalid-argument keeps the server message', () {
      final e = AppException.fromCallable(code: 'invalid-argument', message: 'stakePoints must be 10..1000');
      expect(e.message, 'stakePoints must be 10..1000');
      expect(e.reason, isNull);
    });

    test('friendly text for codes without a trustworthy server message', () {
      expect(AppException.fromCallable(code: 'unauthenticated').message, contains('sign in'));
      expect(AppException.fromCallable(code: 'unavailable').message, contains('Network'));
      expect(AppException.fromCallable(code: 'deadline-exceeded').message, contains('Network'));
      expect(AppException.fromCallable(code: 'internal', message: 'INTERNAL').message, contains('Something went wrong'));
      expect(AppException.fromCallable(code: 'resource-exhausted').message, contains('Too many'));
      expect(AppException.fromCallable(code: 'permission-denied').message, contains('permission'));
      expect(AppException.fromCallable(code: 'not-found').message, contains('find'));
      expect(AppException.fromCallable(code: 'already-exists').message, contains('exists'));
    });

    test('raw code echoed as the message is not shown to users', () {
      final e = AppException.fromCallable(code: 'not-found', message: 'NOT_FOUND');
      expect(e.message, isNot('NOT_FOUND'));
    });

    test('non-map details are ignored', () {
      expect(AppException.fromCallable(code: 'internal', details: 'x').reason, isNull);
      expect(AppException.fromCallable(code: 'internal', details: {'reason': 5}).reason, isNull);
      expect(AppException.fromCallable(code: 'internal', details: {'reason': ''}).reason, isNull);
    });

    test('isRetryable', () {
      expect(AppException.fromCallable(code: 'unavailable').isRetryable, isTrue);
      expect(AppException.fromCallable(code: 'invalid-argument').isRetryable, isFalse);
    });

    test('toString includes code and reason', () {
      final e = AppException.fromCallable(code: 'failed-precondition', message: 'm', details: {'reason': 'R'});
      expect(e.toString(), contains('failed-precondition/R'));
    });
  });

  test('normalizeCallableData converts platform maps to Map<String, dynamic>', () {
    final out = normalizeCallableData(<Object?, Object?>{
      'a': <Object?, Object?>{'b': 1},
      'l': <Object?>[
        <Object?, Object?>{'x': 2},
      ],
    });
    expect(out, isA<Map<String, dynamic>>());
    expect(((out as Map)['a'] as Map)['b'], 1);
    expect((((out['l']) as List).first as Map<String, dynamic>)['x'], 2);
  });

  group('FakeFunctionsClient', () {
    test('records calls, runs handlers and queued failures', () async {
      final fn = FakeFunctionsClient()
        ..on('echo', (p) => {'got': p['v']})
        ..failNext('echo', AppException.fromCallable(code: 'unavailable'));
      await expectLater(fn.call('echo', {'v': 1}), throwsA(isA<AppException>()));
      expect((await fn.call('echo', {'v': 2}))['got'], 2);
      expect(fn.calls.length, 2);
      await expectLater(fn.call('missing'), throwsA(isA<AppException>()));
    });
  });

  group('mapAuthError (Firebase Auth messages)', () {
    test('duplicate account', () {
      expect(mapAuthError('email-already-in-use').message, contains('already exists'));
    });
    test('wrong password and unknown user look the same (no account probing)', () {
      expect(mapAuthError('wrong-password').message, 'Incorrect email or password.');
      expect(mapAuthError('user-not-found').message, 'Incorrect email or password.');
      expect(mapAuthError('invalid-credential').message, 'Incorrect email or password.');
    });
    test('weak password', () => expect(mapAuthError('weak-password').message, contains('too weak')));
    test('network', () => expect(mapAuthError('network-request-failed').message, contains('Network')));
    test('too many requests', () => expect(mapAuthError('too-many-requests').message, contains('Too many')));
    test('"auth/" prefix is stripped', () {
      final e = mapAuthError('auth/weak-password');
      expect(e.code, 'weak-password');
    });
    test('blocking function rejection of a non-thapar e-mail', () {
      final e = mapAuthError('internal-error', message: 'Only thapar.edu emails allowed');
      expect(e.message, contains('@thapar.edu'));
    });
    test('unknown code gets a generic message', () {
      expect(mapAuthError('totally-new').message, contains('Something went wrong'));
    });
  });

  group('Validators (form validators)', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('a@gmail.com'), 'Use your @thapar.edu email address');
      expect(Validators.email('a@thapar.edu.evil.com'), isNotNull);
      expect(Validators.email('a@thapar.edu'), isNull);
      expect(Validators.email(' A@THAPAR.EDU '), isNull);
    });
    test('password rules', () {
      expect(Validators.password(''), isNotNull);
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('allletters'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('Password1'), isNull);
    });
    test('login password only requires a value', () {
      expect(Validators.loginPassword(''), isNotNull);
      expect(Validators.loginPassword('x'), isNull);
    });
    test('confirm password', () {
      expect(Validators.confirmPassword('a', ''), isNotNull);
      expect(Validators.confirmPassword('a', 'b'), 'Passwords do not match');
      expect(Validators.confirmPassword('a', 'a'), isNull);
    });
    test('full name', () {
      expect(Validators.fullName(' '), isNotNull);
      expect(Validators.fullName('A'), isNotNull);
      expect(Validators.fullName('Ab'), isNull);
      expect(Validators.fullName('x' * 61), isNotNull);
    });
    test('bio length', () {
      expect(Validators.bio('x' * 160), isNull);
      expect(Validators.bio('x' * 161), isNotNull);
      expect(Validators.bio(null), isNull);
    });
    test('required', () {
      expect(Validators.required(null, 'm'), 'm');
      expect(Validators.required(' ', 'm'), 'm');
      expect(Validators.required(<int>[], 'm'), 'm');
      expect(Validators.required('x', 'm'), isNull);
    });
  });

  group('AppConfig', () {
    test('not configured without keys', () {
      expect(const AppConfig().isConfigured, isFalse);
      expect(AppConfig.resolve().isConfigured, isFalse);
    });

    test('configured only with apiKey, appId and projectId', () {
      expect(const AppConfig(apiKey: 'k', appId: 'a', projectId: 'p').isConfigured, isTrue);
      expect(const AppConfig(apiKey: 'k', appId: 'a').isConfigured, isFalse);
      expect(const AppConfig(apiKey: 'k', projectId: 'p').isConfigured, isFalse);
      expect(const AppConfig(appId: 'a', projectId: 'p').isConfigured, isFalse);
    });

    test('emulator mode fills missing keys with demo-stepup defaults', () {
      final c = AppConfig.resolve(useEmulator: true);
      expect(c.isConfigured, isTrue);
      expect(c.projectId, 'demo-stepup');
      expect(c.apiKey, isNotEmpty);
      expect(c.emulatorHost, '10.0.2.2');
      expect(c.storageBucket, 'demo-stepup.appspot.com');
    });

    test('emulator mode keeps explicitly supplied values', () {
      final c = AppConfig.resolve(useEmulator: true, projectId: 'my-proj', emulatorHost: '127.0.0.1');
      expect(c.projectId, 'my-proj');
      expect(c.emulatorHost, '127.0.0.1');
    });

    test('no emulator: missing keys are NOT defaulted', () {
      final c = AppConfig.resolve(apiKey: 'k');
      expect(c.isConfigured, isFalse);
      expect(c.projectId, isEmpty);
    });

    test('constants', () {
      expect(AppConfig.functionsRegion, 'asia-south1');
      expect(AppConfig.authEmulatorPort, 9099);
      expect(AppConfig.firestoreEmulatorPort, 8080);
      expect(AppConfig.functionsEmulatorPort, 5001);
      expect(AppConfig.storageEmulatorPort, 9199);
    });

    test('emulator default API key has the format Firebase Installations accepts on Android', () {
      // Found on a real phone: with the old 'demo-api-key' every callable failed with
      // "IllegalArgumentException: Please set a valid API key". Format: 'A' + 38 x [A-Za-z0-9_-].
      final c = AppConfig.resolve(useEmulator: true);
      expect(c.apiKey, AppConfig.demoApiKey);
      expect(RegExp(r'^A[\w-]{38}$').hasMatch(c.apiKey), isTrue, reason: c.apiKey);
      expect(RegExp(r'^\d:\d+:android:[0-9a-fA-F]+$').hasMatch(c.appId), isTrue, reason: c.appId);
    });

    test('Google sign-in is off by default', () {
      expect(const AppConfig().googleSignInEnabled, isFalse);
      expect(AppConfig.fromEnvironment().googleSignInEnabled, isFalse);
    });
  });
}
