import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BazaarModel {
  final String id;
  final String name;
  final String location;
  final String contactPerson;
  final String contactNumber;
  final String address;
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
    this.isActive = true,
    this.createdAt,
    this.lastUpdated,
  });

  factory BazaarModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return BazaarModel(
      id: documentId,
      name: _stringValue(data['name'] ?? data['bazaarName']),
      location: _stringValue(data['location'] ?? data['city']),
      contactPerson: _stringValue(data['contactPerson'] ?? data['contactName']),
      contactNumber: _stringValue(data['contactNumber'] ?? data['phone']),
      address: _stringValue(data['address']),
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
  // PUNJAB MASTER BAZAARS
  //
  // IMPORTANT:
  // These are the existing 64 bazaars already present in the project.
  // Do not remove or rename them.
  // ===========================================================================

  static const List<Map<String, String>> _punjabBazaarSeedData = [
    // -------------------------------------------------------------------------
    // LAHORE
    // -------------------------------------------------------------------------
    {
      'name': 'China Scheme Bazaar',
      'location': 'Lahore',
      'address': 'China Scheme, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Chung Bazaar',
      'location': 'Lahore',
      'address': 'Chung, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Harbanspura Bazaar',
      'location': 'Lahore',
      'address': 'Harbanspura, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Mian Plaza Johar Town Bazaar',
      'location': 'Lahore',
      'address': 'Johar Town, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Raiwind Bazaar',
      'location': 'Lahore',
      'address': 'Raiwind, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Sabzazar Bazaar',
      'location': 'Lahore',
      'address': 'Sabzazar, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Sher Shah Colony Bazaar',
      'location': 'Lahore',
      'address': 'Sher Shah Colony, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Thokar Niaz Baig Bazaar',
      'location': 'Lahore',
      'address': 'Thokar Niaz Baig, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Township Bazaar',
      'location': 'Lahore',
      'address': 'Township, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Wahdat Colony Bazaar',
      'location': 'Lahore',
      'address': 'Wahdat Colony, Lahore',
      'bazaarType': 'Sahulat Bazaar',
    },

    // -------------------------------------------------------------------------
    // OTHER PUNJAB MODEL / SAHULAT BAZAARS
    // -------------------------------------------------------------------------
    {
      'name': 'Bahawalpur Bazaar',
      'location': 'Bahawalpur',
      'address': 'Bahawalpur',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Chakwal Bazaar',
      'location': 'Chakwal',
      'address': 'Chakwal',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Bhera Bazaar',
      'location': 'Sargodha',
      'address': 'Bhera, Sargodha',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Sargodha Bazaar',
      'location': 'Sargodha',
      'address': 'Sargodha',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Faisalabad Jhang Road Bazaar',
      'location': 'Faisalabad',
      'address': 'Jhang Road, Faisalabad',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Faisalabad Millat Road Bazaar',
      'location': 'Faisalabad',
      'address': 'Millat Road, Faisalabad',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Gujrat Bazaar',
      'location': 'Gujrat',
      'address': 'Gujrat',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Gujranwala Bazaar',
      'location': 'Gujranwala',
      'address': 'Gujranwala',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Hafizabad Bazaar',
      'location': 'Hafizabad',
      'address': 'Hafizabad',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Jhang Bazaar',
      'location': 'Jhang',
      'address': 'Jhang',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Kasur Bazaar',
      'location': 'Kasur',
      'address': 'Kasur',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Jauharabad Bazaar',
      'location': 'Khushab',
      'address': 'Jauharabad, Khushab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Layyah Bazaar',
      'location': 'Layyah',
      'address': 'Layyah',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Chur Harpal Bazaar',
      'location': 'Rawalpindi',
      'address': 'Chur Harpal, Rawalpindi',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Lodhran Bazaar',
      'location': 'Lodhran',
      'address': 'Lodhran',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Jampur Bazaar',
      'location': 'Rajanpur',
      'address': 'Jampur, Rajanpur',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Toba Tek Singh Bazaar',
      'location': 'Toba Tek Singh',
      'address': 'Toba Tek Singh',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Sahiwal Bazaar',
      'location': 'Sahiwal',
      'address': 'Sahiwal',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'D.G. Khan Bazaar',
      'location': 'Dera Ghazi Khan',
      'address': 'Dera Ghazi Khan',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Farooqabad Bazaar',
      'location': 'Sheikhupura',
      'address': 'Farooqabad, Sheikhupura',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Sialkot Bazaar',
      'location': 'Sialkot',
      'address': 'Sialkot',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Vehari Bazaar',
      'location': 'Vehari',
      'address': 'Vehari',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Mianwali Bazaar',
      'location': 'Mianwali',
      'address': 'Mianwali',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Pakpattan Bazaar',
      'location': 'Pakpattan',
      'address': 'Pakpattan',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Bhakkar Bazaar',
      'location': 'Bhakkar',
      'address': 'Bhakkar',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Taunsa Shareef Bazaar',
      'location': 'Taunsa Shareef',
      'address': 'Taunsa Shareef',
      'bazaarType': 'Sahulat Bazaar',
    },

    // -------------------------------------------------------------------------
    // ADDITIONAL SAHULAT BAZAARS
    // -------------------------------------------------------------------------
    {
      'name': 'Chunian Bazaar',
      'location': 'Chunian',
      'address': 'Chunian, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Pattoki Bazaar',
      'location': 'Pattoki',
      'address': 'Pattoki, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Khanewal Bazaar',
      'location': 'Khanewal',
      'address': 'Khanewal, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Muzaffargarh Bazaar',
      'location': 'Muzaffargarh',
      'address': 'Muzaffargarh, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Wazirabad Bazaar',
      'location': 'Wazirabad',
      'address': 'Wazirabad, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Jaranwala Bazaar',
      'location': 'Jaranwala',
      'address': 'Jaranwala, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Chiniot Bazaar',
      'location': 'Chiniot',
      'address': 'Chiniot, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Bhalwal Bazaar',
      'location': 'Bhalwal',
      'address': 'Bhalwal, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },
    {
      'name': 'Okara Bazaar',
      'location': 'Okara',
      'address': 'Okara, Punjab',
      'bazaarType': 'Sahulat Bazaar',
    },

    // -------------------------------------------------------------------------
    // SAHULAT ON-THE-GO - LAHORE
    // -------------------------------------------------------------------------
    {
      'name': 'Sahulat on-the-Go - Multan Road',
      'location': 'Lahore',
      'address': 'Multan Road, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Hanjarwal',
      'location': 'Lahore',
      'address': 'Hanjarwal, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Manga Mandi',
      'location': 'Lahore',
      'address': 'Manga Mandi, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - G-1 Market',
      'location': 'Lahore',
      'address': 'G-1 Market, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Faisal Town',
      'location': 'Lahore',
      'address': 'Faisal Town, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Moon Market',
      'location': 'Lahore',
      'address': 'Moon Market, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Bedian Road',
      'location': 'Lahore',
      'address': 'Bedian Road, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - E-Millat Road',
      'location': 'Lahore',
      'address': 'E-Millat Road, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Gulshan Ravi',
      'location': 'Lahore',
      'address': 'Gulshan Ravi, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Shahdara',
      'location': 'Lahore',
      'address': 'Shahdara, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Shadman',
      'location': 'Lahore',
      'address': 'Shadman, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Singh Pura',
      'location': 'Lahore',
      'address': 'Singh Pura, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Madar-e-Millat Road',
      'location': 'Lahore',
      'address': 'Madar-e-Millat Road, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Madina Market',
      'location': 'Lahore',
      'address': 'Madina Market, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Sundar Road',
      'location': 'Lahore',
      'address': 'Sundar Road, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Kotha Pind',
      'location': 'Lahore',
      'address': 'Kotha Pind, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Kharak Nala',
      'location': 'Lahore',
      'address': 'Kharak Nala, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Awan Town',
      'location': 'Lahore',
      'address': 'Awan Town, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
    {
      'name': 'Sahulat on-the-Go - Valencia',
      'location': 'Lahore',
      'address': 'Valencia, Lahore',
      'bazaarType': 'Sahulat on-the-Go',
    },
  ];

  // ===========================================================================
  // ALL BAZAARS
  // ===========================================================================

  // Master data is restored once per Super Admin session (see App), never
  // from read streams: only a Super Admin may write Bazaars, so seeding from
  // a stream made the whole Bazaar list fail for Admins and Users.

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

  Future<String> createBazaar({
    required String name,
    String location = '',
    String contactPerson = '',
    String contactNumber = '',
    String address = '',
  }) async {
    final cleanName = name.trim();
    final cleanLocation = location.trim();

    if (cleanName.isEmpty) {
      throw Exception('Bazaar name is required.');
    }

    final alreadyExists = await bazaarExists(
      cleanName,
      location: cleanLocation,
    );

    if (alreadyExists) {
      throw Exception('A Bazaar with this name already exists.');
    }

    final docRef = _firestore.collection(_collection).doc();

    await docRef.set({
      'name': cleanName,
      'bazaarName': cleanName,
      'location': cleanLocation,
      'city': cleanLocation,
      'contactPerson': contactPerson.trim(),
      'contactNumber': contactNumber.trim(),
      'address': address.trim(),
      'isActive': true,
      'status': 'Active',
      'isMaster': false,
      'bazaarType': 'Sahulat Bazaar',
      'type': 'Sahulat Bazaar',
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

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
    final cleanName = _normalize(name);
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

      final existingName = _normalize(data['name'] ?? data['bazaarName']);

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

  /// Number of Punjab master Bazaars defined by the application.
  static int get masterBazaarCount => _punjabBazaarSeedData.length;

  /// Deterministic document ID for a master Bazaar. Two devices restoring
  /// the same missing master concurrently write the same document instead
  /// of creating duplicates, and a renamed master is still recognised.
  static String masterBazaarDocumentId(String name, String location) {
    final slug = _bazaarKey(name, location)
        .replaceAll(RegExp(r'[^a-z0-9|]+'), '-')
        .replaceAll('|', '__')
        .replaceAll(RegExp(r'-+'), '-');

    return 'master__$slug';
  }

  // ===========================================================================
  // SEED / RESTORE MASTER BAZAARS
  //
  // IMPORTANT:
  // This ONLY ADDS missing master bazaars.
  //
  // It NEVER deletes existing bazaars.
  // It NEVER disables existing bazaars.
  // It NEVER modifies the user's manually created bazaar.
  // ===========================================================================

  Future<int> seedPunjabBazaars() async {
    final collection = _firestore.collection(_collection);

    final snapshot = await collection.get();

    debugPrint(
      'BAZAAR DEBUG: Existing Firestore documents = '
      '${snapshot.docs.length}',
    );

    final existingExactKeys = <String>{};
    final existingNameKeys = <String>{};
    final existingDocIds = snapshot.docs.map((doc) => doc.id).toSet();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final existingName = _normalize(data['name'] ?? data['bazaarName']);

      final existingLocation = _normalize(data['location'] ?? data['city']);

      if (existingName.isEmpty) {
        continue;
      }

      existingExactKeys.add(_bazaarKey(existingName, existingLocation));

      existingNameKeys.add(existingName);
    }

    final missingBazaars = <Map<String, String>>[];

    for (final seed in _punjabBazaarSeedData) {
      final name = (seed['name'] ?? '').trim();
      final location = (seed['location'] ?? '').trim();

      if (name.isEmpty) {
        continue;
      }

      final normalizedName = _normalize(name);
      final normalizedLocation = _normalize(location);

      final exactKey = _bazaarKey(normalizedName, normalizedLocation);

      // Name-only matching is intentional.
      //
      // If the user already has the same Bazaar in Firestore,
      // do not create another copy just because its city/address
      // was entered differently.
      if (existingExactKeys.contains(exactKey) ||
          existingNameKeys.contains(normalizedName) ||
          existingDocIds.contains(masterBazaarDocumentId(name, location))) {
        continue;
      }

      missingBazaars.add(seed);

      existingExactKeys.add(exactKey);
      existingNameKeys.add(normalizedName);
    }

    debugPrint(
      'BAZAAR DEBUG: Master records in code = '
      '${_punjabBazaarSeedData.length}',
    );

    debugPrint(
      'BAZAAR DEBUG: Missing master bazaars = '
      '${missingBazaars.length}',
    );

    if (missingBazaars.isEmpty) {
      return 0;
    }

    final batch = _firestore.batch();

    for (final seed in missingBazaars) {
      final name = (seed['name'] ?? '').trim();
      final location = (seed['location'] ?? '').trim();
      final address = (seed['address'] ?? '').trim();
      final bazaarType = (seed['bazaarType'] ?? 'Sahulat Bazaar').trim();

      final docRef = collection.doc(masterBazaarDocumentId(name, location));

      batch.set(docRef, {
        'name': name,
        'bazaarName': name,
        'location': location,
        'city': location,
        'contactPerson': '',
        'contactNumber': '',
        'address': address,
        'isActive': true,
        'status': 'Active',
        'isMaster': true,
        'bazaarType': bazaarType,
        'type': bazaarType,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    debugPrint(
      'BAZAAR DEBUG: Successfully restored '
      '${missingBazaars.length} missing master bazaars.',
    );

    return missingBazaars.length;
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
          debugPrint(
            'BAZAAR DEBUG: Ignoring empty-name document: '
            '${doc.id}',
          );
          continue;
        }

        bazaars.add(bazaar);
      } catch (e) {
        debugPrint(
          'BAZAAR DEBUG: Failed to parse Bazaar '
          '${doc.id}: $e',
        );
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
  // ===========================================================================
  // BAZAAR KEY
  // ===========================================================================
  static String _bazaarKey(String name, String location) {
    return '${_normalize(name)}|${_normalize(location)}';
  }
   }  
   