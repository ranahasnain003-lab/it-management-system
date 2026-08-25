import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;

  final String title;

  final String message;

  final String type;

  final String userId;

  final bool isRead;

  final DateTime? createdAt;

  NotificationModel({
    required this.id,

    required this.title,

    required this.message,

    required this.type,

    required this.userId,

    required this.isRead,

    this.createdAt,
  });

  factory NotificationModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    return NotificationModel(
      id: documentId,

      title: map['title'] ?? '',

      message: map['message'] ?? '',

      type: map['type'] ?? '',

      userId: map['userId'] ?? '',

      isRead: map['isRead'] ?? false,

      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
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
    };
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,

      title: title,

      message: message,

      type: type,

      userId: userId,

      isRead: isRead ?? this.isRead,

      createdAt: createdAt,
    );
  }
}
