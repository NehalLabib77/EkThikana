import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  List<dynamic>? items;
  bool busy = false;

  Future<void> load() async {
    setState(() => busy = true);
    try {
      items = await ApiService.studyPlan();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) => Scaffold(
        appBar: AppBar(
          title: Text(EkLanguage.text('Study Plan', 'স্টাডি প্ল্যান')),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF1EDFF), Color(0xFFFFFFFF)]),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE5DFFF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: EkColors.purple, shape: BoxShape.circle),
                    child: const Icon(Icons.auto_graph, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(EkLanguage.text('Deadline-based study plan', 'ডেডলাইনভিত্তিক পড়ার পরিকল্পনা'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text(
                          EkLanguage.text(
                            'EkThikana ranks unfinished tasks by deadline urgency. It does not generate questions or MCQs.',
                            'EkThikana অসমাপ্ত কাজ ডেডলাইন অনুযায়ী সাজায়। এটি প্রশ্ন বা MCQ তৈরি করে না।',
                          ),
                          style: const TextStyle(color: EkColors.muted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : load,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt),
              label: Text(EkLanguage.text(busy ? 'Building plan…' : 'Build My Plan', busy ? 'প্ল্যান তৈরি হচ্ছে…' : 'আমার প্ল্যান তৈরি করুন')),
            ),
            const SizedBox(height: 20),
            if (items == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Text(EkLanguage.text('Tap Build to create a plan from your unfinished tasks.', 'অসমাপ্ত কাজ থেকে পরিকল্পনা তৈরি করতে Build চাপুন।'), textAlign: TextAlign.center, style: const TextStyle(color: EkColors.muted)),
                ),
              )
            else if (items!.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(EkLanguage.text('No unfinished tasks found.', 'কোনো অসমাপ্ত কাজ পাওয়া যায়নি।'))),
                ),
              )
            else ...[
              SectionHeader(title: Text(EkLanguage.text('Priority order', 'অগ্রাধিকারের ক্রম'))),
              const SizedBox(height: 8),
              for (var i = 0; i < items!.length; i++) ...[
                Builder(builder: (context) {
                  final item = Map<String, dynamic>.from(items![i] as Map);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: EkColors.lavender, foregroundColor: EkColors.purple, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
                      title: Text(item['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(item['dueAt']?.toString() ?? EkLanguage.text('No deadline', 'ডেডলাইন নেই'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
