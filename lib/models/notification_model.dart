import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type;
  final String userId;
  final bool isRead;
  final DateTime? createdAt;

  // Optional navigation/reference data.
  final String requestId;
  final String movementId;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.userId,
    required this.isRead,
    this.createdAt,
    this.requestId = '',
    this.movementId = '',
  });

  factory NotificationModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    DateTime? parsedCreatedAt;

    final createdAtValue = map['createdAt'];

    if (createdAtValue is Timestamp) {
      parsedCreatedAt = createdAtValue.toDate();
    } else if (createdAtValue is DateTime) {
      parsedCreatedAt = createdAtValue;
    }

    return NotificationModel(
      id: documentId,
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      isRead: map['isRead'] == true,
      createdAt: parsedCreatedAt,
      requestId: map['requestId']?.toString() ?? '',
      movementId: map['movementId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'type': type,
      'userId': userId,
      'isRead': isRead,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'requestId': requestId,
      'movementId': movementId,
    };
  }

  NotificationModel copyWith({
    bool? isRead,
    String? requestId,
    String? movementId,
  }) {
    return NotificationModel(
      id: id,
      title: title,
      message: message,
      type: type,
      userId: userId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      requestId: requestId ?? this.requestId,
      movementId: movementId ?? this.movementId,
    );
  }
}
