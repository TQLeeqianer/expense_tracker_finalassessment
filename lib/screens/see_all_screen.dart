import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_helper.dart';
import '../widgets/add_transaction_sheet.dart';

class SeeAllScreen extends StatefulWidget {
  final String filterCategory;
  final TransactionType? filterType;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  final double? filterMinAmount;
  final double? filterMaxAmount;
  final String filterAccount;
  final String sortMode;

  const SeeAllScreen({
    super.key,
    this.filterCategory = '',
    this.filterType,
    this.filterStartDate,
    this.filterEndDate,
    this.filterMinAmount,
    this.filterMaxAmount,
    this.filterAccount = '',
    this.sortMode = 'Newest',
  });

  @override
  State<SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<SeeAllScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  bool _searchFocused = false;
  String _filterTag = '';

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _formatAmount(double amount, String baseCurrency) {
    final isPrivacyMode = Provider.of<SettingsProvider>(context, listen: false).isPrivacyModeEnabled;
    if (isPrivacyMode) return '****';
    return '${CurrencyHelper.getSymbol(baseCurrency)} ${NumberFormat('#,##0.00').format(amount)}';
  }

  Color _tagBgColor(TransactionType type) {
    switch (type) {
      case TransactionType.expense: return Colors.red.shade100;
      case TransactionType.income: return Colors.green.shade100;
      case TransactionType.transfer: return Colors.blue.shade100;
    }
  }

  Color _tagTextColor(TransactionType type) {
    switch (type) {
      case TransactionType.expense: return Colors.red.shade700;
      case TransactionType.income: return Colors.green.shade700;
      case TransactionType.transfer: return Colors.blue.shade700;
    }
  }

  bool _passesFilters(TransactionModel t) {
    bool passTime = true;
    if (widget.filterStartDate != null && widget.filterEndDate != null) {
      passTime = t.date.isAfter(widget.filterStartDate!.subtract(const Duration(days: 1))) &&
                 t.date.isBefore(widget.filterEndDate!.add(const Duration(days: 1)));
    }
    bool passSearch = true;
    if (_searchQuery.trim().isNotEmpty) {
      final rawQuery = _searchQuery.trim();
      final queryLower = rawQuery.toLowerCase();
      final isNegativeSearch = rawQuery.startsWith('-');
      final isPositiveSearch = rawQuery.startsWith('+');
      final queryStripped = rawQuery.replaceAll('+', '').replaceAll('-', '').trim();
      final queryNum = double.tryParse(queryStripped);
      bool amountMatch = false;
      if (queryNum != null) {
        if (isNegativeSearch) {
          amountMatch = t.amount == queryNum && t.type == TransactionType.expense;
        } else if (isPositiveSearch) {
          amountMatch = t.amount == queryNum && t.type == TransactionType.income;
        } else {
          amountMatch = t.amount == queryNum;
        }
      }
      passSearch = t.title.toLowerCase().contains(queryLower) ||
                   t.category.toLowerCase().contains(queryLower) ||
                   t.tags.any((tag) => tag.toLowerCase().contains(queryLower)) ||
                   amountMatch;
    }
    bool passCat = widget.filterCategory.isEmpty || t.category == widget.filterCategory;
    bool passType = widget.filterType == null || t.type == widget.filterType;
    bool passMin = widget.filterMinAmount == null || t.amount >= widget.filterMinAmount!;
    bool passMax = widget.filterMaxAmount == null || t.amount <= widget.filterMaxAmount!;
    bool passAcc = widget.filterAccount.isEmpty ||
                   t.fromAccount == widget.filterAccount ||
                   t.toAccount == widget.filterAccount;
    bool passTag = _filterTag.isEmpty || t.tags.contains(_filterTag);
    return passTime && passSearch && passCat && passType && passMin && passMax && passAcc && passTag;
  }

  List<TransactionModel> _sortTransactions(List<TransactionModel> list) {
    final sorted = List<TransactionModel>.from(list);
    switch (widget.sortMode) {
      case 'Oldest': sorted.sort((a, b) => a.date.compareTo(b.date)); break;
      case 'Highest Amount': sorted.sort((a, b) => b.amount.compareTo(a.amount)); break;
      case 'Lowest Amount': sorted.sort((a, b) => a.amount.compareTo(b.amount)); break;
      default: sorted.sort((a, b) => b.date.compareTo(a.date));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final baseCurrency = Provider.of<SettingsProvider>(context).baseCurrency;

    return PopScope(
      canPop: !_searchFocused,
      onPopInvoked: (didPop) {
        if (!didPop && _searchFocused) {
          _searchFocus.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          title: const Text('All Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () {
              if (_searchFocused) {
                _searchFocus.unfocus();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by title, category, tag, or amount…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            if (_searchFocused)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, size: 14, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Search mode active — swipe or tap back to exit', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Tag filter chips — built from all non-deleted transactions
            StreamBuilder<List<TransactionModel>>(
              stream: FirestoreService().getTransactionsStream(),
              builder: (context, snapshot) {
                final allTags = (snapshot.data ?? [])
                    .where((t) => !t.isDeleted)
                    .expand((t) => t.tags)
                    .toSet()
                    .toList()
                  ..sort();
                if (allTags.isEmpty) return const SizedBox.shrink();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All Tags'),
                        selected: _filterTag.isEmpty,
                        onSelected: (_) => setState(() => _filterTag = ''),
                        selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      ),
                      const SizedBox(width: 8),
                      ...allTags.map((tag) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text('#$tag'),
                          selected: _filterTag == tag,
                          onSelected: (_) => setState(() => _filterTag = _filterTag == tag ? '' : tag),
                          selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        ),
                      )),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

            Expanded(
              child: StreamBuilder<List<TransactionModel>>(
                stream: FirestoreService().getTransactionsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final all = (snapshot.data ?? []).where((t) => !t.isDeleted).toList();
                  final filtered = _sortTransactions(all.where(_passesFilters).toList());

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No transactions found.', style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _buildTile(filtered[i], baseCurrency),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(TransactionModel t, String baseCurrency) {
    Color iconColor;
    Color bgColor;
    IconData icon;
    String prefix;
    switch (t.type) {
      case TransactionType.income:
        iconColor = Colors.green; bgColor = Colors.green.withOpacity(0.1);
        icon = Icons.work_outline; prefix = '+ '; break;
      case TransactionType.expense:
        iconColor = Colors.red; bgColor = Colors.red.withOpacity(0.1);
        icon = Icons.shopping_bag; prefix = '- '; break;
      case TransactionType.transfer:
        iconColor = Colors.blue; bgColor = Colors.blue.withOpacity(0.1);
        icon = Icons.swap_horiz; prefix = ''; break;
    }

    final displayAmt = CurrencyHelper.convert(t.amount, t.currency, baseCurrency);

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => AddTransactionSheet(existingTransaction: t),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 24, backgroundColor: bgColor, child: Icon(icon, color: iconColor)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(DateFormat('MMM dd, yyyy').format(t.date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (t.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: t.tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _tagBgColor(t.type),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(fontSize: 10, color: _tagTextColor(t.type), fontWeight: FontWeight.w600),
                          ),
                        )).toList(),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$prefix${_formatAmount(displayAmt, baseCurrency)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}
