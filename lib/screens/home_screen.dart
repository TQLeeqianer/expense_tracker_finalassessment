import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/transaction_model.dart';
import '../widgets/add_transaction_sheet.dart';
import '../utils/currency_helper.dart';

enum TimeRange { today, thisWeek, thisMonth, thisYear, allTime }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TimeRange _selectedRange = TimeRange.thisMonth;
  String _baseCurrency = 'USD';
  
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

  bool _isObscured = false;

  String _formatAmount(double amount, {String? currency, bool showDecimals = true}) {
    if (_isObscured) return '****';
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
        // A simple "This Week" (last 7 days logic) or actual ISO week.
        // We'll use within last 7 days and not in the future for safety.
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

  @override
  Widget build(BuildContext context) {
    final Color blueColor = Theme.of(context).colorScheme.primary; 
    
    // Get user email
    final user = Provider.of<AuthService>(context).user;
    final String email = user?.email ?? 'user@example.com';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: StreamBuilder<List<TransactionModel>>(
        stream: FirestoreService().getTransactionsStream(),
        builder: (context, snapshot) {
          
          if (snapshot.hasError) {
             return Center(child: Text("Error: \${snapshot.error}"));
          }
          
          double totalNetWorth = 0;
          double currentIncome = 0;
          double currentExpense = 0;
          double currentTransfer = 0;
          
          final allTransactions = (snapshot.data ?? []).where((t) => !t.isDeleted).toList();
          final List<TransactionModel> filteredTransactions = [];
          final Map<String, double> walletBalances = {};
          final Map<String, double> expenseByCategory = {};
          
          for (var t in allTransactions) {
            double convertedAmt = CurrencyHelper.convert(t.amount, t.currency, _baseCurrency);
            
            // Unconditionally calculate Total Net Worth (All Time) and Wallets from valid transactions
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

            // Apply selected time filter for Cashflow and transaction list
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
                final query = _searchQuery.trim().toLowerCase();
                passSearch = t.title.toLowerCase().contains(query) ||
                             t.tags.any((tag) => tag.toLowerCase().contains(query));
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
              // TOP BLUE COLLAPSIBLE SECTION
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
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.white24,
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Hi, Developer!',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: () async {
                                await Provider.of<AuthService>(context, listen: false).signOut();
                              },
                              icon: const Icon(Icons.logout, color: Colors.white),
                            )
                          ],
                        ),
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
                                  onTap: () => setState(() => _isObscured = !_isObscured),
                                  child: Icon(
                                    _isObscured ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.white70,
                                    size: 18,
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
                              items: CurrencyHelper.availableCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _baseCurrency = val);
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
                            _buildActionItem(Icons.swap_horiz, 'Transfer', () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => const AddTransactionSheet(initialType: TransactionType.transfer),
                              );
                            }),
                            _buildActionItem(Icons.qr_code_scanner, 'Scan', () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt Scanning coming soon!')));
                            }),
                            _buildActionItem(Icons.pie_chart, 'Report', () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advanced Reporting coming soon!')));
                            }),
                            _buildActionItem(Icons.history, 'History', _showFilterSheet),
                            _buildActionItem(Icons.grid_view, 'More', () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('More Features coming soon!')));
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
              
              // BOTTOM CARDS SECTION
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
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Cashflow',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<TimeRange>(
                                value: _selectedRange,
                                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                style: const TextStyle(fontSize: 14, color: Colors.black87),
                                items: TimeRange.values.map((TimeRange range) {
                                  return DropdownMenuItem<TimeRange>(
                                    value: range,
                                    child: Text(_getRangeLabel(range)),
                                  );
                                }).toList(),
                                onChanged: (TimeRange? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _selectedRange = newValue;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
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
                              bgColor: Colors.white,
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
                              bgColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildWalletCard(
                              context: context,
                              icon: Icons.swap_horiz,
                              title: 'Transfer',
                              amount: _formatAmount(currentTransfer, showDecimals: false),
                              iconColor: Colors.orange,
                              bgColor: Colors.white,
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
                      
                      _buildSectionHeader('Transactions', 'See All'),
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
                          return const SizedBox(height: 80); // Added FAB safety boundary
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
          // OPEN ADD TRANSACTION BOTTOM SHEET
          showModalBottomSheet(
            context: context,
            isScrollControlled: true, 
            backgroundColor: Colors.transparent,
            builder: (ctx) => const AddTransactionSheet(),
          );
        },
        backgroundColor: blueColor,
        child: const Icon(Icons.add, color: Colors.white),
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

  Widget _buildWalletsList(Map<String, double> wallets) {
    if (wallets.isEmpty) {
      return const Text("No wallets found. Add a transaction first!", style: TextStyle(color: Colors.grey));
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: wallets.entries.map((entry) {
          return Container(
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
                const Icon(Icons.account_balance_wallet, color: Colors.blueAccent),
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
  }) {
    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: iconColor.withOpacity(0.1),
                child: Icon(icon, color: iconColor),
              ),
              const Icon(Icons.more_horiz, color: Colors.grey),
            ],
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
    );
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
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 50,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
      
      legendItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(category, style: const TextStyle(color: Colors.black87, fontSize: 14))),
              Text('${CurrencyHelper.getSymbol(_baseCurrency)}${NumberFormat("#,##0.00").format(amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          SizedBox(
            height: 200,
            child: Stack(
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
                        '${CurrencyHelper.getSymbol(_baseCurrency)}${NumberFormat("#,##0").format(total)}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Column(children: legendItems),
        ],
      ),
    );
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

    // Swipe to delete capability
    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
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
        FirestoreService().deleteTransaction(t.id);
      },
      child: InkWell(
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
                        spacing: 6,
                        runSpacing: 6,
                        children: t.tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500)),
                        )).toList(),
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

  void _showFilterSheet() {
    final TextEditingController minAmtCtrl = TextEditingController(text: _filterMinAmount?.toString() ?? '');
    final TextEditingController maxAmtCtrl = TextEditingController(text: _filterMaxAmount?.toString() ?? '');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Advanced Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Custom Date Range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final DateTimeRange? picked = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                      initialDateRange: _filterStartDate != null && _filterEndDate != null 
                                          ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
                                          : null,
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        _filterStartDate = picked.start;
                                        _filterEndDate = picked.end;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.date_range, size: 18),
                                  label: Text(_filterStartDate != null && _filterEndDate != null
                                      ? '${DateFormat('MM/dd').format(_filterStartDate!)} - ${DateFormat('MM/dd').format(_filterEndDate!)}'
                                      : 'Select Range'),
                                ),
                              ),
                              if (_filterStartDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.red),
                                  onPressed: () => setModalState(() { _filterStartDate = null; _filterEndDate = null; }),
                                )
                            ],
                          ),
                          const SizedBox(height: 16),

                          const Text('Amount Range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: minAmtCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Min', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money, size: 16)),
                                  onChanged: (val) => _filterMinAmount = double.tryParse(val),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: maxAmtCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Max', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money, size: 16)),
                                  onChanged: (val) => _filterMaxAmount = double.tryParse(val),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          const Text('Account / Wallet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _filterAccount.isEmpty ? null : _filterAccount,
                            hint: const Text('All Accounts'),
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: ['Cash', 'Bank', 'Credit Card', 'AmBank', 'Maybank'] 
                                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (val) {
                              setModalState(() => _filterAccount = val ?? '');
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          const Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _filterCategory.isEmpty ? null : _filterCategory,
                            hint: const Text('All Categories'),
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: ['Shopping', 'Food', 'Transport', 'Entertainment', 'Salary', 'Investment', 'Transfer'] 
                                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (val) {
                              setModalState(() => _filterCategory = val ?? '');
                            },
                          ),
                          const SizedBox(height: 16),

                          const Text('Transaction Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<TransactionType>(
                            value: _filterType,
                            hint: const Text('All Types'),
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: TransactionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(),
                            onChanged: (val) {
                              setModalState(() => _filterType = val);
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          const Text('Sort By', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _currentSortMode,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: ['Newest', 'Oldest', 'Highest Amount', 'Lowest Amount']
                                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (val) {
                              setModalState(() => _currentSortMode = val ?? 'Newest');
                            },
                          ),
                          const SizedBox(height: 24),
                        ]
                      )
                    )
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _filterCategory = '';
                              _filterType = null;
                              _filterStartDate = null;
                              _filterEndDate = null;
                              _filterMinAmount = null;
                              _filterMaxAmount = null;
                              _filterAccount = '';
                              _currentSortMode = 'Newest';
                            });
                            setState(() {
                              _filterCategory = '';
                              _filterType = null;
                              _filterStartDate = null;
                              _filterEndDate = null;
                              _filterMinAmount = null;
                              _filterMaxAmount = null;
                              _filterAccount = '';
                              _currentSortMode = 'Newest';
                            });
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text('Reset', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {}); // Apply state change broadly across board
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blueAccent),
                          child: const Text('Apply Filters', style: TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }
        );
      },
    );
  }
}
