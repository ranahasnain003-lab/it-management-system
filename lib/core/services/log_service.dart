import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../../models/activity_model.dart';

class LogService {
  LogService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : this._(firestore, auth);

  const LogService._(this._firestore, this._auth);

  /// Both stay NULLABLE and are resolved only when an entry is actually
  /// written: a LogService is held by providers and services that tests build
  /// against fakes, and reading FirebaseFirestore.instance or
  /// FirebaseAuth.instance in the constructor would throw there long before any
  /// log was wanted.
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  CollectionReference get _logCollection {
    final firestore = _firestore ?? FirebaseFirestore.instance;

    return firestore.collection(AppConstants.activityLogsCollection);
  }

  Future<void> createLog(ActivityModel activity) async {
    // Audit entries carry the server time (required by the Security Rules,
    // so a client clock can never back-date an entry).
    await _logCollection.add(
      activity.toMap()..['createdAt'] = FieldValue.serverTimestamp(),
    );
  }

  // ===========================================================================
  // AUDIT TRAIL
  // ===========================================================================

  /// Records one audit entry for an operation that has ALREADY succeeded.
  ///
  /// Deliberately best effort, and the only way the app writes the trail:
  ///
  /// - it is never called from inside the caller's transaction, so a log write
  ///   can never make a stock movement retry or abort;
  /// - it is called only after the operation it describes has committed, so
  ///   the trail never claims something that did not happen;
  /// - every failure is swallowed with a debugPrint, because an operation the
  ///   user completed must not be reported as failed just because its audit
  ///   line could not be written.
  ///
  /// The fields are the ones the `logs` rule requires: `userId` is the
  /// signed-in account (the rule refuses anything else) and `createdAt` is the
  /// server time (the rule requires `createdAt == request.time`), so neither
  /// the author nor the moment can be forged from the client. `details`
  /// duplicates `description` because the web Activity Log reads both.
  Future<void> recordActivity({
    required String action,
    required String description,
    required String module,
    String targetId = '',
    String userName = '',
  }) async {
    try {
      final user = (_auth ?? FirebaseAuth.instance).currentUser;

      final uid = user?.uid.trim() ?? '';

      // Without a signed-in account the entry could only be rejected by the
      // rule, so nothing is attempted.
      if (uid.isEmpty) {
        return;
      }

      final cleanDescription = description.trim();

      final author = userName.trim().isNotEmpty
          ? userName.trim()
          : (user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!.trim()
                : (user?.email?.trim() ?? ''));

      await _logCollection.add({
        'action': action.trim(),
        'description': cleanDescription,
        'details': cleanDescription,
        'userId': uid,
        'userName': author,
        'module': module.trim(),
        'targetId': targetId.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Activity log "${action.trim()}" could not be written: $e');
    }
  }

  Stream<List<ActivityModel>> getLogs() {
    return _logCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ActivityModel.fromMap(
              doc.data() as Map<String, dynamic>,

              doc.id,
            );
          }).toList();
        });
  }

  Future<void> deleteLog(String id) async {
    await _logCollection.doc(id).delete();
  }
}
