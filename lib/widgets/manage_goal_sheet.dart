import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/ui_helpers.dart';

class ManageGoalSheet extends StatefulWidget {
  const ManageGoalSheet({super.key});

  @override
  State<ManageGoalSheet> createState() => _ManageGoalSheetState();
}

class _ManageGoalSheetState extends State<ManageGoalSheet> {
  late TextEditingController _goalController;
  int _daysInMonth = 30;
  String _selectedTag = 'Saving';

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _goalController = TextEditingController(
      text: settings.monthlySavingsGoal > 0 ? settings.monthlySavingsGoal.toStringAsFixed(0) : '',
    );
    _selectedTag = settings.savingsTag;
    
    final now = DateTime.now();
    _daysInMonth = _getDaysInMonth(now.year, now.month);
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 12) return 31;
    return DateTime(year, month + 1, 0).day;
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  void _saveGoal() {
    final val = double.tryParse(_goalController.text) ?? 0.0;
    if (val < 0) {
      UIHelpers.showAlertDialog(context, 'Invalid Amount', 'Goal cannot be negative.');
      return;
    }
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    settings.setMonthlySavingsGoal(val);
    settings.setSavingsTag(_selectedTag);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Savings goal updated successfully!'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseCurrency = Provider.of<SettingsProvider>(context).baseCurrency;
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 24,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Set Monthly Goal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Challenge yourself! Set a target of how much you want to save this month. We will break it down into a daily target to keep you on track.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _goalController,
            decoration: InputDecoration(
              labelText: 'Monthly Savings Goal ($baseCurrency)',
              prefixIcon: const Icon(Icons.flag),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (val) {
              setState(() {}); // Trigger rebuild to update daily breakdown preview
            },
          ),
          const SizedBox(height: 16),
          
          DropdownButtonFormField<String>(
            value: Provider.of<SettingsProvider>(context).activeTags.contains(_selectedTag) ? _selectedTag : null,
            decoration: InputDecoration(
              labelText: 'Linked Tag to Track',
              prefixIcon: const Icon(Icons.local_offer),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: Provider.of<SettingsProvider>(context).activeTags.map((t) {
              return DropdownMenuItem(value: t, child: Text(t));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedTag = val);
            },
            hint: const Text('Select a tag'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8.0, left: 4),
            child: Text('Only expenses/incomes with this exact tag will be counted towards your monthly progress.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 16),
          
          // Live preview of Daily Breakdown
          Builder(
            builder: (context) {
              final val = double.tryParse(_goalController.text) ?? 0.0;
              if (val > 0) {
                final dailyGoal = val / _daysInMonth;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insights, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'That means you need to save $baseCurrency ${dailyGoal.toStringAsFixed(2)} every day this month ($_daysInMonth days) to reach your goal.',
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }
          ),
          
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _saveGoal,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Goal', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }
}
