import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../models/financial_transaction.dart';
import '../../services/financial_service.dart';
import 'bazar_buddy_screen.dart';
import 'commute_bd_screen.dart';
import 'daily_expenses_screen.dart';
import 'medicine_screen.dart';

class LifeScreen extends StatelessWidget {
  const LifeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) {
        final modules = [
          _LifeModule(
            title: EkLanguage.text('Medicine', 'ওষুধ'),
            subtitle: EkLanguage.text('Reminders & dose cost', 'রিমাইন্ডার ও ডোজ খরচ'),
            emoji: '💊',
            color: const Color(0xFFE6F8F5),
            page: const MedicineScreen(),
          ),
          _LifeModule(
            title: 'BazarBuddy',
            subtitle: EkLanguage.text('Smart shopping list', 'স্মার্ট বাজার তালিকা'),
            emoji: '🛒',
            color: const Color(0xFFEAF7E6),
            page: const BazarBuddyScreen(),
          ),
          _LifeModule(
            title: EkLanguage.text('Daily Expenses', 'দৈনিক খরচ'),
            subtitle: EkLanguage.text('Daily spending tracker', 'দৈনিক খরচ ট্র্যাকার'),
            emoji: '🍽️',
            color: const Color(0xFFFFF3D9),
            page: const DailyExpensesScreen(),
          ),
          _LifeModule(
            title: 'CommuteBD',
            subtitle: EkLanguage.text('Routes & real fare tracking', 'রুট ও বাস্তব ভাড়া ট্র্যাকিং'),
            emoji: '🚌',
            color: const Color(0xFFE8F1FF),
            page: const CommuteBDScreen(),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(EkLanguage.text('Life Hub', 'লাইফ হাব')),
                Text(
                  EkLanguage.text(
                    'Organize life and spending in one place',
                    'জীবন ও খরচ এক জায়গায় গুছিয়ে রাখুন',
                  ),
                  style: const TextStyle(fontSize: 11, color: EkColors.muted),
                ),
              ],
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 12),
                child: LanguageToggle(),
              ),
            ],
          ),
          body: StreamBuilder<List<FinancialTransactionModel>>(
            stream: FinancialService.monthStream(DateTime.now()),
            builder: (context, snap) {
              final summary = FinancialService.summary(snap.data ?? const []);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: modules.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 156,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemBuilder: (context, i) {
                      final module = modules[i];
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => module.page),
                        ),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: module.color,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: .04),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(module.emoji, style: const TextStyle(fontSize: 42)),
                              const Spacer(),
                              Text(
                                module.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                module.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: EkColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF5FCEB), Color(0xFFFFFAEA)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE4EBCD)),
                    ),
                    child: Row(
                      children: [
                        const Text('💰', style: TextStyle(fontSize: 38)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                EkLanguage.text(
                                  'This Month',
                                  'এই মাস',
                                ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: EkColors.muted,
                                ),
                              ),
                              Text(
                                '${EkLanguage.text('Spending', 'খরচ')}: ৳${summary.totalSpending.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LifeModule {
  const _LifeModule({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.page,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final Widget page;
}
