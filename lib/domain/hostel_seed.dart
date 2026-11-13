import 'hostel.dart';

/// Built-in copy of the hostel directory (DATABASE_SCHEMA.md). The Firestore
/// `hostels` collection is authoritative and admin-editable; this seed is used
/// only to display choices while the live directory cannot be loaded.
/// Exactly 18 hostels; Vasudha blocks E and G stay separate.
const List<Hostel> hostelSeed = [
  Hostel(id: 'agira', displayName: 'Agira Hall', legacyName: 'Hostel-A', category: HostelCategory.general, sortOrder: 1),
  Hostel(id: 'amritam', displayName: 'Amritam Hall', legacyName: 'Hostel-B', category: HostelCategory.general, sortOrder: 2),
  Hostel(id: 'prithvi', displayName: 'Prithvi Hall', legacyName: 'Hostel-C', category: HostelCategory.general, sortOrder: 3),
  Hostel(id: 'neeram', displayName: 'Neeram Hall', legacyName: 'Hostel-D', category: HostelCategory.general, sortOrder: 4),
  Hostel(id: 'vyan', displayName: 'Vyan Hall', legacyName: 'Hostel-H', category: HostelCategory.general, sortOrder: 5),
  Hostel(id: 'tejas', displayName: 'Tejas Hall', legacyName: 'Hostel-J', category: HostelCategory.general, sortOrder: 6),
  Hostel(id: 'ambaram', displayName: 'Ambaram Hall', legacyName: 'Hostel-K', category: HostelCategory.general, sortOrder: 7),
  Hostel(id: 'viyat', displayName: 'Viyat Hall', legacyName: 'Hostel-L', category: HostelCategory.general, sortOrder: 8),
  Hostel(id: 'anantam', displayName: 'Anantam Hall', legacyName: 'Hostel-M', category: HostelCategory.general, sortOrder: 9),
  Hostel(id: 'vyom', displayName: 'Vyom Hall', legacyName: 'Hostel-O', category: HostelCategory.general, sortOrder: 10),
  Hostel(id: 'frf-g', displayName: 'Hostel-FRF/G', category: HostelCategory.general, sortOrder: 11),
  Hostel(id: 'vasudha-e', displayName: 'Vasudha Hall - Block E', legacyName: 'Hostel-E', block: 'E', category: HostelCategory.girls, sortOrder: 12),
  Hostel(id: 'vasudha-g', displayName: 'Vasudha Hall - Block G', legacyName: 'Hostel-G', block: 'G', category: HostelCategory.girls, sortOrder: 13),
  Hostel(id: 'ira', displayName: 'Ira Hall', legacyName: 'Hostel-I', category: HostelCategory.girls, sortOrder: 14),
  Hostel(id: 'ananta', displayName: 'Ananta Hall', legacyName: 'Hostel-N', category: HostelCategory.girls, sortOrder: 15),
  Hostel(id: 'dhriti', displayName: 'Dhriti Hall (Hostel-PG)', category: HostelCategory.girls, sortOrder: 16),
  Hostel(id: 'vahni', displayName: 'Vahni Hall', legacyName: 'Hostel-Q', category: HostelCategory.girls, sortOrder: 17),
  Hostel(id: 'pavani', displayName: 'Hostel-Pavani Hall', legacyName: 'PG-2', category: HostelCategory.girls, sortOrder: 18),
];
