import 'package:cloud_firestore/cloud_firestore.dart';


class ActivityModel {

  final String id;

  final String action;

  final String description;

  final String userId;

  final String userName;

  final String module;

  final DateTime? createdAt;



  ActivityModel({

    required this.id,

    required this.action,

    required this.description,

    required this.userId,

    required this.userName,

    required this.module,

    this.createdAt,

  });



  factory ActivityModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {

    return ActivityModel(

      id: documentId,

      action: map['action'] ?? '',

      description: map['description'] ?? '',

      userId: map['userId'] ?? '',

      userName: map['userName'] ?? '',

      module: map['module'] ?? '',


      createdAt:
          map['createdAt'] != null
              ? (map['createdAt'] as Timestamp).toDate()
              : null,

    );

  }



  Map<String, dynamic> toMap() {

    return {

      'action': action,

      'description': description,

      'userId': userId,

      'userName': userName,

      'module': module,


      'createdAt':
          createdAt != null
              ? Timestamp.fromDate(createdAt!)
              : null,

    };

  }

}