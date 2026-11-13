import 'package:flutter_test/flutter_test.dart';
import 'package:stepup/data/firestore/fake_firestore_access.dart';
import 'package:stepup/data/firestore/hostel_repository.dart';
import 'package:stepup/domain/hostel.dart';
import 'package:stepup/domain/hostel_seed.dart';

void main() {
  // (id, displayName, legacyName, block, category) exactly as in DATABASE_SCHEMA.md
  const expected = <(String, String, String?, String?, HostelCategory)>[
    ('agira', 'Agira Hall', 'Hostel-A', null, HostelCategory.general),
    ('amritam', 'Amritam Hall', 'Hostel-B', null, HostelCategory.general),
    ('prithvi', 'Prithvi Hall', 'Hostel-C', null, HostelCategory.general),
    ('neeram', 'Neeram Hall', 'Hostel-D', null, HostelCategory.general),
    ('vyan', 'Vyan Hall', 'Hostel-H', null, HostelCategory.general),
    ('tejas', 'Tejas Hall', 'Hostel-J', null, HostelCategory.general),
    ('ambaram', 'Ambaram Hall', 'Hostel-K', null, HostelCategory.general),
    ('viyat', 'Viyat Hall', 'Hostel-L', null, HostelCategory.general),
    ('anantam', 'Anantam Hall', 'Hostel-M', null, HostelCategory.general),
    ('vyom', 'Vyom Hall', 'Hostel-O', null, HostelCategory.general),
    ('frf-g', 'Hostel-FRF/G', null, null, HostelCategory.general),
    ('vasudha-e', 'Vasudha Hall - Block E', 'Hostel-E', 'E', HostelCategory.girls),
    ('vasudha-g', 'Vasudha Hall - Block G', 'Hostel-G', 'G', HostelCategory.girls),
    ('ira', 'Ira Hall', 'Hostel-I', null, HostelCategory.girls),
    ('ananta', 'Ananta Hall', 'Hostel-N', null, HostelCategory.girls),
    ('dhriti', 'Dhriti Hall (Hostel-PG)', null, null, HostelCategory.girls),
    ('vahni', 'Vahni Hall', 'Hostel-Q', null, HostelCategory.girls),
    ('pavani', 'Hostel-Pavani Hall', 'PG-2', null, HostelCategory.girls),
  ];

  group('hostel seed', () {
    test('has exactly 18 hostels', () => expect(hostelSeed.length, 18));

    test('matches the schema table row by row', () {
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final h = hostelSeed[i];
        expect(h.id, e.$1, reason: 'id #$i');
        expect(h.displayName, e.$2, reason: e.$1);
        expect(h.legacyName, e.$3, reason: e.$1);
        expect(h.block, e.$4, reason: e.$1);
        expect(h.category, e.$5, reason: e.$1);
        expect(h.sortOrder, i + 1, reason: e.$1);
      }
    });

    test('ids and display names are unique', () {
      expect(hostelSeed.map((h) => h.id).toSet().length, 18);
      expect(hostelSeed.map((h) => h.displayName).toSet().length, 18);
    });

    test('11 general and 7 girls hostels', () {
      expect(hostelSeed.where((h) => h.category == HostelCategory.general).length, 11);
      expect(hostelSeed.where((h) => h.category == HostelCategory.girls).length, 7);
    });

    test('Vasudha blocks are separate hostels, never merged', () {
      final v = hostelSeed.where((h) => h.id.startsWith('vasudha')).toList();
      expect(v.length, 2);
      expect(v.map((h) => h.block).toSet(), {'E', 'G'});
      expect(hostelSeed.any((h) => h.id == 'vasudha'), isFalse);
    });

    test('label shows (Previously ...) only when a legacy name exists', () {
      final agira = hostelSeed.firstWhere((h) => h.id == 'agira');
      final frf = hostelSeed.firstWhere((h) => h.id == 'frf-g');
      expect(agira.label, 'Agira Hall (Previously Hostel-A)');
      expect(frf.label, 'Hostel-FRF/G');
    });

    test('all seed hostels active', () => expect(hostelSeed.every((h) => h.active), isTrue));
  });

  group('HostelDirectory', () {
    const dir = HostelDirectory(hostels: hostelSeed, isFallback: true);

    test('groups into "Hostels" and "Girls\' hostels" sorted by sortOrder', () {
      expect(dir.general.map((h) => h.id).first, 'agira');
      expect(dir.general.length, 11);
      expect(dir.girls.length, 7);
      expect(dir.girls.first.id, 'vasudha-e');
      expect(dir.girls.last.id, 'pavani');
    });

    test('inactive hostels are hidden', () {
      final d = HostelDirectory(
        hostels: [
          const Hostel(id: 'a', displayName: 'A', category: HostelCategory.general, sortOrder: 1),
          const Hostel(id: 'b', displayName: 'B', category: HostelCategory.general, sortOrder: 2, active: false),
        ],
        isFallback: false,
      );
      expect(d.general.map((h) => h.id), ['a']);
    });

    test('byId', () {
      expect(dir.byId('ira')?.displayName, 'Ira Hall');
      expect(dir.byId('nope'), isNull);
      expect(dir.byId(null), isNull);
    });
  });

  group('HostelRepository', () {
    test('uses live Firestore hostels when available', () async {
      final fs = FakeFirestoreAccess(hostels: const [
        Hostel(id: 'x', displayName: 'X Hall', category: HostelCategory.general, sortOrder: 1),
      ]);
      final dir = await HostelRepository(fs).load();
      expect(dir.isFallback, isFalse);
      expect(dir.hostels.single.id, 'x');
    });

    test('falls back to the seed when offline', () async {
      final fs = FakeFirestoreAccess()..hostelsOffline = true;
      final dir = await HostelRepository(fs).load();
      expect(dir.isFallback, isTrue);
      expect(dir.hostels.length, 18);
    });

    test('falls back to the seed when the live list is empty', () async {
      final fs = FakeFirestoreAccess(hostels: const []);
      final dir = await HostelRepository(fs).load();
      expect(dir.isFallback, isTrue);
    });
  });

  test('Hostel.fromMap maps the Firestore document', () {
    final h = Hostel.fromMap('vasudha-e', {
      'displayName': 'Vasudha Hall - Block E',
      'legacyName': 'Hostel-E',
      'block': 'E',
      'category': 'GIRLS',
      'active': true,
      'sortOrder': 12,
    });
    expect(h.isGirls, isTrue);
    expect(h.block, 'E');
    expect(h.sortOrder, 12);
  });
}
