import 'package:flutter/material.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = [
      {
        "title": "Asset Added",
        "user": "Admin",
        "time": "Today 10:30 AM",
        "icon": Icons.add_box,
      },

      {
        "title": "User Created",
        "user": "Super Admin",
        "time": "Today 09:15 AM",
        "icon": Icons.person_add,
      },

      {
        "title": "Request Approved",
        "user": "Admin",
        "time": "Yesterday 05:20 PM",
        "icon": Icons.check_circle,
      },
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Activity Logs"), centerTitle: true),

      body: ListView.builder(
        padding: const EdgeInsets.all(16),

        itemCount: logs.length,

        itemBuilder: (context, index) {
          final log = logs[index];

          return Card(
            elevation: 5,

            margin: const EdgeInsets.only(bottom: 15),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),

            child: ListTile(
              leading: CircleAvatar(child: Icon(log["icon"] as IconData)),

              title: Text(
                log["title"].toString(),

                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text("By: ${log["user"]}"),

                  Text(log["time"].toString()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
