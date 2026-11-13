// Helpers that talk to the Firebase Emulator Suite over plain REST, from the
// phone (ports are forwarded with `adb reverse`, so 127.0.0.1 is the PC).
//
// This is TEST-ONLY code. It reads server state with the emulator's
// "owner" bearer token (bypasses rules) to *assert* what the real app did.
// It never writes points, steps or results. The only writes are `setControl`
// (a handshake document for the PC-side adb watcher) and `promoteRewardDevice`
// (reward-device bookkeeping, see its comment).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String kProject = 'demo-stepup';
const String kHost = '127.0.0.1';
const String kPassword = 'Passw0rd123';

class Emu {
  static final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static Future<(int, String)> _raw(
    String method,
    Uri url, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final req = await _http.openUrl(method, url);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  }

  static const Map<String, String> _owner = {'Authorization': 'Bearer owner'};

  // ---------------------------------------------------------------- Auth
  static Uri _auth(String path) => Uri.parse('http://$kHost:9099$path');

  static Future<List<Map<String, dynamic>>> oobCodes() async {
    final (code, text) = await _raw('GET', _auth('/emulator/v1/projects/$kProject/oobCodes'));
    if (code != 200) throw StateError('oobCodes -> $code $text');
    return ((jsonDecode(text) as Map)['oobCodes'] as List).cast<Map<String, dynamic>>();
  }

  /// Opens the newest VERIFY_EMAIL link of [email] (what a student does in the inbox).
  static Future<void> verifyEmail(String email) async {
    // The app moves to "Check your inbox" as soon as the account exists, a moment BEFORE the verification mail is
    // requested, so wait for the code to appear.
    final mine = await waitFor<List<Map<String, dynamic>>>(() async {
      final codes = await oobCodes();
      final l = codes
          .where((c) => c['requestType'] == 'VERIFY_EMAIL' && (c['email'] as String).toLowerCase() == email.toLowerCase())
          .toList();
      return l.isEmpty ? null : l;
    }, timeout: const Duration(seconds: 20), what: 'VERIFY_EMAIL oobCode for $email');
    final link = mine.last['oobLink'] as String;
    // The emulator generates the link with its own host; re-target to our forwarded port.
    final u = Uri.parse(link);
    final url = u.replace(scheme: 'http', host: kHost, port: 9099);
    final (code, text) = await _raw('GET', url);
    if (code >= 400) throw StateError('verify link -> $code $text');
  }

  static Future<List<Map<String, dynamic>>> authUsers() async {
    final (code, text) = await _raw(
      'GET',
      _auth('/identitytoolkit.googleapis.com/v1/projects/$kProject/accounts:batchGet?maxResults=200'),
      headers: _owner,
    );
    if (code != 200) throw StateError('batchGet -> $code $text');
    final users = (jsonDecode(text) as Map)['users'];
    return users == null ? [] : (users as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>?> authUserByEmail(String email) async {
    for (final u in await authUsers()) {
      if ((u['email'] as String?)?.toLowerCase() == email.toLowerCase()) return u;
    }
    return null;
  }

  // ----------------------------------------------------------- Firestore
  static Uri _fs(String path) => Uri.parse('http://$kHost:8080/v1/projects/$kProject/databases/(default)/documents$path');

  static dynamic decodeValue(Map<String, dynamic> v) {
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue')) return int.parse(v['integerValue'] as String);
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    if (v.containsKey('timestampValue')) return v['timestampValue'];
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('arrayValue')) {
      final vals = (v['arrayValue'] as Map)['values'] as List?;
      return [for (final e in vals ?? const []) decodeValue((e as Map).cast<String, dynamic>())];
    }
    if (v.containsKey('mapValue')) {
      return decodeFields((((v['mapValue'] as Map)['fields']) as Map?)?.cast<String, dynamic>() ?? {});
    }
    return v;
  }

  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) =>
      {for (final e in fields.entries) e.key: decodeValue((e.value as Map).cast<String, dynamic>())};

  static Map<String, dynamic> _decodeDoc(Map<String, dynamic> d) {
    final name = d['name'] as String;
    return {
      '_id': name.substring(name.lastIndexOf('/') + 1),
      ...decodeFields((d['fields'] as Map?)?.cast<String, dynamic>() ?? {}),
    };
  }

  /// Document at [path] (e.g. `users/abc`) or null when missing.
  static Future<Map<String, dynamic>?> doc(String path) async {
    final (code, text) = await _raw('GET', _fs('/$path'), headers: _owner);
    if (code == 404) return null;
    if (code != 200) throw StateError('GET $path -> $code $text');
    return _decodeDoc(jsonDecode(text) as Map<String, dynamic>);
  }

  /// All documents directly in collection [path] (no ordering guarantee).
  static Future<List<Map<String, dynamic>>> list(String path) async {
    final out = <Map<String, dynamic>>[];
    String? token;
    do {
      final q = token == null ? '?pageSize=300' : '?pageSize=300&pageToken=$token';
      final (code, text) = await _raw('GET', Uri.parse('${_fs('/$path')}$q'), headers: _owner);
      if (code != 200) throw StateError('list $path -> $code $text');
      final j = jsonDecode(text) as Map<String, dynamic>;
      for (final d in (j['documents'] as List?) ?? const []) {
        out.add(_decodeDoc((d as Map).cast<String, dynamic>()));
      }
      token = j['nextPageToken'] as String?;
    } while (token != null);
    return out;
  }

  /// `collectionId where field == value` (top-level collections).
  static Future<List<Map<String, dynamic>>> where(String collection, String field, String equals) async {
    final (code, text) = await _raw(
      'POST',
      Uri.parse('${_fs('')}:runQuery'),
      headers: _owner,
      body: {
        'structuredQuery': {
          'from': [
            {'collectionId': collection}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': {'stringValue': equals},
            }
          },
        }
      },
    );
    if (code != 200) throw StateError('runQuery $collection -> $code $text');
    return [
      for (final r in jsonDecode(text) as List)
        if ((r as Map)['document'] != null) _decodeDoc((r['document'] as Map).cast<String, dynamic>()),
    ];
  }

  /// Polls [probe] until it returns non-null (or throws on timeout).
  static Future<T> waitFor<T>(
    Future<T?> Function() probe, {
    Duration timeout = const Duration(seconds: 40),
    String what = 'condition',
  }) async {
    final end = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(end)) {
      try {
        final v = await probe();
        if (v != null) return v;
      } catch (e) {
        lastError = e;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException('timed out waiting for $what${lastError == null ? '' : ' (last error: $lastError)'}');
  }

  // ------------------------------------------- reward-device bookkeeping only
  /// Makes [deviceId] the account's reward device (emulator "owner" write that bypasses the callables).
  ///
  /// WHY: `flutter test` uninstalls the app after every run, so each test file starts with a NEW device id, and the
  /// server (correctly) keeps the account's first device as its single reward device for `rewardDeviceTakeoverDays`
  /// (14). This simulates that takeover so later files can submit reward-eligible buckets. It writes account device
  /// bookkeeping only - never points, steps, buckets or results.
  static Future<void> promoteRewardDevice(String uid, String deviceId) async {
    Future<void> patch(String path, String field, Map<String, Object?> value) async {
      final url = Uri.parse('${_fs('/$path')}?updateMask.fieldPaths=$field');
      final (code, text) = await _raw('PATCH', url, headers: _owner, body: {'fields': {field: value}});
      if (code != 200) throw StateError('promoteRewardDevice PATCH $path -> $code $text');
    }

    final previous = (await doc('users/$uid'))?['rewardDeviceId'] as String?;
    if (previous != null && previous != deviceId) {
      await patch('users/$uid/devices/$previous', 'isRewardDevice', {'booleanValue': false});
    }
    await patch('users/$uid', 'rewardDeviceId', {'stringValue': deviceId});
    await patch('users/$uid/devices/$deviceId', 'isRewardDevice', {'booleanValue': true});
  }

  // --------------------------------------------- PC-side adb handshake only
  /// Writes `testControl/{id}` (handshake with `adb-watcher.ps1`; not app data).
  static Future<void> setControl(String id, Map<String, String> fields) async {
    final (code, text) = await _raw(
      'PATCH',
      _fs('/testControl/$id'),
      headers: _owner,
      body: {
        'fields': {for (final e in fields.entries) e.key: {'stringValue': e.value}},
      },
    );
    if (code != 200) throw StateError('setControl -> $code $text');
  }

  static Future<Map<String, dynamic>?> control(String id) => doc('testControl/$id');
}
