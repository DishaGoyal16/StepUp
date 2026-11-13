/// Hostel grouping used by the registration dropdown.
enum HostelCategory {
  general('GENERAL'),
  girls('GIRLS');

  const HostelCategory(this.wire);
  final String wire;

  static HostelCategory fromWire(Object? value) =>
      value == 'GIRLS' ? HostelCategory.girls : HostelCategory.general;
}

/// A campus hostel (`hostels/{hostelId}`). Vasudha blocks are separate
/// hostels on purpose and are never merged.
class Hostel {
  const Hostel({
    required this.id,
    required this.displayName,
    required this.category,
    required this.sortOrder,
    this.legacyName,
    this.block,
    this.active = true,
  });

  factory Hostel.fromMap(String id, Map<String, dynamic> map) => Hostel(
        id: id,
        displayName: (map['displayName'] as String?) ?? id,
        legacyName: map['legacyName'] as String?,
        block: map['block'] as String?,
        category: HostelCategory.fromWire(map['category']),
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 9999,
        active: (map['active'] as bool?) ?? true,
      );

  final String id;
  final String displayName;
  final String? legacyName;
  final String? block;
  final HostelCategory category;
  final int sortOrder;
  final bool active;

  /// Label for pickers, e.g. `Agira Hall (Previously Hostel-A)`.
  String get label =>
      legacyName == null ? displayName : '$displayName (Previously $legacyName)';

  bool get isGirls => category == HostelCategory.girls;
}

/// A loaded hostel list and whether it came from the built-in seed (shown
/// only while the live directory is not reachable).
class HostelDirectory {
  const HostelDirectory({required this.hostels, required this.isFallback});

  final List<Hostel> hostels;
  final bool isFallback;

  List<Hostel> get general => _sorted(HostelCategory.general);
  List<Hostel> get girls => _sorted(HostelCategory.girls);

  List<Hostel> _sorted(HostelCategory c) {
    final list = hostels.where((h) => h.active && h.category == c).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Hostel? byId(String? id) {
    if (id == null) return null;
    for (final h in hostels) {
      if (h.id == id) return h;
    }
    return null;
  }
}
