import 'package:flutter/material.dart';

import '../tasks/tasks_screen.dart';
import 'medicine_screen.dart';
import 'record_module_screen.dart';

class LifeScreen extends StatelessWidget {
  const LifeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modules = [
      _Module('Tasks', Icons.task_alt, const TasksScreen()),
      _Module('Medicine', Icons.medication_outlined, const MedicineScreen()),
      _Module(
        'BazarBuddy',
        Icons.shopping_basket_outlined,
        const RecordModuleScreen(
          title: 'BazarBuddy',
          collection: 'grocery_items',
          itemLabel: 'Item',
          detailsLabel: 'Quantity / note',
        ),
      ),
      _Module(
        'FamilyHub',
        Icons.family_restroom,
        const RecordModuleScreen(
          title: 'FamilyHub',
          collection: 'family_records',
          itemLabel: 'Record title',
          detailsLabel: 'Details',
        ),
      ),
      _Module(
        'RentMate',
        Icons.home_outlined,
        const RecordModuleScreen(
          title: 'RentMate',
          collection: 'rent_records',
          itemLabel: 'Rent record',
          detailsLabel: 'Amount / due date / note',
        ),
      ),
      _Module(
        'CommuteBD',
        Icons.directions_bus_outlined,
        const RecordModuleScreen(
          title: 'CommuteBD',
          collection: 'saved_locations',
          itemLabel: 'Place / route',
          detailsLabel: 'Location / transport note',
        ),
      ),
      _Module(
        'Wellness',
        Icons.favorite_border,
        const RecordModuleScreen(
          title: 'Wellness',
          collection: 'wellness_records',
          itemLabel: 'Entry',
          detailsLabel: 'Sleep / water / activity / note',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Daily life')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 150,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: modules.length,
        itemBuilder: (context, i) {
          final m = modules[i];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => m.page),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(m.icon, size: 34),
                    const Spacer(),
                    Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const Text('Open module'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Module {
  _Module(this.title, this.icon, this.page);
  final String title;
  final IconData icon;
  final Widget page;
}
