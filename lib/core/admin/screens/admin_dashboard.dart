import 'package:flutter/material.dart';

import '../../users/screens/users_screen.dart';
import 'roles_screen.dart';
import 'permissions_screen.dart';
import 'reports_screen.dart';
import 'logs_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Control Panel"),

        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(22),

              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.blue],
                ),

                borderRadius: BorderRadius.circular(20),
              ),

              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    "Super Admin",

                    style: TextStyle(
                      color: Colors.white,

                      fontSize: 26,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  SizedBox(height: 8),

                  Text(
                    "Manage complete IT system",

                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            GridView.count(
              crossAxisCount: 2,

              shrinkWrap: true,

              physics: const NeverScrollableScrollPhysics(),

              mainAxisSpacing: 16,

              crossAxisSpacing: 16,

              children: [
                _item(context, "Users", Icons.people, const UsersScreen()),

                _item(
                  context,

                  "Roles",

                  Icons.admin_panel_settings,

                  const RolesScreen(),
                ),

                _item(
                  context,

                  "Permissions",

                  Icons.security,

                  const PermissionsScreen(),
                ),

                _item(
                  context,

                  "Reports",

                  Icons.analytics,

                  const ReportsScreen(),
                ),

                _item(
                  context,

                  "Activity Logs",

                  Icons.history,

                  const LogsScreen(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, String title, IconData icon, Widget page) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },

      child: Card(
        elevation: 5,

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(icon, size: 40, color: Colors.blue),

            const SizedBox(height: 12),

            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
