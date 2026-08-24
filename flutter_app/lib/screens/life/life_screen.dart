import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'bazar_buddy_screen.dart';
import 'medicine_screen.dart';
import 'record_module_screen.dart';

class LifeScreen extends StatelessWidget {
  const LifeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = <_LifeModule>[
      _LifeModule('Medicine', 'ওষুধ', Icons.medication_liquid_outlined, const Color(0xFFE7FBF8), EkColors.teal, const MedicineScreen()),
      _LifeModule(
        'BazarBuddy', 'বাজারবাডি', Icons.shopping_cart_outlined, const Color(0xFFEDFAEA), const Color(0xFF45AF4B),
        const BazarBuddyScreen(),
      ),
      _LifeModule(
        'FamilyHub', 'ফ্যামিলিহাব', Icons.groups_2_outlined, const Color(0xFFFFEEEE), const Color(0xFFFF5A55),
        const RecordModuleScreen(title: 'FamilyHub', collection: 'family_records', itemLabel: 'Record title', detailsLabel: 'Details'),
      ),
      _LifeModule(
        'RentMate', 'রেন্টমেট', Icons.home_outlined, const Color(0xFFFFECEF), const Color(0xFFF24A5C),
        const RecordModuleScreen(title: 'RentMate', collection: 'rent_records', itemLabel: 'Rent record', detailsLabel: 'Amount / due date / note'),
      ),
      _LifeModule(
        'CommuteBD', 'যাতায়াত', Icons.directions_bus_outlined, const Color(0xFFFFF5DC), const Color(0xFFFFA621),
        const RecordModuleScreen(title: 'CommuteBD', collection: 'saved_locations', itemLabel: 'Place / route', detailsLabel: 'Location / transport note'),
      ),
      _LifeModule(
        'Wellness', 'সুস্থতা', Icons.favorite_outline, const Color(0xFFEFF1FF), const Color(0xFF5369E8),
        const RecordModuleScreen(title: 'Wellness', collection: 'wellness_records', itemLabel: 'Entry', detailsLabel: 'Sleep / water / activity / note'),
      ),
    ];

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EkLanguage.text('Life Hub', 'লাইফ হাব')),
              Text(EkLanguage.text('Manage life, stress-free', 'পরিকল্পিত থাকুন, জীবনের জন্য'), style: const TextStyle(fontSize: 11, color: EkColors.muted, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: .92,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
              ),
              itemCount: modules.length,
              itemBuilder: (context, i) {
                final m = modules[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.page)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                    decoration: BoxDecoration(
                      color: m.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .78), shape: BoxShape.circle),
                          child: Icon(m.icon, color: m.color, size: 25),
                        ),
                        const SizedBox(height: 8),
                        Text(EkLanguage.text(m.en, m.bn), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            SectionHeader(title: Text(EkLanguage.text("Today's Reminders", 'আজকের রিমাইন্ডার'))),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _reminder(Icons.medication_outlined, EkColors.red, EkLanguage.text('Medicine', 'ওষুধ'), EkLanguage.text('Open Medicine to see confirmed schedule', 'নিশ্চিত সময় দেখতে Medicine খুলুন')),
                  const Divider(height: 1, indent: 62),
                  _reminder(Icons.shopping_basket_outlined, EkColors.green, EkLanguage.text('Shopping', 'বাজার'), EkLanguage.text('Keep your grocery items in BazarBuddy', 'BazarBuddy-তে বাজারের তালিকা রাখুন')),
                  const Divider(height: 1, indent: 62),
                  _reminder(Icons.home_outlined, EkColors.blue, EkLanguage.text('Rent', 'ভাড়া'), EkLanguage.text('Keep rent notes and due information together', 'ভাড়ার নোট ও সময় একসাথে রাখুন')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reminder(IconData icon, Color color, String title, String subtitle) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: EkColors.muted),
    );
  }
}

class _LifeModule {
  _LifeModule(this.en, this.bn, this.icon, this.background, this.color, this.page);
  final String en;
  final String bn;
  final IconData icon;
  final Color background;
  final Color color;
  final Widget page;
}
