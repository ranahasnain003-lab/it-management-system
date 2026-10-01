import 'package:cloud_firestore/cloud_firestore.dart';

class BazaarModel {
  final String id;
  final String name;
  final String location;
  final String contactPerson;
  final String contactNumber;
  final String address;
  final String bazaarType;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastUpdated;

  const BazaarModel({
    required this.id,
    required this.name,
    this.location = '',
    this.contactPerson = '',
    this.contactNumber = '',
    this.address = '',
    this.bazaarType = '',
    this.isActive = true,
    this.createdAt,
    this.lastUpdated,
  });

  factory BazaarModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    // The field pairs below are read BOTH ways round on purpose. One legacy
    // production document carries `city`/`type` and has no `location`/
    // `bazaarType` at all, so reading only the newer name would show that
    // Bazaar without its city.
    return BazaarModel(
      id: documentId,
      name: _stringValue(data['name'] ?? data['bazaarName']),
      location: _stringValue(data['location'] ?? data['city']),
      contactPerson: _stringValue(data['contactPerson'] ?? data['contactName']),
      contactNumber: _stringValue(data['contactNumber'] ?? data['phone']),
      address: _stringValue(data['address']),
      bazaarType: _stringValue(data['bazaarType'] ?? data['type']),
      isActive: _boolValue(data['isActive'] ?? data['status'], fallback: true),
      createdAt: _dateValue(data['createdAt']),
      lastUpdated: _dateValue(data['lastUpdated'] ?? data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'contactPerson': contactPerson,
      'contactNumber': contactNumber,
      'address': address,
      'isActive': isActive,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'lastUpdated': lastUpdated != null
          ? Timestamp.fromDate(lastUpdated!)
          : null,
    };
  }

  static String _stringValue(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
  }

  static bool _boolValue(dynamic value, {required bool fallback}) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      if (normalized == 'true' || normalized == '1' || normalized == 'active') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == '0' ||
          normalized == 'inactive' ||
          normalized == 'disabled') {
        return false;
      }
    }

    if (value is num) {
      return value != 0;
    }

    return fallback;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}

class BazaarService {
  BazaarService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collection = 'bazaars';

  // ===========================================================================
  // ALL BAZAARS
  // ===========================================================================

  Stream<List<BazaarModel>> getBazaars() {
    return _firestore.collection(_collection).snapshots().map(_parseBazaars);
  }

  // ===========================================================================
  // ACTIVE BAZAARS
  // ===========================================================================

  Stream<List<BazaarModel>> getActiveBazaars() {
    return _firestore.collection(_collection).snapshots().map((snapshot) {
      return _parseBazaars(
        snapshot,
      ).where((bazaar) => bazaar.isActive).toList();
    });
  }

  // ===========================================================================
  // GET SINGLE BAZAAR
  // ===========================================================================

  Future<BazaarModel?> getBazaarById(String bazaarId) async {
    final id = bazaarId.trim();

    if (id.isEmpty) {
      return null;
    }

    final doc = await _firestore.collection(_collection).doc(id).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return BazaarModel.fromFirestore(doc.data()!, doc.id);
  }

  // ===========================================================================
  // CREATE BAZAAR
  // ===========================================================================

  /// Creates a Bazaar with a SINGLE write, because every active role may add
  /// a Bazaar but only a manager may update one: a create-then-update pair
  /// would fail halfway through for a User and leave a half-configured
  /// Bazaar behind.
  ///
  /// [isActive] is only ever set to false by a manager; the Add dialogs hide
  /// the toggle for everyone else, so a Bazaar added by a User is active and
  /// immediately usable as a transfer destination.
  ///
  /// [createdBy] carries a default so that adding the field did not break
  /// every existing caller at compile time; the value is still mandatory in
  /// practice, because the Firestore rule requires createdBy to equal the
  /// signed-in uid and both Add dialogs refuse to write before the profile
  /// is loaded.
  Future<String> createBazaar({
    required String name,
    String location = '',
    String contactPerson = '',
    String contactNumber = '',
    String address = '',
    String createdBy = '',
    String createdByName = '',
    bool isActive = true,
  }) async {
    final cleanName = name.trim();
    final cleanLocation = location.trim();

    if (cleanName.isEmpty) {
      throw Exception('Bazaar name is required.');
    }

    // The 65 Bazaars already in production have random document ids, so the
    // deterministic id below cannot detect a duplicate of any of them. Every
    // existing name is compared with the same normalised key instead.
    await _assertNameIsFree(cleanName, cleanLocation);

    final docRef = _firestore
        .collection(_collection)
        .doc(_newDocumentId(cleanName));

    try {
      await _firestore.runTransaction((transaction) async {
        // A plain set() would silently overwrite an existing Bazaar when the
        // writer is a manager, so the target document is read first and inside
        // the transaction, where the check cannot be raced.
        final existing = await transaction.get(docRef);

        if (existing.exists) {
          throw Exception('A Bazaar with this name already exists.');
        }

        transaction.set(docRef, {
          'name': cleanName,
          'bazaarName': cleanName,
          'location': cleanLocation,
          'city': cleanLocation,
          'contactPerson': contactPerson.trim(),
          'contactNumber': contactNumber.trim(),
          'address': address.trim(),
          'isActive': isActive,
          'status': isActive ? 'Active' : 'Disabled',
          'bazaarType': 'Sahulat Bazaar',
          'type': 'Sahulat Bazaar',
          'createdBy': createdBy.trim(),
          'createdByName': createdByName.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (error) {
      // A transaction needs a live connection, while the plain set() this
      // replaced was queued offline. The behaviour change is explained to the
      // user instead of surfacing as a generic failure.
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw Exception('You need a connection to add a Bazaar.');
      }

      rethrow;
    }

    return docRef.id;
  }

  // ===========================================================================
  // UPDATE BAZAAR
  // ===========================================================================

  Future<void> updateBazaar({
    required String bazaarId,
    required String name,
    String location = '',
    String contactPerson = '',
    String contactNumber = '',
    String address = '',
    bool isActive = true,
  }) async {
    final id = bazaarId.trim();
    final cleanName = name.trim();
    final cleanLocation = location.trim();

    if (id.isEmpty) {
      throw Exception('Bazaar ID is required.');
    }

    if (cleanName.isEmpty) {
      throw Exception('Bazaar name is required.');
    }

    final duplicate = await bazaarExists(
      cleanName,
      location: cleanLocation,
      excludeBazaarId: id,
    );

    if (duplicate) {
      throw Exception(
        'Another Bazaar with this name already exists in this location.',
      );
    }

    await _firestore.collection(_collection).doc(id).update({
      'name': cleanName,
      'bazaarName': cleanName,
      'location': cleanLocation,
      'city': cleanLocation,
      'contactPerson': contactPerson.trim(),
      'contactNumber': contactNumber.trim(),
      'address': address.trim(),
      'isActive': isActive,
      'status': isActive ? 'Active' : 'Disabled',
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===========================================================================
  // ACTIVATE / DEACTIVATE
  // ===========================================================================

  Future<void> updateBazaarStatus({
    required String bazaarId,
    required bool isActive,
  }) async {
    final id = bazaarId.trim();

    if (id.isEmpty) {
      throw Exception('Bazaar ID is required.');
    }

    await _firestore.collection(_collection).doc(id).update({
      'isActive': isActive,
      'status': isActive ? 'Active' : 'Disabled',
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===========================================================================
  // DELETE = DISABLE
  // ===========================================================================

  Future<void> deleteBazaar(String bazaarId) async {
    final id = bazaarId.trim();

    if (id.isEmpty) {
      throw Exception('Bazaar ID is required.');
    }

    await _firestore.collection(_collection).doc(id).update({
      'isActive': false,
      'status': 'Disabled',
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===========================================================================
  // SEARCH BAZAARS
  // ===========================================================================

  Future<List<BazaarModel>> searchBazaars(String query) async {
    final snapshot = await _firestore.collection(_collection).get();

    final bazaars = _parseBazaars(snapshot);

    final search = query.trim().toLowerCase();

    if (search.isEmpty) {
      return bazaars;
    }

    return bazaars.where((bazaar) {
      return bazaar.name.toLowerCase().contains(search) ||
          bazaar.location.toLowerCase().contains(search) ||
          bazaar.contactPerson.toLowerCase().contains(search) ||
          bazaar.contactNumber.toLowerCase().contains(search) ||
          bazaar.address.toLowerCase().contains(search);
    }).toList();
  }

  // ===========================================================================
  // CHECK BAZAAR EXISTS
  // ===========================================================================

  Future<bool> bazaarExists(
    String name, {
    String location = '',
    String? excludeBazaarId,
  }) async {
    // The same key as the create path on purpose: if an edit could rename a
    // Bazaar to "Township-Bazaar" while a create treats that as the existing
    // "Township Bazaar", the two paths would disagree about what a duplicate
    // is and leave a pair of documents create then refuses forever.
    final cleanName = bazaarNameKey(name);
    final cleanLocation = _normalize(location);

    if (cleanName.isEmpty) {
      return false;
    }

    final snapshot = await _firestore.collection(_collection).get();

    return snapshot.docs.any((doc) {
      if (excludeBazaarId != null && doc.id == excludeBazaarId) {
        return false;
      }

      final data = doc.data();

      final existingName = bazaarNameKey(
        BazaarModel._stringValue(data['name'] ?? data['bazaarName']),
      );

      final existingLocation = _normalize(data['location'] ?? data['city']);

      if (existingName != cleanName) {
        return false;
      }

      if (cleanLocation.isEmpty) {
        return true;
      }

      return existingLocation == cleanLocation;
    });
  }

  // ===========================================================================
  // DUPLICATE NAME GUARD
  // ===========================================================================

  /// Throws when any existing Bazaar carries the same normalised name key.
  ///
  /// The comparison ignores case, spacing and punctuation, so "Township
  /// Bazaar", "township  bazaar" and "Township-Bazaar" are one Bazaar. When
  /// the match sits in a different city that city is named, because two
  /// Bazaars with one name in two cities is the case users report as a bug.
  Future<void> _assertNameIsFree(String name, String location) async {
    final key = bazaarNameKey(name);

    if (key.isEmpty) {
      return;
    }

    final snapshot = await _firestore.collection(_collection).get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final existingName = BazaarModel._stringValue(
        data['name'] ?? data['bazaarName'],
      );

      if (bazaarNameKey(existingName) != key) {
        continue;
      }

      final existingLocation = BazaarModel._stringValue(
        data['location'] ?? data['city'],
      );

      if (existingLocation.isNotEmpty &&
          _normalize(existingLocation) != _normalize(location)) {
        throw Exception(
          'A Bazaar named "$existingName" already exists in $existingLocation.',
        );
      }

      throw Exception('A Bazaar with this name already exists.');
    }
  }

  // ===========================================================================
  // DETERMINISTIC DOCUMENT ID
  // ===========================================================================

  /// Comparison key for a Bazaar name: lower case, punctuation dropped and
  /// spaces collapsed to a single '_'.
  ///
  /// Punctuation becomes a separator rather than being deleted outright, so
  /// "Township-Bazaar" and "Township Bazaar" share one key. Deleting it would
  /// key them differently and let the same Bazaar be added twice.
  static String bazaarNameKey(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    return cleaned.replaceAll(' ', '_');
  }

  /// Document id for a NEW Bazaar. It is derived from the name so the same
  /// name can never be created twice, not even by two devices at once.
  ///
  /// Only new documents use it: the existing production Bazaars keep their
  /// random ids, which every movement record already points at.
  String _newDocumentId(String name) {
    final key = bazaarNameKey(name);

    // A name written entirely in a non-Latin script normalises to an empty
    // key; such a Bazaar gets a random id and relies on the name check above.
    if (key.isEmpty) {
      return _firestore.collection(_collection).doc().id;
    }

    // Firestore allows 1500 bytes per document id, but a readable id is
    // capped well below that.
    return 'bz_${key.length > 90 ? key.substring(0, 90) : key}';
  }

  // ===========================================================================
  // PARSE FIRESTORE SNAPSHOT
  // ===========================================================================

  List<BazaarModel> _parseBazaars(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final bazaars = <BazaarModel>[];

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();

        final bazaar = BazaarModel.fromFirestore(data, doc.id);

        if (bazaar.name.trim().isEmpty) {
          continue;
        }

        bazaars.add(bazaar);
      } catch (_) {
        // A single malformed document must not take the whole Bazaar list
        // down: it is skipped so every other Bazaar still reaches the UI.
        continue;
      }
    }
    bazaars.sort(_compareBazaars);
    return bazaars;
  }
  // ===========================================================================
  // SORT
  // ===========================================================================
  static int _compareBazaars(BazaarModel a, BazaarModel b) {
    final activeCompare = (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0);

    if (activeCompare != 0) {
      return activeCompare;
    }
    final locationCompare = a.location.trim().toLowerCase().compareTo(
      b.location.trim().toLowerCase(),
    );
    if (locationCompare != 0) {
      return locationCompare;
    }
  return a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
  }
  // ===========================================================================
  // NORMALIZE
  // ===========================================================================
  static String _normalize(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }
   }
   