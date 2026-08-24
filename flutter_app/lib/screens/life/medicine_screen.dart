import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';

class MedicineScreen extends StatelessWidget {
  const MedicineScreen({super.key});

  Future<void> _manualAdd(
    BuildContext context, {
    String initialName = '',
    String initialInstruction = '',
  }) async {
    final name = TextEditingController(text: initialName);
    final instruction = TextEditingController(text: initialInstruction);
    final schedule = TextEditingController();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm medicine'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Verify every field yourself. OCR may be wrong and EkThikana does not provide medical advice.',
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Medicine name')),
              const SizedBox(height: 10),
              TextField(
                controller: instruction,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Dose / instruction'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: schedule,
                decoration: const InputDecoration(labelText: 'Time / schedule'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('I confirmed — Save')),
        ],
      ),
    );

    if (save == true && name.text.trim().isNotEmpty) {
      await FirestoreService.addOwnerRecord('medicines', {
        'name': name.text.trim(),
        'instruction': instruction.text.trim(),
        'schedule': schedule.text.trim(),
        'confirmedByUser': true,
      });
    }

    name.dispose();
    instruction.dispose();
    schedule.dispose();
  }

  Future<void> _scan(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!context.mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final result = await ApiService.prescriptionOcr(
        bytes: bytes,
        fileName: file.name,
      );

      if (context.mounted) Navigator.pop(context);
      if (!context.mounted) return;

      final text = result['rawText']?.toString() ?? '';
      final instruction = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('OCR result — review only'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: SelectableText(text.isEmpty ? 'No text detected.' : text)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, text),
              child: const Text('Use as draft'),
            ),
          ],
        ),
      );

      if (instruction != null && context.mounted) {
        await _manualAdd(context, initialInstruction: instruction);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.maybePop(context);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine'),
        actions: [
          IconButton(
            tooltip: 'Scan prescription',
            onPressed: () => _scan(context),
            icon: const Icon(Icons.document_scanner_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _manualAdd(context),
        icon: const Icon(Icons.add),
        label: const Text('Medicine'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('medicines'),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No medicine records yet.\nUse + to add manually or the scanner icon to extract text from a prescription.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.medication_outlined),
                  title: Text(data['name']?.toString() ?? ''),
                  subtitle: Text(
                    [
                      data['instruction']?.toString() ?? '',
                      data['schedule']?.toString() ?? '',
                    ].where((e) => e.trim().isNotEmpty).join('\n'),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: 'Delete medicine record?',
                        message: 'This only removes the EkThikana record.',
                        action: 'Delete',
                      );
                      if (ok) await doc.reference.delete();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
