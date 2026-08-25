import 'package:cloud_firestore/cloud_firestore.dart';


class CategoryModel {

  final String id;

  final String name;

  final String description;

  final String icon;

  final bool isActive;

  final DateTime? createdAt;

  final String createdBy;



  CategoryModel({

    required this.id,

    required this.name,

    required this.description,

    required this.icon,

    required this.isActive,

    this.createdAt,

    required this.createdBy,

  });



  factory CategoryModel.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {

    return CategoryModel(

      id: documentId,

      name: map['name'] ?? '',

      description: map['description'] ?? '',

      icon: map['icon'] ?? '',

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

      'icon': icon,

      'isActive': isActive,


      'createdAt':
          createdAt != null
              ? Timestamp.fromDate(createdAt!)
              : null,


      'createdBy': createdBy,

    };

  }



  CategoryModel copyWith({

    String? name,

    String? description,

    String? icon,

    bool? isActive,

  }) {

    return CategoryModel(

      id: id,

      name: name ?? this.name,

      description: description ?? this.description,

      icon: icon ?? this.icon,

      isActive: isActive ?? this.isActive,

      createdAt: createdAt,

      createdBy: createdBy,

    );

  }

}