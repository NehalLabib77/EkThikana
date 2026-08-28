import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../models/financial_transaction.dart';
import '../../services/monthly_money_service.dart';

class MonthlyMoneyScreen extends StatefulWidget {
  const MonthlyMoneyScreen({super.key});

  @override
  State<MonthlyMoneyScreen> createState() => _MonthlyMoneyScreenState();
}

class _MonthlyMoneyScreenState extends State<MonthlyMoneyScreen> {
  late DateTime _month;
  double? _budget;
  double? _remaining;
  List<FinancialTransactionModel> _txs = const [];
  bool _loading = false;
  bool _saving = false;

  final TextEditingController _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _refresh();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final b = await MonthlyMoneyService.getBudget(_month);
      final r = await MonthlyMoneyService.remaining(_month);
      final stream = MonthlyMoneyService.monthStream(_month);
      final first = await stream.first;
      if (!mounted) return;
      setState(() {
        _budget = b;
        _remaining = r;
        _txs = first;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveBudget() async {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v < 0) {
      showError(context, 'Enter a non-negative amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await MonthlyMoneyService.setBudget(_month, v);
      _amount.clear();
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _monthLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[_month.month - 1]} ${_month.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Money'),
        actions: [
          IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Month'),
                    subtitle: Text(_monthLabel),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Budget'),
                    subtitle: Text(_budget == null ? 'Not set' : _budget!.toStringAsFixed(2)),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Remaining'),
                    subtitle: Text(
                      _remaining == null ? '—' : _remaining!.toStringAsFixed(2),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: (_remaining ?? 0) < 0 ? Colors.red : Colors.green[800],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Set budget',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _saveBudget,
                      child: const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Confirmed expenses (${_txs.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Divider(),
                if (_txs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No confirmed expenses this month.'),
                  )
                else
                  ..._txs.take(50).map((tx) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_long),
                        title: Text(tx.title),
                        subtitle: Text(tx.category),
                        trailing: Text('-${tx.amount.toStringAsFixed(2)}'),
                      )),
              ],
            ),
    );
  }
}
