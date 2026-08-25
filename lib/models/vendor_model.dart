import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String company;
  final Timestamp createdAt;

  VendorModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.company,
    required this.createdAt,
  });

  factory VendorModel.fromMap(Map<String, dynamic> map, String id) {
    return VendorModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      company: map['company'] ?? '',
      createdAt: map['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'company': company,
      'createdAt': createdAt,
    };
  }
}