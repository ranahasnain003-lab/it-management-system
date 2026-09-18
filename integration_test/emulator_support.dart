// Test harness for the Firebase Local Emulator Suite.
//
// Run the emulators on the development machine first:
//   firebase emulators:start --only firestore,auth --project it-inventory-8e690
//
// The Android emulator reaches the host machine at 10.0.2.2.
//
// Privileged setup (Super Admin profiles, fixtures) is written through the
// emulator's REST API with the "owner" token, which bypasses Security Rules.
// Every behaviour under test then runs through the real app code, signed in
// as the real role, with the project's firestore.rules enforced.


import 'support/emulator_http.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:it_management_system/firebase_options.dart';

const String emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

const String projectId = 'it-inventory-8e690';

bool _initialized = false;

Future<void> initFirebaseForEmulator() async {
  if (_initialized) {
    return;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Auth first: on the web, touching Firestore initializes Auth, which starts
  // restoring any saved session against the configured endpoint.
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);

  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );

  _initialized = true;
}

Future<Map<String, dynamic>> _request(
  String method,
  Uri uri, {
  Object? body,
  bool owner = true,
}) {
  return emulatorRequest(method, uri, body: body, owner: owner);
}

/// Deletes every document and every Auth account in the emulators.
Future<void> resetEmulators() async {
  await FirebaseAuth.instance.signOut();

  await _request(
    'DELETE',
    Uri.parse(
      'http://$emulatorHost:8080/emulator/v1/projects/$projectId/databases/(default)/documents',
    ),
  );

  await _request(
    'DELETE',
    Uri.parse(
      'http://$emulatorHost:9099/emulator/v1/projects/$projectId/accounts',
    ),
  );
}

/// Creates a verified Auth account and returns its UID.
Future<String> createAuthUser(String email, String password) async {
  final created = await _request(
    'POST',
    Uri.parse(
      'http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-key',
    ),
    body: {'email': email, 'password': password, 'returnSecureToken': true},
    owner: false,
  );

  final uid = created['localId'] as String;

  await _request(
    'POST',
    Uri.parse(
      'http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:update',
    ),
    body: {'localId': uid, 'emailVerified': true},
  );

  return uid;
}

Map<String, dynamic> _value(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is double) return {'doubleValue': value};
  if (value is String) return {'stringValue': value};
  if (value is DateTime) {
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  if (value is List) {
    return {
      'arrayValue': {'values': value.map(_value).toList()},
    };
  }
  if (value is Map<String, dynamic>) {
    return {
      'mapValue': {'fields': value.map((k, v) => MapEntry(k, _value(v)))},
    };
  }

  throw ArgumentError('Unsupported value: $value');
}

/// Writes a document bypassing Security Rules (fixture setup only).
Future<void> seedDocument(String path, Map<String, dynamic> data) async {
  await _request(
    'PATCH',
    Uri.parse(
      'http://$emulatorHost:8080/v1/projects/$projectId/databases/(default)/documents/$path',
    ),
    body: {'fields': data.map((k, v) => MapEntry(k, _value(v)))},
  );
}

Future<void> signInAs(String email, String password) async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser != null) {
    await auth.signOut();
    // On the web the auth state is propagated asynchronously.
    await auth.authStateChanges().firstWhere((user) => user == null);
  }

  await auth.signInWithEmailAndPassword(email: email, password: password);

  await auth.authStateChanges().firstWhere(
    (user) => user?.email?.toLowerCase() == email.toLowerCase(),
  );
}

Future<void> signOutAndWait() async {
  final auth = FirebaseAuth.instance;

  if (auth.currentUser == null) {
    return;
  }

  await auth.signOut();
  await auth.authStateChanges().firstWhere((user) => user == null);
}

/// True when [action] is rejected by Firestore Security Rules.
Future<bool> isDenied(Future<Object?> Function() action) async {
  try {
    await action();
    return false;
  } on FirebaseException catch (e) {
    if (e.code == 'permission-denied') {
      return true;
    }
    rethrow;
  }
}

Map<String, dynamic> userProfile({
  required String uid,
  required String name,
  required String email,
  required String role,
  String status = 'active',
  String createdBy = '',
}) {
  return {
    'uid': uid,
    'name': name,
    'email': email,
    'role': role,
    'roles': [role],
    'status': status,
    'createdBy': createdBy,
    'createdByEmail': '',
    'employeeId': '',
    'department': 'IT',
    'designation': role,
    'organizationId': '',
    'createdAt': DateTime.utc(2026, 1, 1),
  };
}

Map<String, dynamic> assetFixture({
  required String adminId,
  required String name,
  required int quantity,
}) {
  return {
    'assetId': 'TAG-$name',
    'name': name,
    'category': 'Laptop',
    'status': 'Available',
    'quantity': quantity,
    'headOfficeQuantity': quantity,
    'assignedQuantity': 0,
    'deployedQuantity': 0,
    'adminId': adminId,
    'adminName': 'Admin',
    'location': 'Head Office',
    'condition': 'Good',
    'notes': '',
    'serialNumber': 'SN-$name',
    'brand': 'Dell',
    'model': 'Latitude',
    'purchasePrice': 1000.0,
    'warrantyMonths': 12,
    'createdAt': DateTime.utc(2026, 1, 1),
  };
}

/// Reads a collection with the emulator's owner token (bypasses rules), for
/// assertions that must not depend on what the signed-in account may read.
Future<List<Map<String, dynamic>>> adminListCollection(String collection) async {
  // The REST listing is paged: without following nextPageToken a large
  // collection is silently truncated and assertions undercount.
  final documents = <dynamic>[];
  String? pageToken;

  do {
    final response = await _request(
      'GET',
      Uri.parse(
        'http://$emulatorHost:8080/v1/projects/$projectId/databases/(default)/documents/$collection'
        '?pageSize=300${pageToken == null ? '' : '&pageToken=$pageToken'}',
      ),
    );

    documents.addAll((response['documents'] as List<dynamic>?) ?? const []);
    pageToken = response['nextPageToken'] as String?;
  } while (pageToken != null && pageToken.isNotEmpty);

  return documents.map((raw) {
    final document = raw as Map<String, dynamic>;
    final fields = (document['fields'] as Map<String, dynamic>?) ?? const {};

    final decoded = <String, dynamic>{
      'id': (document['name'] as String).split('/').last,
    };

    fields.forEach((key, value) {
      final field = value as Map<String, dynamic>;

      if (field.containsKey('integerValue')) {
        decoded[key] = int.parse(field['integerValue'] as String);
      } else if (field.containsKey('doubleValue')) {
        decoded[key] = field['doubleValue'];
      } else if (field.containsKey('booleanValue')) {
        decoded[key] = field['booleanValue'];
      } else if (field.containsKey('arrayValue')) {
        final values =
            ((field['arrayValue'] as Map<String, dynamic>)['values']
                    as List<dynamic>?) ??
                const [];
        decoded[key] = values
            .map((item) => (item as Map<String, dynamic>)['stringValue'])
            .toList();
      } else if (field.containsKey('nullValue')) {
        decoded[key] = null;
      } else {
        decoded[key] = field['stringValue'];
      }
    });

    return decoded;
  }).toList();
}
