import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/notification_model.dart';
import '../constants/app_constants.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _notificationCollection {
    return _firestore.collection(AppConstants.notificationsCollection);
  }

  Stream<List<NotificationModel>> getNotifications(String userId) {
    // Sorted client-side: where(userId) + orderBy(createdAt) requires a
    // composite index that is not deployed, which made the query fail.
    return _notificationCollection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs.map((doc) {
            return NotificationModel.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();

          // A just-written notification has a pending server timestamp (null);
          // treat it as newest.
          final newest = DateTime.fromMillisecondsSinceEpoch(8640000000000000);

          notifications.sort(
            (a, b) => (b.createdAt ?? newest).compareTo(a.createdAt ?? newest),
          );

          return notifications;
        });
  }

  Stream<int> getUnreadCount(String userId) {
    return _notificationCollection
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> createNotification({
    required String notificationId,
    required String title,
    required String message,
    required String type,
    required String userId,
    String requestId = '',
    String movementId = '',
  }) async {
    final notificationRef = _notificationCollection.doc(notificationId);

    final existingNotification = await notificationRef.get();

    if (existingNotification.exists) {
      return;
    }

    await notificationRef.set({
      'title': title,
      'message': message,
      'type': type,
      'userId': userId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'requestId': requestId,
      'movementId': movementId,
    });
  }

  Future<void> markAsRead(String notificationId) async {
    await _notificationCollection.doc(notificationId).update({'isRead': true});
  }

  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _notificationCollection
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  Future<void> deleteNotification(String id) async {
    await _notificationCollection.doc(id).delete();
  }
}
