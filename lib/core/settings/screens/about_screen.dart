import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About App"), centerTitle: true),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [
            const CircleAvatar(
              radius: 55,

              child: Icon(Icons.computer, size: 55),
            ),

            const SizedBox(height: 20),

            const Text(
              "IT Management System",

              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            const Text(
              "Professional inventory and asset management solution",

              textAlign: TextAlign.center,

              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 30),

            _infoCard(Icons.info, "Version", "1.0.0"),

            _infoCard(Icons.security, "Technology", "Flutter + Firebase"),

            _infoCard(Icons.business, "System Type", "IT Asset Management"),

            _infoCard(Icons.person, "Developer", "IT Administrator"),

            const SizedBox(height: 30),

            const Text(
              "© 2026 IT Management System",

              style: TextStyle(color: Colors.grey),
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
