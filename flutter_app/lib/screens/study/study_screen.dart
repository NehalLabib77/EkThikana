import 'package:flutter/material.dart';

import 'academic_structure_screen.dart';
import 'community_screen.dart';
import 'materials_screen.dart';
import 'notes_screen.dart';
import 'saved_materials_screen.dart';
import 'study_plan_screen.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StudyItem('My notes', Icons.note_alt_outlined, const NotesScreen()),
      _StudyItem('My materials', Icons.picture_as_pdf_outlined, const MaterialsScreen()),
      _StudyItem('Community Library', Icons.public_outlined, const CommunityScreen()),
      _StudyItem('Saved Library', Icons.bookmark_outline, const SavedMaterialsScreen()),
      _StudyItem('Semesters & subjects', Icons.account_tree_outlined, const AcademicStructureScreen()),
      _StudyItem('Study plan', Icons.auto_graph_outlined, const StudyPlanScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Study')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              leading: CircleAvatar(child: Icon(item.icon)),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => item.page),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StudyItem {
  _StudyItem(this.title, this.icon, this.page);
  final String title;
  final IconData icon;
  final Widget page;
}
