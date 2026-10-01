import 'package:cloud_firestore/cloud_firestore.dart';

import 'guarded_transaction.dart';

/// One entry of the asset category catalogue.
///
/// The catalogue replaced the fixed list that used to live on the Add Asset
/// form. Anyone who may add an asset may also add the category it belongs to,
/// so the vocabulary grows with the inventory instead of needing a release.
class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.nameKey,
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt,
  });

  final String id;
  final String name;

  /// The normalised name. It is also the document id, which is what stops two
  /// accounts adding "Laptop" and "laptop " as two separate categories.
  final String nameKey;

  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;

  factory CategoryModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return CategoryModel(
      id: documentId,
      name: _stringValue(data['name']),
      // A document written before this field existed would have no nameKey;
      // the id always carries it, so it is the safer fallback.
      nameKey: _stringValue(data['nameKey']).isEmpty
          ? documentId
          : _stringValue(data['nameKey']),
      createdBy: _stringValue(data['createdBy']),
      createdByName: _stringValue(data['createdByName']),
      createdAt: _dateValue(data['createdAt']),
    );
  }

  static String _stringValue(dynamic value) {
    if (value == null) {
      return '';
    }

    return value.toString().trim();
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

class CategoryService {
  CategoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collection = 'categories';

  /// Longest name the Firestore rules accept, mirrored here so the dialog can
  /// refuse an over-long name before the write is attempted.
  static const int maxNameLength = 60;

  // ===========================================================================
  // NAME KEY
  // ===========================================================================

  /// The document id for [name].
  ///
  /// Lower-cased, whitespace collapsed, anything that is not a letter or a
  /// digit dropped and the remaining spaces joined with '_'. Two spellings of
  /// the same category therefore land on the same document, and the id is
  /// always a legal Firestore id.
  static String nameKeyFor(String name) {
    final collapsed = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    final stripped = collapsed.replaceAll(RegExp(r'[^a-z0-9 ]'), '');

    return stripped
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// The key two spellings are compared on: [nameKeyFor], or the lower-cased
  /// name when it has no usable key (a name made only of punctuation), so such
  /// a name is never collapsed with every other one.
  static String matchKeyFor(String name) {
    final key = nameKeyFor(name);

    return key.isEmpty ? name.trim().toLowerCase() : key;
  }

  // ===========================================================================
  // MERGED CATEGORY LIST
  // ===========================================================================

  /// Every category name the account may offer, in display spelling.
  ///
  /// The catalogue alone is not enough: assets registered before the
  /// catalogue existed carry categories of their own (production has a
  /// 'Laptop' asset), and hiding those would silently rewrite the data on the
  /// next edit. De-duplicated on [nameKeyFor] - the key that actually decides
  /// which document a name belongs to - keeping the first spelling seen so the
  /// catalogue wins over an asset's casing. De-duplicating on the lower-cased
  /// name instead would offer 'Wi-Fi' and 'WiFi' as two options that cannot
  /// both exist as documents.
  static List<String> mergeCategoryNames({
    Iterable<String> catalogue = const [],
    Iterable<String> assetCategories = const [],
  }) {
    final seen = <String, String>{};

    for (final name in [...catalogue, ...assetCategories]) {
      final clean = name.trim();

      if (clean.isEmpty) {
        continue;
      }

      seen.putIfAbsent(matchKeyFor(clean), () => clean);
    }

    final result = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return result;
  }

  /// [mergeCategoryNames] for a caller that holds the catalogue documents.
  ///
  /// Preferred wherever the models are available, because a catalogue entry
  /// is keyed by its STORED [CategoryModel.nameKey] rather than by its
  /// current spelling. That is what makes a rename tidy: 'Laptop' renamed to
  /// 'Laptops' keeps the key `laptop`, so an asset still recording 'Laptop'
  /// lands on the same entry and the list offers the corrected spelling
  /// once, instead of offering both and inviting the old one to be picked
  /// again. Assets keep working either way - their stored text is never
  /// rewritten - this only decides what the form offers.
  static List<String> mergeCategories({
    Iterable<CategoryModel> catalogue = const [],
    Iterable<String> assetCategories = const [],
  }) {
    final seen = <String, String>{};

    for (final category in catalogue) {
      final name = category.name.trim();

      if (name.isEmpty) {
        continue;
      }

      final key = category.nameKey.trim().isEmpty
          ? matchKeyFor(name)
          : category.nameKey.trim();

      seen.putIfAbsent(key, () => name);
    }

    for (final name in assetCategories) {
      final clean = name.trim();

      if (clean.isEmpty) {
        continue;
      }

      seen.putIfAbsent(matchKeyFor(clean), () => clean);
    }

    final result = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return result;
  }

  // ===========================================================================
  // READ
  // ===========================================================================

  /// The catalogue, ordered by name.
  ///
  /// Sorted in the app rather than by Firestore: an orderBy would drop any
  /// document that is missing the field, and the whole point of the catalogue
  /// is that no category quietly disappears.
  Stream<List<CategoryModel>> getCategories() {
    return _firestore.collection(_collection).snapshots().map(_parseCategories);
  }

  Future<List<CategoryModel>> loadCategories() async {
    final snapshot = await _firestore.collection(_collection).get();

    return _parseCategories(snapshot);
  }

  // ===========================================================================
  // CREATE
  // ===========================================================================

  /// Adds [name] to the catalogue and returns the stored category.
  ///
  /// Runs in a transaction because the duplicate check and the write have to
  /// be one step: two accounts adding the same category at the same moment
  /// would otherwise both pass a plain `get` and one would overwrite the
  /// other's name.
  Future<CategoryModel> create({
    required String name,
    required String createdBy,
    String createdByName = '',
  }) async {
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (cleanName.isEmpty) {
      throw Exception('Category name is required.');
    }

    if (cleanName.length > maxNameLength) {
      throw Exception(
        'A category name cannot be longer than $maxNameLength characters.',
      );
    }

    final nameKey = nameKeyFor(cleanName);

    if (nameKey.isEmpty) {
      throw Exception('Please use letters or digits in the category name.');
    }

    final cleanCreatedBy = createdBy.trim();

    if (cleanCreatedBy.isEmpty) {
      throw Exception('You are not authenticated. Please login again.');
    }

    final docRef = _firestore.collection(_collection).doc(nameKey);

    await runGuardedTransaction(_firestore, (transaction) async {
      final existing = await transaction.get(docRef);

      if (existing.exists) {
        throw Exception('That category already exists.');
      }

      // Exactly the fields the Firestore rules whitelist: anything else would
      // be rejected for every role.
      transaction.set(docRef, {
        'name': cleanName,
        'nameKey': nameKey,
        'createdBy': cleanCreatedBy,
        'createdByName': createdByName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return CategoryModel(
      id: nameKey,
      name: cleanName,
      nameKey: nameKey,
      createdBy: cleanCreatedBy,
      createdByName: createdByName.trim(),
    );
  }

  // ===========================================================================
  // RENAME
  // ===========================================================================

  /// Corrects the spelling of an existing category and returns it.
  ///
  /// Only the display name changes. [nameKey] - which is also the document id -
  /// is the category's identity and stays as it was, for two reasons: a
  /// document id cannot be changed in Firestore, and assets record the
  /// category they were given as text. Keeping the key means a renamed
  /// category and the old spelling still sitting on an asset collapse onto
  /// one entry in [mergeCategoryNames], with the corrected spelling winning,
  /// so existing assets keep working and the list does not grow a near
  /// duplicate.
  ///
  /// Duplicate protection is the same normalised-name logic as [create]: a
  /// rename is refused when ANOTHER category already occupies the new name's
  /// key. The check and the write are one transaction, so two accounts
  /// renaming towards the same name cannot both succeed.
  Future<CategoryModel> rename({
    required String categoryId,
    required String name,
  }) async {
    final id = categoryId.trim();

    if (id.isEmpty) {
      throw Exception('Category ID is required.');
    }

    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (cleanName.isEmpty) {
      throw Exception('Category name is required.');
    }

    if (cleanName.length > maxNameLength) {
      throw Exception(
        'A category name cannot be longer than $maxNameLength characters.',
      );
    }

    final newKey = nameKeyFor(cleanName);

    if (newKey.isEmpty) {
      throw Exception('Please use letters or digits in the category name.');
    }

    final docRef = _firestore.collection(_collection).doc(id);
    final takenRef = _firestore.collection(_collection).doc(newKey);

    var storedKey = id;

    await runGuardedTransaction(_firestore, (transaction) async {
      final existing = await transaction.get(docRef);

      if (!existing.exists || existing.data() == null) {
        throw Exception('That category no longer exists.');
      }

      final data = existing.data()!;
      storedKey = CategoryModel._stringValue(data['nameKey']).isEmpty
          ? id
          : CategoryModel._stringValue(data['nameKey']);

      // Renaming to a spelling that normalises to the same key - 'Laptop' to
      // 'laptops' - is the category's own key and never a clash.
      if (newKey != storedKey) {
        final taken = await transaction.get(takenRef);

        if (taken.exists) {
          final other = CategoryModel._stringValue(taken.data()?['name']);

          throw Exception(
            other.isEmpty
                ? 'A category with this name already exists.'
                : 'A category named "$other" already exists.',
          );
        }
      }

      if (CategoryModel._stringValue(data['name']) == cleanName) {
        // Nothing to change: writing anyway would only add noise to the
        // document and to the audit trail.
        return;
      }

      // The ONLY field a rename may touch. The Firestore rules enforce the
      // same thing, so no role can reach the key, the author or the date
      // through this path.
      transaction.update(docRef, {'name': cleanName});
    });

    return CategoryModel(id: id, name: cleanName, nameKey: storedKey);
  }

  // ===========================================================================
  // PARSE FIRESTORE SNAPSHOT
  // ===========================================================================

  List<CategoryModel> _parseCategories(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final categories = <CategoryModel>[];

    for (final doc in snapshot.docs) {
      try {
        final category = CategoryModel.fromFirestore(doc.data(), doc.id);

        if (category.name.isEmpty) {
          continue;
        }

        categories.add(category);
      } catch (_) {
        // A single malformed document must not take the whole catalogue down:
        // it is skipped so every other category still reaches the form.
        continue;
      }
    }

    categories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return categories;
  }
}
