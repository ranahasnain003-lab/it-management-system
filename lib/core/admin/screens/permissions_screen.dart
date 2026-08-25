import 'package:flutter/material.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final Map<String, bool> permissions = {
    "Manage Inventory": true,

    "Add Assets": true,

    "Edit Assets": true,

    "Delete Assets": false,

    "Manage Users": true,

    "Approve Requests": true,

    "View Reports": true,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Permissions Management"),

        centerTitle: true,
      ),

      body: ListView.builder(
        padding: const EdgeInsets.all(16),

        itemCount: permissions.length,

        itemBuilder: (context, index) {
          final key = permissions.keys.elementAt(index);

          return Card(
            elevation: 4,

            margin: const EdgeInsets.only(bottom: 12),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),

            child: SwitchListTile(
              title: Text(
                key,

                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              subtitle: const Text("Control system access"),

              value: permissions[key]!,

              onChanged: (value) {
                setState(() {
                  permissions[key] = value;
                });
              },
            ),
          );
        },
      ),
    );
  }
}
