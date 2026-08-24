import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool deleting = false;
  bool exporting = false;

  Future<void> exportMyData() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final export = await ApiService.exportAccount();
      final jsonText = const JsonEncoder.withIndent('  ').convert(export);
      final date = DateTime.now();
      final stamp =
          '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

      await FilePicker.saveFile(
        fileName: 'EkThikana_export_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(jsonText)),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('EkThikana data export prepared.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> deleteAccount() async {
    final first = await confirmAction(
      context,
      title: 'Delete EkThikana account?',
      message:
          'This permanently deletes your account, personal records, notes and files you own. This cannot be undone.',
      action: 'Continue',
    );
    if (!first || !mounted) return;

    final phrase = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Final confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type DELETE to permanently remove your account.'),
            const SizedBox(height: 12),
            TextField(
              controller: phrase,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(d, phrase.text.trim().toUpperCase() == 'DELETE'),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    phrase.dispose();

    if (confirmed != true) return;

    setState(() => deleting = true);
    try {
      await ApiService.deleteAccount();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const CircleAvatar(
                radius: 42,
                child: Icon(Icons.person, size: 40),
              ),
              const SizedBox(height: 12),
              Text(
                data['displayName']?.toString() ??
                    user.displayName ??
                    '',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                user.email ?? '',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Account type'),
                      trailing: Text(
                        (data['role']?.toString() ?? '').toUpperCase(),
                      ),
                    ),
                    if (data['role'] == 'student') ...[
                      ListTile(
                        leading: const Icon(
                          Icons.account_balance_outlined,
                        ),
                        title: const Text('University'),
                        subtitle: Text(
                          data['university']?.toString() ?? '',
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: const Text('Department'),
                        subtitle: Text(
                          data['department']?.toString() ?? '',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (deleting || exporting) ? null : exportMyData,
                icon: const Icon(Icons.download_outlined),
                label: Text(
                  exporting ? 'Preparing export…' : 'Export my data',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: deleting ? null : AuthService.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: deleting ? null : deleteAccount,
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(
                  deleting ? 'Deleting account…' : 'Delete account permanently',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
