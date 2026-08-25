import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../../models/notification_model.dart';


class NotificationService {

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;



  CollectionReference get _notificationCollection {

    return _firestore.collection(
      AppConstants.notificationsCollection,
    );

  }



  Stream<List<NotificationModel>> getNotifications(
    String userId,
  ) {

    return _notificationCollection
        .where(
          'userId',
          isEqualTo: userId,
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots()
        .map((snapshot) {

          return snapshot.docs.map((doc) {

            return NotificationModel.fromMap(

              doc.data() as Map<String, dynamic>,

              doc.id,

            );

          }).toList();

        });

  }



  Stream<int> getUnreadCount(
    String userId,
  ) {

    return _notificationCollection
        .where(
          'userId',
          isEqualTo: userId,
        )
        .where(
          'isRead',
          isEqualTo: false,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.length,
        );

  }



  Future<void> markAsRead(
    String notificationId,
  ) async {

    await _notificationCollection

        .doc(notificationId)

        .update({

          'isRead': true,

        });

  }



  Future<void> markAllAsRead(
    String userId,
  ) async {

    final snapshot = await _notificationCollection

        .where(
          'userId',
          isEqualTo: userId,
        )

        .where(
          'isRead',
          isEqualTo: false,
        )

        .get();



    for (var doc in snapshot.docs) {

      await doc.reference.update({

        'isRead': true,

      });

    }

  }



  Future<void> deleteNotification(
    String id,
  ) async {

    await _notificationCollection

        .doc(id)

        .delete();

  }

}