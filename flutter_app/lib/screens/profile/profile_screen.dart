import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/financial_service.dart';
import '../life/expense_tracker_screen.dart';

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
        fileName: 'Gochano_export_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(jsonText)),
      );
      if (mounted) {
        showSuccess(
          context,
          EkLanguage.text(
            'Your data export is ready.',
            'আপনার ডেটা এক্সপোর্ট প্রস্তুত।',
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
      title: EkLanguage.text(
        'Delete Gochano account?',
        'Gochano অ্যাকাউন্ট মুছবেন?',
      ),
      message: EkLanguage.text(
        'This permanently deletes your account, personal records, notes and files you own. This cannot be undone.',
        'এটি আপনার অ্যাকাউন্ট, ব্যক্তিগত রেকর্ড, নোট ও নিজের ফাইল স্থায়ীভাবে মুছে দেবে। এটি ফিরিয়ে আনা যাবে না।',
      ),
      action: EkLanguage.text('Continue', 'চালিয়ে যান'),
    );
    if (!first || !mounted) return;

    final phrase = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          EkLanguage.text('Final confirmation', 'চূড়ান্ত নিশ্চিতকরণ'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              EkLanguage.text(
                'Type DELETE to permanently remove your account.',
                'স্থায়ীভাবে মুছতে DELETE লিখুন।',
              ),
            ),
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
            child: Text(EkLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              d,
              phrase.text.trim().toUpperCase() == 'DELETE',
            ),
            child: Text(
              EkLanguage.text('Delete permanently', 'স্থায়ীভাবে মুছুন'),
            ),
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

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Profile', 'প্রোফাইল')),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: LanguageToggle(),
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? {};
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: EkColors.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 52,
                      color: EkColors.purple,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  data['displayName']?.toString() ??
                      user.displayName ??
                      '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  user.email ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: EkColors.muted),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Column(
                    children: [
                      _row(
                        Icons.badge_outlined,
                        EkLanguage.text(
                          'Account type',
                          'অ্যাকাউন্টের ধরন',
                        ),
                        (data['role']?.toString() ?? '').toUpperCase(),
                      ),
                      if (data['role'] == 'student') ...[
                        const Divider(height: 1, indent: 60),
                        _row(
                          Icons.account_balance_outlined,
                          EkLanguage.text(
                            'University',
                            'বিশ্ববিদ্যালয়',
                          ),
                          data['university']?.toString() ?? '',
                        ),
                        const Divider(height: 1, indent: 60),
                        _row(
                          Icons.category_outlined,
                          EkLanguage.text('Department', 'বিভাগ'),
                          data['department']?.toString() ?? '',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _financialSummaryCard(),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed:
                      exporting || deleting ? null : exportMyData,
                  icon: exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    EkLanguage.text(
                      exporting
                          ? 'Preparing export…'
                          : 'Export my data',
                      exporting
                          ? 'এক্সপোর্ট প্রস্তুত হচ্ছে…'
                          : 'আমার ডেটা এক্সপোর্ট করুন',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: deleting ? null : AuthService.logout,
                  icon: const Icon(Icons.logout),
                  label: Text(
                    EkLanguage.text('Sign out', 'সাইন আউট'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: deleting ? null : deleteAccount,
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    color: EkColors.red,
                  ),
                  label: Text(
                    EkLanguage.text(
                      deleting
                          ? 'Deleting account…'
                          : 'Delete account permanently',
                      deleting
                          ? 'অ্যাকাউন্ট মুছছে…'
                          : 'অ্যাকাউন্ট স্থায়ীভাবে মুছুন',
                    ),
                    style: const TextStyle(color: EkColors.red),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _financialSummaryCard() {
    return StreamBuilder(
      stream: FinancialService.monthStream(DateTime.now()),
      builder: (context, snap) {
        final items = snap.data ?? const [];
        final summary = FinancialService.summary(items);
        final bySource = summary.bySource;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F8EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: EkColors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        EkLanguage.text(
                          'This Month',
                          'এই মাস',
                        ),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _moneyStat(
                    EkLanguage.text('Total Spending', 'মোট খরচ'),
                    summary.totalSpending,
                    EkColors.red,
                  ),
                ),
                const Divider(height: 26),
                _sourceRow(
                  EkLanguage.text('Daily', 'দৈনিক'),
                  bySource['daily'] ?? 0,
                ),
                _sourceRow(
                  EkLanguage.text('Bazar', 'বাজার'),
                  bySource['bazar'] ?? 0,
                ),
                _sourceRow(
                  EkLanguage.text('Medicine', 'ওষুধ'),
                  bySource['medicine'] ?? 0,
                ),
                _sourceRow(
                  EkLanguage.text('Commute', 'যাতায়াত'),
                  bySource['commute'] ?? 0,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ExpenseTrackerScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                    iconAlignment: IconAlignment.end,
                    label: Text(
                      EkLanguage.text(
                        'View Expense Details',
                        'খরচের বিস্তারিত দেখুন',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _moneyStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: EkColors.muted,
            fontSize: 11,
          ),
        ),
        Text(
          '৳${value.toStringAsFixed(0)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 21,
          ),
        ),
      ],
    );
  }

  Widget _sourceRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: EkColors.muted),
            ),
          ),
          Text(
            '৳${amount.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String value) {
    return ListTile(
      leading: Icon(icon, color: EkColors.muted),
      title: Text(title),
      trailing: SizedBox(
        width: 150,
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: EkColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
