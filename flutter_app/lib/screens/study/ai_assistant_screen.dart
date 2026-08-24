import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../search/universal_search_screen.dart';
import 'materials_screen.dart';
import 'notes_screen.dart';
import 'study_plan_screen.dart';

class AiAssistantScreen extends StatelessWidget {
  const AiAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, __) {
        final actions = <_AiAction>[
          _AiAction(Icons.summarize_outlined, const Color(0xFF6751F5), 'Summarize Note', 'নোট সংক্ষেপ করুন', 'Open a note and use AI tools', 'নোট খুলে AI টুল ব্যবহার করুন', () => _go(context, const NotesScreen())),
          _AiAction(Icons.psychology_alt_outlined, const Color(0xFF2585FF), 'Explain This Topic', 'বিষয় সহজভাবে ব্যাখ্যা করুন', 'Understand study content clearly', 'পড়ার বিষয় সহজে বুঝুন', () => _go(context, const NotesScreen())),
          _AiAction(Icons.auto_fix_high_outlined, const Color(0xFFE7447D), 'Clean My Note', 'আমার নোট গুছিয়ে দিন', 'Improve structure without changing meaning', 'অর্থ না বদলে নোট গুছিয়ে নিন', () => _go(context, const NotesScreen())),
          _AiAction(Icons.key_outlined, const Color(0xFF3A74E8), 'Extract Key Topics', 'মূল বিষয় বের করুন', 'Find the important topics in your note', 'নোটের গুরুত্বপূর্ণ বিষয়গুলো বের করুন', () => _go(context, const NotesScreen())),
          _AiAction(Icons.picture_as_pdf_outlined, const Color(0xFFFF8D2E), 'Ask This PDF', 'এই PDF সম্পর্কে জিজ্ঞাসা করুন', 'Open a PDF and ask from its content', 'PDF খুলে তার বিষয়বস্তু থেকে প্রশ্ন করুন', () => _go(context, const MaterialsScreen())),
          _AiAction(Icons.event_note_outlined, const Color(0xFF21AF7A), 'Plan My Study', 'পড়াশোনার পরিকল্পনা করুন', 'Prioritize unfinished tasks by deadline', 'অসমাপ্ত কাজ সময় অনুযায়ী সাজান', () => _go(context, const StudyPlanScreen())),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(EkLanguage.text('AI Study Assistant', 'AI স্টাডি সহকারী')),
            actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF2EEFF), Color(0xFFFFFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE4DEFF)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(color: EkColors.purple, shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(EkLanguage.text('How can I help you study?', 'পড়াশোনায় কীভাবে সাহায্য করতে পারি?'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          const SizedBox(height: 5),
                          Text(EkLanguage.text('Choose a focused tool below. EkThikana does not generate MCQs or automatic quizzes.', 'নিচের নির্দিষ্ট টুল বেছে নিন। EkThikana MCQ বা স্বয়ংক্রিয় কুইজ তৈরি করে না।'), style: const TextStyle(color: EkColors.muted, fontSize: 12, height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final action in actions) ...[
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: action.onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: action.color.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
                            child: Icon(action.icon, color: action.color),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(EkLanguage.text(action.en, action.bn), style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(EkLanguage.text(action.enSub, action.bnSub), style: const TextStyle(color: EkColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: EkColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
              ],
              const SizedBox(height: 6),
              TextField(
                readOnly: true,
                onTap: () => _go(context, const UniversalSearchScreen(student: true)),
                decoration: InputDecoration(
                  hintText: EkLanguage.text('Search your study content…', 'আপনার পড়ার বিষয় খুঁজুন…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: const Icon(Icons.arrow_circle_right, color: EkColors.purple),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _AiAction {
  _AiAction(this.icon, this.color, this.en, this.bn, this.enSub, this.bnSub, this.onTap);
  final IconData icon;
  final Color color;
  final String en;
  final String bn;
  final String enSub;
  final String bnSub;
  final VoidCallback onTap;
}
