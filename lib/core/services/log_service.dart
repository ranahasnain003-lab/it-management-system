import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../../models/activity_model.dart';

class LogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _logCollection {
    return _firestore.collection(AppConstants.activityLogsCollection);
  }

  Future<void> createLog(ActivityModel activity) async {
    // Audit entries carry the server time (required by the Security Rules,
    // so a client clock can never back-date an entry).
    await _logCollection.add(
      activity.toMap()..['createdAt'] = FieldValue.serverTimestamp(),
    );
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
