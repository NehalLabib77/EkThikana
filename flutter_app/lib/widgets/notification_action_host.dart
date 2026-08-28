import 'package:flutter/material.dart';

import '../core/navigation.dart';
import '../core/ui.dart';
import '../screens/life/medicine_screen.dart';
import '../services/financial_service.dart';
import '../services/notification_service.dart';

class NotificationActionHost extends StatefulWidget {
  const NotificationActionHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<NotificationActionHost> createState() => _NotificationActionHostState();
}

class _NotificationActionHostState extends State<NotificationActionHost> {
  @override
  void initState() {
    super.initState();
    NotificationService.medicineAction.addListener(_handle);
  }

  @override
  void dispose() {
    NotificationService.medicineAction.removeListener(_handle);
    super.dispose();
  }

  Future<void> _handle() async {
    final action = NotificationService.medicineAction.value;
    if (action == null) return;
    NotificationService.medicineAction.value = null;

    // Give AuthGate/Navigator a moment to settle after a cold launch.
    BuildContext? context;
    for (var i = 0; i < 20; i++) {
      context = AppNavigation.navigatorKey.currentContext;
      if (context != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (context == null || !context.mounted) return;

    // Deep-link to the Medicine screen first so the user lands on a real
    // medicine context before any confirm/skip dialog. Payload is untouched.
    final nav = AppNavigation.navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute(builder: (_) => const MedicineScreen()),
      );
      // Let the new route mount so its dialogs/snackbars use the new context.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      context = AppNavigation.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
    }

    if (action.action == 'skip') {
      try {
        await FinancialService.recordMedicineDose(
          medicineId: action.medicineId,
          medicineName: action.medicineName,
          scheduledTime: action.hhmm,
          date: DateTime.now(),
          status: 'skipped',
          unitPriceSnapshot: action.unitPrice,
          unit: action.unit,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dose marked skipped.')),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
      return;
    }

    if (action.action != 'taken') return;

    final quantity = TextEditingController(
      text: _format(action.quantityPerDose),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm medicine taken'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.medicineName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('Scheduled: ${_format(action.quantityPerDose)} ${action.unit}'),
            const SizedBox(height: 12),
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Actual quantity taken',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Taken'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final actual = double.tryParse(quantity.text.trim()) ?? 0;
        await FinancialService.recordMedicineDose(
          medicineId: action.medicineId,
          medicineName: action.medicineName,
          scheduledTime: action.hhmm,
          date: DateTime.now(),
          status: 'taken',
          actualQuantityTaken: actual,
          unitPriceSnapshot: action.unitPrice,
          unit: action.unit,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Taken recorded • ৳${(actual * action.unitPrice).toStringAsFixed(2)}',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }
    quantity.dispose();
  }

  static String _format(double value) =>
      value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) => widget.child;
}
