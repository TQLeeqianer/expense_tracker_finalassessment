import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import '../models/transaction_model.dart';
import 'profile_screen.dart';
import 'filter_screen.dart';
import 'see_all_screen.dart';
import 'scan_screen.dart';
import '../widgets/add_transaction_sheet.dart';
import '../screens/atm_locator_screen.dart';
import '../widgets/ai_analysis_sheet.dart';
import '../widgets/bank_statement_sheet.dart';
import '../widgets/app_notification_overlay.dart';
import '../utils/currency_helper.dart';
import '../utils/ui_helpers.dart';
import '../screens/history_comparison_screen.dart';

enum TimeRange { today, thisWeek, thisMonth, thisYear, allTime }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TimeRange _selectedRange = TimeRange.thisMonth;
  String get _baseCurrency => Provider.of<SettingsProvider>(context).baseCurrency;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterCategory = '';
  TransactionType? _filterType;

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  double? _filterMinAmount;
  double? _filterMaxAmount;
  String _filterAccount = '';
  String _currentSortMode = 'Newest';
  bool _isCheckingGoal = false;
  final Set<String> _selectedIds = {};
  bool _isMultiSelectMode = false;
  bool _showPieChart = true;

  String _formatAmount(double amount, {String? currency, bool showDecimals = true}) {
    final isPrivacyMode = Provider.of<SettingsProvider>(context).isPrivacyModeEnabled;
    if (isPrivacyMode) return '****';
    final curParams = currency ?? _baseCurrency;
    final formatStr = showDecimals ? "#,##0.00" : "#,##0";
    return '${CurrencyHelper.getSymbol(curParams)} ${NumberFormat(formatStr).format(amount)}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isWithinRange(DateTime date, TimeRange range) {
    final now = DateTime.now();
    switch (range) {
      case TimeRange.today:
        return date.year == now.year && date.month == now.month && date.day == now.day;
      case TimeRange.thisWeek:
        final difference = now.difference(date).inDays;
        return difference >= 0 && difference <= 7;
      case TimeRange.thisMonth:
        return date.year == now.year && date.month == now.month;
      case TimeRange.thisYear:
        return date.year == now.year;
      case TimeRange.allTime:
        return true;
    }
  }

  String _getRangeLabel(TimeRange range) {
    switch (range) {
      case TimeRange.today: return 'Today';
      case TimeRange.thisWeek: return 'This Week';
      case TimeRange.thisMonth: return 'This Month';
      case TimeRange.thisYear: return 'This Year';
      case TimeRange.allTime: return 'All Time';
    }
  }

  void _handlePrivacyModeToggle() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.isPrivacyModeEnabled) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.privacy_tip, size: 48, color: Colors.blueAccent),
              SizedBox(height: 12),
              Text(
                'Enable Privacy Mode',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: const Text(
            'Your balances and amounts will be hidden. Tap the eye icon again to disable.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                settings.togglePrivacyMode();
              },
              child: const Text('Enable'),
            ),
          ],
        ),
      );
    } else {
      settings.togglePrivacyMode();
    }
  }

  void _showGoalReminderDialog(double dailyGoal, double todaySaved, double deficit, String currency, String targetTag) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.track_changes, size: 48, color: Colors.orange),
            SizedBox(height: 12),
            Text(
              'Savings Target Alert',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          "Your monthly goal breaks down to $currency ${dailyGoal.toStringAsFixed(0)} per day for your [#$targetTag] fund.\n\nToday, you have secured $currency ${todaySaved.toStringAsFixed(0)}.\n\nYou're short by $currency ${deficit.toStringAsFixed(0)}. Keep pushing!",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 15),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkDailyGoalReminder(List<TransactionModel> allTransactions, SettingsProvider settings) async {
    if (_isCheckingGoal) return;
    _isCheckingGoal = true;

    if (settings.monthlySavingsGoal <= 0) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastShown = prefs.getString('lastGoalReminderDate');
      
      // Exactly once per day
      if (lastShown == todayStr) return;

      final today = DateTime.now();
      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      final dailyGoal = settings.monthlySavingsGoal / daysInMonth;
      final targetTag = settings.savingsTag;

      double todaySavings = 0.0;
      for (var t in allTransactions) {
        if (t.status != TransactionStatus.failed && t.status != TransactionStatus.refunded &&
            t.date.year == today.year && t.date.month == today.month && t.date.day == today.day) {
          
          if (t.tags.contains(targetTag)) {
            double amt = CurrencyHelper.convert(t.amount, t.currency, settings.baseCurrency);
            // Treat expenses, incomes, or transfers purely as absolute saved value if they are tagged for Savings
            todaySavings += amt.abs(); 
          }
        }
      }

      if (todaySavings < dailyGoal) {
        final deficit = dailyGoal - todaySavings;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showGoalReminderDialog(dailyGoal, todaySavings, deficit, settings.baseCurrency, targetTag);
          }
        });
        await prefs.setString('lastGoalReminderDate', todayStr);
      }
    } catch (e) {
      debugPrint("Error checking goal logic: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color blueColor = Theme.of(context).colorScheme.primary;
    
    // Get user email
    final user = Provider.of<AuthService>(context).user;
    final String email = user?.email ?? 'user@example.com';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      bottomNavigationBar: _isMultiSelectMode
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: Colors.white,
                child: Row(
                  children: [
                    Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelMultiSelect,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: StreamBuilder<List<TransactionModel>>(
        stream: FirestoreService().getTransactionsStream(),
        builder: (context, snapshot) {
          
          if (snapshot.hasError) {
             return Center(child: Text("Error: ${snapshot.error}"));
          }
          
          double totalNetWorth = 0;
          double currentIncome = 0;
          double currentExpense = 0;
          double currentTransfer = 0;
          
          final allTransactions = (snapshot.data ?? []).where((t) => !t.isDeleted).toList();
          final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
          
          if (snapshot.connectionState == ConnectionState.active) {
            _checkDailyGoalReminder(allTransactions, settingsProvider);
          }
          final List<TransactionModel> filteredTransactions = [];
          
          final Map<String, double> walletBalances = Map.from(settingsProvider.wallets);
          
          // Seed the total net worth with the initial wallet balances
          for (var balance in walletBalances.values) {
            totalNetWorth += balance;
          }
          final Map<String, double> expenseByCategory = {};
          
          for (var t in allTransactions) {
            double convertedAmt = CurrencyHelper.convert(t.amount, t.currency, _baseCurrency);
            
            // Unconditionally calculate Total Net Worth
            if (t.status != TransactionStatus.failed && t.status != TransactionStatus.refunded) {

              if (t.type == TransactionType.expense) {
                totalNetWorth -= convertedAmt;
                if (t.fromAccount != null && t.fromAccount!.isNotEmpty) {
                  walletBalances[t.fromAccount!] = (walletBalances[t.fromAccount!] ?? 0) - convertedAmt;
                }
              } else if (t.type == TransactionType.income) {
                totalNetWorth += convertedAmt;
                if (t.toAccount != null && t.toAccount!.isNotEmpty) {
                  walletBalances[t.toAccount!] = (walletBalances[t.toAccount!] ?? 0) + convertedAmt;
                }
              } else if (t.type == TransactionType.transfer) {
                if (t.fromAccount != null && t.fromAccount!.isNotEmpty) {
                  walletBalances[t.fromAccount!] = (walletBalances[t.fromAccount!] ?? 0) - convertedAmt;
                }
                if (t.toAccount != null && t.toAccount!.isNotEmpty) {
                  walletBalances[t.toAccount!] = (walletBalances[t.toAccount!] ?? 0) + convertedAmt;
                }
              }
            }

            bool passTime = true;
            if (_filterStartDate != null && _filterEndDate != null) {
              passTime = t.date.isAfter(_filterStartDate!.subtract(const Duration(days: 1))) && 
                         t.date.isBefore(_filterEndDate!.add(const Duration(days: 1)));
            } else {
              passTime = _isWithinRange(t.date, _selectedRange);
            }

            if (passTime) {
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
              bool passCat = _filterCategory.isEmpty || t.category == _filterCategory;
              bool passType = _filterType == null || t.type == _filterType;
              bool passMinAmt = _filterMinAmount == null || t.amount >= _filterMinAmount!;
              bool passMaxAmt = _filterMaxAmount == null || t.amount <= _filterMaxAmount!;
              bool passAccount = _filterAccount.isEmpty || (t.fromAccount == _filterAccount) || (t.toAccount == _filterAccount);

              if (passSearch && passCat && passType && passMinAmt && passMaxAmt && passAccount) {
                filteredTransactions.add(t);
                
                if (t.status != TransactionStatus.failed && t.status != TransactionStatus.refunded) {
                  if (t.type == TransactionType.expense) {
                    currentExpense += convertedAmt;
                    if (t.category.isNotEmpty) {
                      expenseByCategory[t.category] = (expenseByCategory[t.category] ?? 0) + convertedAmt;
                    }
                  } else if (t.type == TransactionType.income) {
                    currentIncome += convertedAmt;
                  } else if (t.type == TransactionType.transfer) {
                    currentTransfer += convertedAmt;
                  }
                }
              }
            }
          }

          if (_currentSortMode == 'Newest') {
            filteredTransactions.sort((a, b) => b.date.compareTo(a.date));
          } else if (_currentSortMode == 'Oldest') {
            filteredTransactions.sort((a, b) => a.date.compareTo(b.date));
          } else if (_currentSortMode == 'Highest Amount') {
            filteredTransactions.sort((a, b) => b.amount.compareTo(a.amount));
          } else if (_currentSortMode == 'Lowest Amount') {
            filteredTransactions.sort((a, b) => a.amount.compareTo(b.amount));
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: blueColor,
                expandedHeight: 380,
                pinned: true,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 40),
                    decoration: BoxDecoration(
                      color: blueColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Consumer<SettingsProvider>(
                                    builder: (context, settings, child) {
                                      final imagePath = settings.profileImagePath;
                                      return CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.white24,
                                        backgroundImage: imagePath != null && imagePath.length > 500
                                            ? MemoryImage(base64Decode(imagePath))
                                            : null,
                                        child: (imagePath == null || imagePath.length <= 500)
                                            ? const Icon(Icons.person, color: Colors.white)
                                            : null,
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Consumer<AuthService>(
                                      builder: (context, auth, _) => Text(
                                        'Hi, ${auth.user?.displayName ?? 'Developer'}!',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ], // Closes inner Column children
                                ), // Closes inner Column
                              ], // Closes inner Row children
                            ), // Closes inner Row
                          ], // Closes outer Row children
                        ), // Closes outer Row
                      const SizedBox(height: 24),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Total Net Worth (All Time)',
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _handlePrivacyModeToggle,
                                  child: Consumer<SettingsProvider>(
                                    builder: (context, provider, child) => Icon(
                                      provider.isPrivacyModeEnabled ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            DropdownButton<String>(
                              value: _baseCurrency,
                              dropdownColor: Colors.blue.shade700,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              underline: const SizedBox(),
                              items: Provider.of<SettingsProvider>(context).activeCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  Provider.of<SettingsProvider>(context, listen: false).setBaseCurrency(val);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatAmount(totalNetWorth),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildActionItem(Icons.qr_code_scanner, 'Scan', () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
                            }),
                            _buildActionItem(Icons.auto_awesome, 'AI Insight', () {
                              final Map<String, dynamic> summaryData = {
                                'currency': settingsProvider.baseCurrency,
                                'totalNetWorth': totalNetWorth,
                                'timeRange': _selectedRange.name,
                                'totalIncome': currentIncome,
                                'totalExpense': currentExpense,
                                'expenseByCategory': expenseByCategory,
                              };
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => AiAnalysisSheet(summaryData: summaryData),
                              );
                            }),
                            _buildActionItem(Icons.history, 'History', () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => HistoryComparisonScreen(
                                    transactions: allTransactions,
                                    baseCurrency: settingsProvider.baseCurrency,
                                  ),
                                ),
                              );
                            }),
                            _buildActionItem(Icons.map, 'Map', () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const ATMLocatorScreen()));
                            }),
                            _buildActionItem(Icons.picture_as_pdf, 'PDF Sync', () async {
                              final result = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const BankStatementSheet(),
                              );
                              if (result == true && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Statements Imported Successfully! 🎉', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
                                );
                              }
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Container(
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                  ),
                ),
              ),
              
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('My Wallets', ''),
                      const SizedBox(height: 16),
                      _buildWalletsList(walletBalances),
                      const SizedBox(height: 32),
                      
                      const Text(
                        'Cashflow',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: TimeRange.values.map((range) {
                            final isSelected = _selectedRange == range;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(_getRangeLabel(range)),
                                selected: isSelected,
                                showCheckmark: false,
                                selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                labelStyle: TextStyle(
                                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade600,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                                backgroundColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                elevation: 0,
                                pressElevation: 0,
                                onSelected: (bool selected) {
                                  if (selected) {
                                    setState(() => _selectedRange = range);
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildWalletCard(
                              context: context,
                              icon: Icons.arrow_downward,
                              title: 'Income',
                              amount: _formatAmount(currentIncome, showDecimals: false),
                              iconColor: Colors.blue,
                              bgColor: _filterType == TransactionType.income ? Colors.blue.shade50 : Colors.white,
                              onTap: () {
                                setState(() {
                                  _filterType = _filterType == TransactionType.income ? null : TransactionType.income;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildWalletCard(
                              context: context,
                              icon: Icons.arrow_upward,
                              title: 'Spending',
                              amount: _formatAmount(currentExpense, showDecimals: false),
                              iconColor: Colors.green,
                              bgColor: _filterType == TransactionType.expense ? Colors.green.shade50 : Colors.white,
                              onTap: () {
                                setState(() {
                                  _filterType = _filterType == TransactionType.expense ? null : TransactionType.expense;
                                });
                              },
                            ),
                          ),

                        ],
                      ),
                      const SizedBox(height: 32),
                      
                      if (expenseByCategory.isNotEmpty) ...[
                        _buildSectionHeader('Expense Breakdown', ''),
                        const SizedBox(height: 16),
                        _buildExpenseChart(expenseByCategory),
                        const SizedBox(height: 32),
                      ],
                      
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search transactions or tags...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            suffixIcon: IconButton(
                              icon: Stack(
                                children: [
                                  Icon(Icons.filter_list, color: (_filterCategory.isNotEmpty || _filterType != null || _filterStartDate != null || _filterMinAmount != null || _filterMaxAmount != null || _filterAccount.isNotEmpty || _currentSortMode != 'Newest') ? Colors.blue : Colors.grey),
                                  if (_filterCategory.isNotEmpty || _filterType != null || _filterStartDate != null || _filterMinAmount != null || _filterMaxAmount != null || _filterAccount.isNotEmpty || _currentSortMode != 'Newest')
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                                    ),
                                ],
                              ),
                              onPressed: _showFilterSheet,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SeeAllScreen(
                                filterCategory: _filterCategory,
                                filterType: _filterType,
                                filterStartDate: _filterStartDate,
                                filterEndDate: _filterEndDate,
                                filterMinAmount: _filterMinAmount,
                                filterMaxAmount: _filterMaxAmount,
                                filterAccount: _filterAccount,
                                sortMode: _currentSortMode,
                              ),
                            ),
                          );
                        },
                        child: _buildSectionHeader('Transactions', 'See All'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))
              else if (filteredTransactions.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text("No transactions yet.", style: TextStyle(color: Colors.grey)),
                    )
                  )
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == filteredTransactions.length) {
                          return const SizedBox(height: 80); 
                        }
                        return _buildTransactionTile(filteredTransactions[index]);
                      },
                      childCount: filteredTransactions.length + 1,
                    ),
                  ),
                ),
            ],
          );
        }
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final overlay = Overlay.of(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => const AddTransactionSheet(),
          ).then((saved) {
            if (mounted && saved == true) {
              AppNotification.show(
                overlay,
                'Transaction saved successfully!',
                icon: Icons.check_circle,
                color: Colors.green,
              );
            }
          });
        },
        backgroundColor: blueColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showComingSoonDialog(BuildContext context, String title, String message, IconData icon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String actionText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          actionText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _showGenericGoalReminderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.savings, size: 48, color: Colors.orange),
            SizedBox(height: 12),
            Text(
              'Savings Reminder',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: const Text(
          "Hey! You haven't saved any money today yet. Don't forget to record your savings!",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  void _showWalletOptions(BuildContext context, String walletName, double currentBalance) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(walletName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit Wallet Name'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditWalletDialog(context, walletName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Wallet'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteWalletDialog(context, walletName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditWalletDialog(BuildContext context, String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Wallet Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'New Wallet Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                final newName = controller.text.trim();
                Provider.of<SettingsProvider>(context, listen: false).editWallet(oldName, newName);
                FirestoreService().reassignWalletTransactions(oldName, newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteWalletDialog(BuildContext context, String walletName) {
    if (walletName == 'Default Wallet') {
      UIHelpers.showAlertDialog(context, 'Action Denied', 'Cannot delete the Default Wallet.');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Wallet'),
        content: Text('Are you sure you want to delete "$walletName"? This will move all its transactions to "Default Wallet".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Provider.of<SettingsProvider>(context, listen: false).deleteWallet(walletName);
              FirestoreService().reassignWalletTransactions(walletName, 'Default Wallet');
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletsList(Map<String, double> wallets) {
    if (wallets.isEmpty) {
      return const Text("No wallets found. Add a transaction first!", style: TextStyle(color: Colors.grey));
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: wallets.entries.map((entry) {
          return GestureDetector(
            onTap: () => _showWalletOptions(context, entry.key, entry.value),
            child: Container(
              width: 140,
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
                      const Icon(Icons.more_vert, color: Colors.grey, size: 18),
                    ]
                  ),
                const SizedBox(height: 12),
                Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatAmount(entry.value),
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
  }

  Widget _buildWalletCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String amount,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: iconColor.withOpacity(0.1),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildExpenseChart(Map<String, double> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    
    final List<Color> chartColors = [
      Colors.redAccent, Colors.blueAccent, Colors.greenAccent, 
      Colors.orangeAccent, Colors.purpleAccent, Colors.teal,
      Colors.pinkAccent, Colors.amber,
    ];
    
    double total = data.values.fold(0, (sum, item) => sum + item);
    int colorIndex = 0;

    List<PieChartSectionData> sections = [];
    List<Widget> legendItems = [];

    data.forEach((category, amount) {
      final color = chartColors[colorIndex % chartColors.length];
      final percentage = (amount / total) * 100;
      
      sections.add(
        PieChartSectionData(
          color: color,
          value: amount,
          showTitle: percentage >= 3, // Only show big labels on the chart to keep it clean
          titlePositionPercentageOffset: 1.5,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 55, 
          titleStyle: const TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: Colors.black87,
          ),
        ),
      );
      
      legendItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text('$category (${percentage.toStringAsFixed(1)}%)', style: const TextStyle(color: Colors.black87, fontSize: 14))),
              Text(_formatAmount(amount, showDecimals: true), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        )
      );
      
      colorIndex++;
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(_showPieChart ? Icons.bar_chart : Icons.pie_chart, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _showPieChart = !_showPieChart;
                  });
                },
              ),
            ],
          ),
          SizedBox(
            height: 200,
            child: _showPieChart 
              ? Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 60,
                        sections: sections,
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Total', style: TextStyle(color: Colors.grey, fontSize: 14)),
                          Text(
                            _formatAmount(total, showDecimals: false), 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: data.values.isNotEmpty ? data.values.reduce((a, b) => a > b ? a : b) * 1.2 : 100,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            if (value.toInt() < 0 || value.toInt() >= data.length) return const SizedBox();
                            final str = data.keys.toList()[value.toInt()];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(str.substring(0, str.length > 3 ? 3 : str.length), style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: data.entries.toList().asMap().entries.map((entry) {
                      int idx = entry.key;
                      double amount = entry.value.value;
                      return BarChartGroupData(
                        x: idx,
                        barRods: [
                          BarChartRodData(
                            toY: amount,
                            color: chartColors[idx % chartColors.length],
                            width: 20,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
          ),
          const SizedBox(height: 24),
          Column(children: legendItems),
        ],
      ),
    );
  }

  void _enterMultiSelect(String id) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _isMultiSelectMode = false;
    });
  }

  void _cancelMultiSelect() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await FirestoreService().deleteTransaction(id);
    }
    setState(() {
      _isMultiSelectMode = false;
      _selectedIds.clear();
    });
  }

  Widget _buildTransactionTile(TransactionModel t) {
    Color iconColor;
    Color bgColor;
    IconData icon;
    String prefix;
    
    switch (t.type) {
      case TransactionType.income:
        iconColor = Colors.green;
        bgColor = Colors.green.withOpacity(0.1);
        icon = Icons.work_outline;
        prefix = "+ ";
        break;
      case TransactionType.expense:
        iconColor = Colors.red;
        bgColor = Colors.red.withOpacity(0.1);
        icon = Icons.shopping_bag;
        prefix = "- ";
        break;
      case TransactionType.transfer:
        iconColor = Colors.blue;
        bgColor = Colors.blue.withOpacity(0.1);
        icon = Icons.swap_horiz;
        prefix = "";
        break;
    }

    Widget statusIndicator = const SizedBox.shrink();
    if (t.status == TransactionStatus.pending) {
      statusIndicator = const Tooltip(
        message: 'Pending',
        child: Icon(Icons.access_time, color: Colors.orange, size: 16),
      );
    } else if (t.status == TransactionStatus.failed) {
      statusIndicator = const Tooltip(
        message: 'Failed',
        child: Icon(Icons.error_outline, color: Colors.red, size: 16),
      );
    } else if (t.status == TransactionStatus.refunded) {
      statusIndicator = const Tooltip(
        message: 'Refunded',
        child: Icon(Icons.replay, color: Colors.purple, size: 16),
      );
    }

    return Dismissible(
      key: Key(t.id),
      direction: _isMultiSelectMode ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        FirestoreService().deleteLinkedTransaction(t);
      },
      child: InkWell(
        onTap: () {
          if (_isMultiSelectMode) {
            _toggleSelect(t.id);
          } else {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => AddTransactionSheet(existingTransaction: t),
            );
          }
        },
        onLongPress: () {
          if (!_isMultiSelectMode) _enterMultiSelect(t.id);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _selectedIds.contains(t.id) ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: _selectedIds.contains(t.id) ? Border.all(color: Colors.blue, width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_isMultiSelectMode) ...[
              Checkbox(
                value: _selectedIds.contains(t.id),
                onChanged: (_) => _toggleSelect(t.id),
                activeColor: Colors.blue,
              ),
              const SizedBox(width: 8),
            ],
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: bgColor,
                  child: Icon(icon, color: iconColor),
                ),
                if (t.status != TransactionStatus.completed)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: statusIndicator,
                    ),
                  ),
                if (t.linkedTransactionId != null)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.link, size: 12, color: Colors.blue),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: t.status == TransactionStatus.failed || t.status == TransactionStatus.refunded 
                          ? TextDecoration.lineThrough 
                          : null,
                      color: t.status == TransactionStatus.failed ? Colors.grey : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (t.type == TransactionType.transfer && t.fromAccount != null && t.toAccount != null)
                    Text(
                      '${t.fromAccount} → ${t.toAccount}',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    )
                  else
                    Text(
                      DateFormat('MMM dd, yyyy - hh:mm a').format(t.date),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  if (t.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: t.tags.map((tag) {
                          Color chipBg;
                          Color chipText;
                          switch (t.type) {
                            case TransactionType.expense:
                              chipBg = Colors.red.shade100; chipText = Colors.red.shade700; break;
                            case TransactionType.income:
                              chipBg = Colors.green.shade100; chipText = Colors.green.shade700; break;
                            case TransactionType.transfer:
                              chipBg = Colors.blue.shade100; chipText = Colors.blue.shade700; break;
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
                            child: Text('#$tag', style: TextStyle(fontSize: 10, color: chipText, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$prefix${_formatAmount(t.amount, currency: t.currency)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: t.status == TransactionStatus.failed || t.status == TransactionStatus.refunded ? Colors.grey : iconColor,
                decoration: t.status == TransactionStatus.failed || t.status == TransactionStatus.refunded 
                    ? TextDecoration.lineThrough 
                    : null,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showFilterSheet() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => FilterScreen(
          initialCategory: _filterCategory,
          initialType: _filterType,
          initialStartDate: _filterStartDate,
          initialEndDate: _filterEndDate,
          initialMinAmount: _filterMinAmount,
          initialMaxAmount: _filterMaxAmount,
          initialAccount: _filterAccount,
          initialSortMode: _currentSortMode,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _filterCategory = result['filterCategory'] as String;
        _filterType = result['filterType'] as TransactionType?;
        _filterStartDate = result['filterStartDate'] as DateTime?;
        _filterEndDate = result['filterEndDate'] as DateTime?;
        _filterMinAmount = result['filterMinAmount'] as double?;
        _filterMaxAmount = result['filterMaxAmount'] as double?;
        _filterAccount = result['filterAccount'] as String;
        _currentSortMode = result['currentSortMode'] as String;
      });
    }
  }
}
