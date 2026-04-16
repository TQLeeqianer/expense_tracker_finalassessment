import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../providers/settings_provider.dart';

/// Full-page filter screen. Pop returns a Map with updated filter values.
/// Keys: filterCategory (String), filterType (TransactionType?),
///       filterStartDate (DateTime?), filterEndDate (DateTime?),
///       filterMinAmount (double?), filterMaxAmount (double?),
///       filterAccount (String), currentSortMode (String)
class FilterScreen extends StatefulWidget {
  final String initialCategory;
  final TransactionType? initialType;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final double? initialMinAmount;
  final double? initialMaxAmount;
  final String initialAccount;
  final String initialSortMode;

  const FilterScreen({
    super.key,
    this.initialCategory = '',
    this.initialType,
    this.initialStartDate,
    this.initialEndDate,
    this.initialMinAmount,
    this.initialMaxAmount,
    this.initialAccount = '',
    this.initialSortMode = 'Newest',
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen>
    with SingleTickerProviderStateMixin {
  late String _filterCategory;
  late TransactionType? _filterType;
  late DateTime? _filterStartDate;
  late DateTime? _filterEndDate;
  late double? _filterMinAmount;
  late double? _filterMaxAmount;
  late String _filterAccount;
  late String _currentSortMode;

  final TextEditingController _minAmtCtrl = TextEditingController();
  final TextEditingController _maxAmtCtrl = TextEditingController();

  bool _showThisWeekPanel = false;
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _filterCategory = widget.initialCategory;
    _filterType = widget.initialType;
    _filterStartDate = widget.initialStartDate;
    _filterEndDate = widget.initialEndDate;
    _filterMinAmount = widget.initialMinAmount;
    _filterMaxAmount = widget.initialMaxAmount;
    _filterAccount = widget.initialAccount;
    _currentSortMode = widget.initialSortMode;

    _minAmtCtrl.text = _filterMinAmount?.toString() ?? '';
    _maxAmtCtrl.text = _filterMaxAmount?.toString() ?? '';

    _panelController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _panelSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _minAmtCtrl.dispose();
    _maxAmtCtrl.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _selectThisWeek() {
    final now = DateTime.now();
    setState(() {
      _filterStartDate = now.subtract(Duration(days: now.weekday - 1));
      _filterEndDate = now;
      _showThisWeekPanel = true;
    });
    _panelController.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _panelController.reverse().then((_) {
          if (mounted) setState(() => _showThisWeekPanel = false);
        });
      }
    });
  }

  void _applyAndPop() {
    Navigator.pop(context, {
      'filterCategory': _filterCategory,
      'filterType': _filterType,
      'filterStartDate': _filterStartDate,
      'filterEndDate': _filterEndDate,
      'filterMinAmount': _filterMinAmount,
      'filterMaxAmount': _filterMaxAmount,
      'filterAccount': _filterAccount,
      'currentSortMode': _currentSortMode,
    });
  }

  void _reset() {
    setState(() {
      _filterCategory = '';
      _filterType = null;
      _filterStartDate = null;
      _filterEndDate = null;
      _filterMinAmount = null;
      _filterMaxAmount = null;
      _filterAccount = '';
      _currentSortMode = 'Newest';
      _minAmtCtrl.clear();
      _maxAmtCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final walletNames = settingsProvider.wallets.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Filter Transactions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Range',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickChip('This Week', onTap: _selectThisWeek),
                    _buildQuickChip('This Month', onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _filterStartDate = DateTime(now.year, now.month, 1);
                        _filterEndDate = now;
                      });
                    }),
                    _buildQuickChip('This Year', onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _filterStartDate = DateTime(now.year, 1, 1);
                        _filterEndDate = now;
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  'Custom Date Range',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            initialDateRange: _filterStartDate != null && _filterEndDate != null
                                ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
                                : null,
                          );
                          if (picked != null) {
                            setState(() {
                              _filterStartDate = picked.start;
                              _filterEndDate = picked.end;
                            });
                          }
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          _filterStartDate != null && _filterEndDate != null
                              ? '${DateFormat('MM/dd').format(_filterStartDate!)} \u2013 ${DateFormat('MM/dd').format(_filterEndDate!)}'
                              : 'Select Range',
                        ),
                      ),
                    ),
                    if (_filterStartDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () => setState(() {
                          _filterStartDate = null;
                          _filterEndDate = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  'Amount Range',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Min',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money, size: 16),
                        ),
                        onChanged: (val) => _filterMinAmount = double.tryParse(val),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _maxAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Max',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money, size: 16),
                        ),
                        onChanged: (val) => _filterMaxAmount = double.tryParse(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text(
                  'Account / Wallet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterAccount.isEmpty ? null : _filterAccount,
                  hint: const Text('All Accounts'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: walletNames
                      .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                      .toList(),
                  onChanged: (val) => setState(() => _filterAccount = val ?? ''),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterCategory.isEmpty ? null : _filterCategory,
                  hint: const Text('All Categories'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    'Shopping', 'Food', 'Transport', 'Utilities',
                    'Entertainment', 'Health', 'Transfer', 'Other',
                    'Salary', 'Freelance', 'Investment', 'Gift',
                  ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) => setState(() => _filterCategory = val ?? ''),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Transaction Type',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TransactionType>(
                  value: _filterType,
                  hint: const Text('All Types'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: TransactionType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())))
                      .toList(),
                  onChanged: (val) => setState(() => _filterType = val),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Sort By',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _currentSortMode,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: ['Newest', 'Oldest', 'Highest Amount', 'Lowest Amount']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => _currentSortMode = val ?? 'Newest'),
                ),
              ],
            ),
          ),

          // This-Week slide-up confirmation panel
          if (_showThisWeekPanel)
            Positioned(
              bottom: 80,
              left: 24,
              right: 24,
              child: SlideTransition(
                position: _panelSlide,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This Week: ${_filterStartDate != null ? DateFormat('MMM dd').format(_filterStartDate!) : ''} \u2013 ${_filterEndDate != null ? DateFormat('MMM dd').format(_filterEndDate!) : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Apply button pinned at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFFF4F6F9),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ElevatedButton(
                onPressed: _applyAndPop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Apply Filters', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, {required VoidCallback onTap}) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
    );
  }
}
