import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? "";

    return Scaffold(
      appBar: AppBar(title: const Text("Security"), centerTitle: true),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          Card(
            elevation: 5,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),

            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.email)),

              title: const Text("Account Email"),

              subtitle: Text(email),
            ),
          ),

          const SizedBox(height: 15),

          Card(
            elevation: 5,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),

            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.lock)),

              title: const Text("Change Password"),

              subtitle: const Text("Send password reset email"),

              trailing: const Icon(Icons.arrow_forward_ios),

              onTap: () async {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Password reset email sent")),
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 15),

          Card(
            elevation: 5,

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),

            child: const ListTile(
              leading: CircleAvatar(child: Icon(Icons.verified_user)),

              title: Text("Account Protection"),

              subtitle: Text(
                "Your account is secured with Firebase Authentication",
              ),
            ),
          ),
        ],
      ),
    );
  }
}
