import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reports"), centerTitle: true),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              "System Reports",

              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            _reportCard(
              "Inventory Report",

              "View complete asset inventory",

              Icons.inventory,
            ),

            _reportCard(
              "Assigned Assets",

              "Track assets assigned to users",

              Icons.person,
            ),

            _reportCard(
              "Requests Report",

              "View approval request history",

              Icons.assignment,
            ),

            _reportCard("User Activity", "Monitor user actions", Icons.history),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Export feature coming soon")),
                  );
                },

                icon: const Icon(Icons.download),

                label: const Text("Export Report"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(String title, String subtitle, IconData icon) {
    return Card(
      elevation: 5,

      margin: const EdgeInsets.only(bottom: 15),

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),

        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),

        subtitle: Text(subtitle),

        trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      ),
    );
  }
}
