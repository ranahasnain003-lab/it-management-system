import '../models/notification_model.dart';

import '../core/services/notification_service.dart';



class NotificationRepository {

  final NotificationService _notificationService =
      NotificationService();



  Stream<List<NotificationModel>> getNotifications(

    String userId,

  ) {

    return _notificationService.getNotifications(

      userId,

    );

  }



  Stream<int> getUnreadCount(

    String userId,

  ) {

    return _notificationService.getUnreadCount(

      userId,

    );

  }



  Future<void> markAsRead(

    String notificationId,

  ) async {


    await _notificationService.markAsRead(

      notificationId,

    );

  }



  Future<void> markAllAsRead(

    String userId,

  ) async {


    await _notificationService.markAllAsRead(

      userId,

    );

  }



  Future<void> deleteNotification(

    String id,

  ) async {


    await _notificationService.deleteNotification(

      id,

    );

  }

}