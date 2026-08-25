import 'package:cloud_firestore/cloud_firestore.dart';


class DepartmentModel {

  final String id;

  final String name;

  final String description;

  final bool isActive;

  final DateTime? createdAt;

  final String createdBy;



  DepartmentModel({

    required this.id,

    required this.name,

    required this.description,

    required this.isActive,

    this.createdAt,

    required this.createdBy,

  });



  factory DepartmentModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {

    return DepartmentModel(

      id: documentId,

      name: map['name'] ?? '',

      description: map['description'] ?? '',

      isActive: map['isActive'] ?? true,


      createdAt:
          map['createdAt'] != null
              ? (map['createdAt'] as Timestamp).toDate()
              : null,


      createdBy: map['createdBy'] ?? '',

    );

  }



  Map<String, dynamic> toMap() {

    return {

      'name': name,

      'description': description,

      'isActive': isActive,


      'createdAt':
          createdAt != null
              ? Timestamp.fromDate(createdAt!)
              : null,


      'createdBy': createdBy,

    };

  }



  DepartmentModel copyWith({

    String? name,

    String? description,

    bool? isActive,

  }) {

    return DepartmentModel(

      id: id,

      name: name ?? this.name,

      description: description ?? this.description,

      isActive: isActive ?? this.isActive,

      createdAt: createdAt,

      createdBy: createdBy,

    );

  }

}