import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/category_service.dart';
import 'package:it_management_system/models/asset_model.dart';

void main() {
  late FakeFirebaseFirestore db;
  late CategoryService categories;

  setUp(() {
    db = FakeFirebaseFirestore();
    categories = CategoryService(firestore: db);
  });

  Future<Map<String, dynamic>?> categoryData(String id) async {
    return (await db.collection('categories').doc(id).get()).data();
  }

  // ===========================================================================
  // NAME KEY
  // ===========================================================================

  group('nameKeyFor', () {
    test('lower-cases, collapses whitespace and joins words with _', () {
      expect(CategoryService.nameKeyFor('Laptop'), 'laptop');
      expect(CategoryService.nameKeyFor('  Laptop  '), 'laptop');
      expect(CategoryService.nameKeyFor('Network   Device'), 'network_device');
      expect(CategoryService.nameKeyFor('NETWORK device'), 'network_device');
    });

    test('drops characters that are neither letters nor digits', () {
      expect(CategoryService.nameKeyFor('Wi-Fi'), 'wifi');
      expect(CategoryService.nameKeyFor('UPS (backup)'), 'ups_backup');
      expect(
        CategoryService.nameKeyFor('Printer / Scanner'),
        'printer_scanner',
      );
      expect(CategoryService.nameKeyFor('Type 2'), 'type_2');
    });

    test('is empty when nothing usable is left, so no document is written', () {
      expect(CategoryService.nameKeyFor('   '), '');
      expect(CategoryService.nameKeyFor('-- //'), '');
    });
  });

  // ===========================================================================
  // CREATE
  // ===========================================================================

  group('create', () {
    test('writes exactly the fields the Firestore rules whitelist', () async {
      final created = await categories.create(
        name: '  Network   Device  ',
        createdBy: 'uid-1',
        createdByName: 'Ali',
      );

      expect(created.id, 'network_device');
      expect(created.nameKey, 'network_device');

      // The display name keeps its casing, with the extra spaces collapsed.
      expect(created.name, 'Network Device');

      final data = await categoryData('network_device');

      expect(data, isNotNull);
      expect(data!.keys.toSet(), {
        'name',
        'nameKey',
        'createdBy',
        'createdByName',
        'createdAt',
      });
      expect(data['name'], 'Network Device');
      expect(data['nameKey'], 'network_device');
      expect(data['createdBy'], 'uid-1');
      expect(data['createdByName'], 'Ali');
    });

    test('refuses a duplicate that differs only in case or spacing', () async {
      await categories.create(name: 'Laptop', createdBy: 'uid-1');

      for (final duplicate in ['laptop', 'LAPTOP', '  Laptop ', 'Lap top']) {
        // 'Lap top' is a different category on purpose - only the first three
        // normalise to the same key.
        if (CategoryService.nameKeyFor(duplicate) != 'laptop') {
          continue;
        }

        await expectLater(
          categories.create(name: duplicate, createdBy: 'uid-2'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('That category already exists.'),
            ),
          ),
        );
      }

      // The original is untouched: a refused duplicate must not overwrite it.
      final data = await categoryData('laptop');

      expect(data!['name'], 'Laptop');
      expect(data['createdBy'], 'uid-1');

      final snapshot = await db.collection('categories').get();

      expect(snapshot.docs.length, 1);
    });

    test('refuses a name with nothing usable in it', () async {
      await expectLater(
        categories.create(name: '  ', createdBy: 'uid-1'),
        throwsA(isA<Exception>()),
      );

      await expectLater(
        categories.create(name: '///', createdBy: 'uid-1'),
        throwsA(isA<Exception>()),
      );

      expect((await db.collection('categories').get()).docs, isEmpty);
    });

    test('refuses a name longer than the rules allow', () async {
      await expectLater(
        categories.create(
          name: 'a' * (CategoryService.maxNameLength + 1),
          createdBy: 'uid-1',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('refuses an empty createdBy', () async {
      await expectLater(
        categories.create(name: 'Laptop', createdBy: '  '),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ===========================================================================
  // READ
  // ===========================================================================

  group('read', () {
    test('returns the catalogue ordered by name', () async {
      await categories.create(name: 'Printer', createdBy: 'uid-1');
      await categories.create(name: 'camera', createdBy: 'uid-1');
      await categories.create(name: 'Laptop', createdBy: 'uid-1');

      expect((await categories.loadCategories()).map((c) => c.name).toList(), [
        'camera',
        'Laptop',
        'Printer',
      ]);

      expect(
        (await categories.getCategories().first).map((c) => c.name).toList(),
        ['camera', 'Laptop', 'Printer'],
      );
    });

    test('skips a document with no name instead of failing the list', () async {
      await categories.create(name: 'Laptop', createdBy: 'uid-1');

      await db.collection('categories').doc('broken').set({
        'nameKey': 'broken',
      });

      expect((await categories.loadCategories()).map((c) => c.name).toList(), [
        'Laptop',
      ]);
    });
  });

  // ===========================================================================
  // MERGED LIST
  // ===========================================================================

  group('mergeCategoryNames', () {
    test('includes a category that exists only on an asset', () {
      // The production inventory has a 'Laptop' asset and no catalogue entry
      // for it; losing that option would rewrite the asset on the next edit.
      expect(
        CategoryService.mergeCategoryNames(
          catalogue: const ['Printer'],
          assetCategories: const ['Laptop'],
        ),
        ['Laptop', 'Printer'],
      );

      expect(
        CategoryService.mergeCategoryNames(assetCategories: const ['Laptop']),
        ['Laptop'],
      );
    });

    test(
      'de-duplicates case-insensitively, keeping the catalogue spelling',
      () {
        expect(
          CategoryService.mergeCategoryNames(
            catalogue: const ['Laptop'],
            assetCategories: const ['laptop', 'LAPTOP', ' Laptop '],
          ),
          ['Laptop'],
        );
      },
    );

    test('de-duplicates on the key that decides the document id', () {
      // 'Wi-Fi' and 'WiFi' are the same document, so offering both would give
      // two options that cannot both exist.
      expect(
        CategoryService.mergeCategoryNames(
          catalogue: const ['Wi-Fi'],
          // 'wi fi' is deliberately not here: dropping the hyphen leaves
          // 'wifi', not 'wi_fi', so that spelling is a different document.
          assetCategories: const ['WiFi', ' wifi '],
        ),
        ['Wi-Fi'],
      );

      expect(
        CategoryService.mergeCategoryNames(
          catalogue: const ['Network Device'],
          assetCategories: const ['Network   Device'],
        ),
        ['Network Device'],
      );
    });

    test('drops blank names and sorts case-insensitively', () {
      expect(
        CategoryService.mergeCategoryNames(
          catalogue: const ['printer', '', '   '],
          assetCategories: const ['Camera', 'ups'],
        ),
        ['Camera', 'printer', 'ups'],
      );
    });

    test('is empty when there is nothing to offer', () {
      expect(CategoryService.mergeCategoryNames(), isEmpty);
    });
  });

  // ===========================================================================
  // NEW ASSET AUTHOR
  //
  // The Add Asset screen is what lets a User register an asset, and the create
  // rule accepts that write only when createdBy is the signed-in UID while
  // adminId is the User's own Admin. Asserted on the stored document because a
  // missing createdBy is refused by Firestore, not by anything the app checks.
  // ===========================================================================

  group('new asset author', () {
    test('a User add carries createdBy and the owning Admin', () async {
      final assets = AssetService(firestore: db);

      // Exactly what add_asset_screen.dart builds for a User: the author is
      // the signed-in account, the owner is the Admin that created it.
      const asset = AssetModel(
        id: '',
        assetId: 'AST-0001',
        name: 'Dell Latitude',
        category: 'Laptop',
        status: 'Available',
        quantity: 2,
        adminId: 'admin-uid',
        adminName: 'Admin One',
        createdBy: 'user-uid',
      );

      final documentId = await assets.addAsset(asset);

      final data = (await db.collection('assets').doc(documentId).get()).data();

      expect(data?['createdBy'], 'user-uid');
      expect(data?['adminId'], 'admin-uid');
    });

    test('createdBy is not one of the fields an edit may change', () {
      expect(AssetService.editableFields, isNot(contains('createdBy')));
    });
  });
  // ===========================================================================
  // RENAME
  // ===========================================================================

  group('rename', () {
    Future<String> seed(String name) async {
      final created = await categories.create(name: name, createdBy: "u1");
      return created.id;
    }

    test("corrects the spelling and leaves every other field alone", () async {
      final id = await seed("Laptop");

      final renamed = await categories.rename(categoryId: id, name: "Laptops");

      expect(renamed.name, "Laptops");
      // The identity never moves: it is the document id.
      expect(renamed.id, "laptop");
      expect(renamed.nameKey, "laptop");

      final data = (await categoryData(id))!;
      expect(data["name"], "Laptops");
      expect(data["nameKey"], "laptop");
      expect(data["createdBy"], "u1");
      expect(data.containsKey("createdAt"), isTrue);
    });

    test("trims and collapses whitespace in the new name", () async {
      final id = await seed("Laptop");

      final renamed = await categories.rename(
        categoryId: id,
        name: "  Network   Switch  ",
      );

      expect(renamed.name, "Network Switch");
      expect((await categoryData(id))!["name"], "Network Switch");
    });

    test("a name that only differs in case or spacing is allowed", () async {
      final id = await seed("Network Device");

      // Same key, so it is this category being re-spelled, not a clash.
      final renamed = await categories.rename(
        categoryId: id,
        name: "NETWORK   device",
      );

      expect(renamed.name, "NETWORK device");
      expect(renamed.nameKey, "network_device");
    });

    test("refuses a name another category already owns", () async {
      final laptop = await seed("Laptop");
      await seed("Monitor");

      await expectLater(
        categories.rename(categoryId: laptop, name: "monitor"),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            "message",
            contains("already exists"),
          ),
        ),
      );

      // Nothing changed.
      expect((await categoryData(laptop))!["name"], "Laptop");
    });

    test("refuses a name that normalises onto another category key", () async {
      final laptop = await seed("Laptop");
      await seed("Wi-Fi");

      await expectLater(
        categories.rename(categoryId: laptop, name: "WIFI"),
        throwsA(isA<Exception>()),
      );
    });

    test(
      "refuses an empty name, a punctuation-only name and an over-long one",
      () async {
        final id = await seed("Laptop");

        for (final bad in ["", "   ", "***"]) {
          await expectLater(
            categories.rename(categoryId: id, name: bad),
            throwsA(isA<Exception>()),
            reason: bad,
          );
        }

        await expectLater(
          categories.rename(
            categoryId: id,
            name: "x" * (CategoryService.maxNameLength + 1),
          ),
          throwsA(isA<Exception>()),
        );

        expect((await categoryData(id))!["name"], "Laptop");
      },
    );

    test("refuses a category that no longer exists", () async {
      await expectLater(
        categories.rename(categoryId: "ghost", name: "Ghost"),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            "message",
            contains("no longer exists"),
          ),
        ),
      );
    });

    test("renaming twice keeps the same document", () async {
      final id = await seed("Laptop");

      await categories.rename(categoryId: id, name: "Laptops");
      await categories.rename(categoryId: id, name: "Notebooks");

      expect((await db.collection("categories").get()).docs, hasLength(1));
      expect((await categoryData(id))!["name"], "Notebooks");
    });

    test(
      "an asset keeping the old spelling still resolves to one entry",
      () async {
        // This is what makes a rename safe for existing data: the asset text
        // and the corrected name share a key, so the list offers one option -
        // the corrected one - and the asset is never shown an unknown category.
        final id = await seed("Laptop");
        await categories.rename(categoryId: id, name: "Laptops");

        // Keyed on the category's identity, which the rename did not move,
        // so the asset's older spelling collapses onto the corrected one.
        final merged = CategoryService.mergeCategories(
          catalogue: await categories.loadCategories(),
          assetCategories: const ["Laptop"],
        );

        expect(merged, ["Laptops"]);
      },
    );
  });
}
