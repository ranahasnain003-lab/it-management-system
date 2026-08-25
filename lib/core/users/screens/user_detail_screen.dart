import 'package:flutter/material.dart';

import '../../../models/user_model.dart';

class UserDetailScreen extends StatelessWidget {
  final UserModel user;

  const UserDetailScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Details"), centerTitle: true),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            CircleAvatar(
              radius: 55,

              child: Text(
                user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : "U",

                style: const TextStyle(
                  fontSize: 40,

                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              user.fullName,

              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 25),

            _infoCard(Icons.email, "Email", user.email),

            _infoCard(Icons.admin_panel_settings, "Role", user.role),

            _infoCard(Icons.verified_user, "Status", user.status),

            _infoCard(
              Icons.calendar_today,

              "Created At",

              user.createdAt.toString(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(IconData icon, String title, String value) {
    return Card(
      elevation: 4,

      margin: const EdgeInsets.only(bottom: 15),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),

        title: Text(title),

        subtitle: Text(value),
      ),
    );
  }
}
