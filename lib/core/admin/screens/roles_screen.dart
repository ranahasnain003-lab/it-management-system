import 'package:flutter/material.dart';

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roles = [
      {
        "name": "Super Admin",
        "description": "Full system access",
        "icon": Icons.admin_panel_settings,
      },

      {
        "name": "Admin",
        "description": "Manage inventory and users",
        "icon": Icons.manage_accounts,
      },

      {
        "name": "User",
        "description": "Limited access user",
        "icon": Icons.person,
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Roles Management"), centerTitle: true),

      body: ListView.builder(
        padding: const EdgeInsets.all(16),

        itemCount: roles.length,

        itemBuilder: (context, index) {
          final role = roles[index];

          return Card(
            elevation: 5,

            margin: const EdgeInsets.only(bottom: 15),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),

            child: ListTile(
              leading: CircleAvatar(
                radius: 25,

                child: Icon(role["icon"] as IconData),
              ),

              title: Text(
                role["name"].toString(),

                style: const TextStyle(
                  fontWeight: FontWeight.bold,

                  fontSize: 18,
                ),
              ),

              subtitle: Text(role["description"].toString()),

              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
          );
        },
      ),
    );
  }
}
