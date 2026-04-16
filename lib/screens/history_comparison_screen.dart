import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../utils/currency_helper.dart';

class HistoryComparisonScreen extends StatefulWidget {
  final List<TransactionModel> transactions;
  final String baseCurrency;

  const HistoryComparisonScreen({
    super.key,
    required this.transactions,
    required this.baseCurrency,
  });

  @override
  State<HistoryComparisonScreen> createState() => _HistoryComparisonScreenState();
}

class _HistoryComparisonScreenState extends State<HistoryComparisonScreen> {
  double thisMonthExpense = 0;
  double thisMonthIncome = 0;
  double lastMonthExpense = 0;
  double lastMonthIncome = 0;

  Map<String, double> thisMonthCat = {};
  Map<String, double> lastMonthCat = {};

  late DateTime now;
  late DateTime lastMonthDate;

  @override
  void initState() {
    super.initState();
    now = DateTime.now();
    int currentMonth = now.month;
    int currentYear = now.year;

    int lastMonth = currentMonth == 1 ? 12 : currentMonth - 1;
    int lastMonthYear = currentMonth == 1 ? currentYear - 1 : currentYear;
    lastMonthDate = DateTime(lastMonthYear, lastMonth);

    _calculateData(currentMonth, currentYear, lastMonth, lastMonthYear);
  }

  void _calculateData(int cm, int cy, int lm, int ly) {
    for (var tx in widget.transactions) {
      if (tx.status != TransactionStatus.completed) continue;

      double amount = CurrencyHelper.convert(tx.amount, tx.currency, widget.baseCurrency);

      if (tx.date.month == cm && tx.date.year == cy) {
        if (tx.type == TransactionType.expense) {
          thisMonthExpense += amount;
          if (tx.category.isNotEmpty) {
            thisMonthCat[tx.category] = (thisMonthCat[tx.category] ?? 0) + amount;
          }
        } else if (tx.type == TransactionType.income) {
          thisMonthIncome += amount;
        }
      } else if (tx.date.month == lm && tx.date.year == ly) {
        if (tx.type == TransactionType.expense) {
          lastMonthExpense += amount;
          if (tx.category.isNotEmpty) {
            lastMonthCat[tx.category] = (lastMonthCat[tx.category] ?? 0) + amount;
          }
        } else if (tx.type == TransactionType.income) {
          lastMonthIncome += amount;
        }
      }
    }

    // Sort categories
    thisMonthCat = Map.fromEntries(
        thisMonthCat.entries.toList()..sort((e1, e2) => e2.value.compareTo(e1.value)));
  }

  String _formatAmount(double amount) {
    final symbol = CurrencyHelper.getSymbol(widget.baseCurrency);
    final formatter = NumberFormat('#,##0');
    return '$symbol${formatter.format(amount)}';
  }

  Widget _buildTrendChip(double current, double previous, {bool invertColor = false}) {
    if (previous == 0 && current == 0) {
      return const Text('-', style: TextStyle(color: Colors.grey, fontSize: 12));
    }
    if (previous == 0 && current > 0) {
      Color c = invertColor ? Colors.green : Colors.red;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text('+New', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    double diff = current - previous;
    double pct = (diff / previous) * 100;
    
    // For expenses: diff > 0 (more expense) is BAD (red). diff < 0 is GOOD (green).
    // If invertColor is true (for income): diff > 0 is GOOD (green). diff < 0 is BAD (red).
    bool isPositive = diff >= 0;
    Color chipColor;
    if (invertColor) {
      chipColor = isPositive ? Colors.green : Colors.red;
    } else {
      chipColor = isPositive ? Colors.red : Colors.green;
    }

    IconData icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    String sign = isPositive ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 2),
          Text(
            '$sign${pct.toStringAsFixed(1)}%',
            style: TextStyle(color: chipColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadlineBlock() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expense', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  _formatAmount(thisMonthExpense),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                _buildTrendChip(thisMonthExpense, lastMonthExpense),
                const SizedBox(height: 6),
                Text('Last: ${_formatAmount(lastMonthExpense)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade200),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Income', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  _formatAmount(thisMonthIncome),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                _buildTrendChip(thisMonthIncome, lastMonthIncome, invertColor: true),
                const SizedBox(height: 6),
                Text('Last: ${_formatAmount(lastMonthIncome)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChartSegment() {
    double maxY = [thisMonthIncome, lastMonthIncome, thisMonthExpense, lastMonthExpense].fold(0.0, (a, b) => a > b ? a : b);
    if (maxY == 0) maxY = 1000;
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 4),
              const Text('Last Mth', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(width: 16),
              Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 4),
              const Text('This Mth', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32, // Gives enough space at the bottom to prevent clipping
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            value.toInt() == 0 ? 'Income' : 'Expense',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(
                    x: 0,
                    barRods: [
                      BarChartRodData(toY: lastMonthIncome, color: Colors.grey.shade300, width: 22, borderRadius: BorderRadius.circular(4)),
                      BarChartRodData(toY: thisMonthIncome, color: Colors.blueAccent, width: 22, borderRadius: BorderRadius.circular(4)),
                    ],
                  ),
                  BarChartGroupData(
                    x: 1,
                    barRods: [
                      BarChartRodData(toY: lastMonthExpense, color: Colors.grey.shade300, width: 22, borderRadius: BorderRadius.circular(4)),
                      BarChartRodData(toY: thisMonthExpense, color: Colors.blueAccent, width: 22, borderRadius: BorderRadius.circular(4)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryComparison() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.category, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Leaderboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(DateFormat('MMM').format(now), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          if (thisMonthCat.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No expenses this month.', style: TextStyle(color: Colors.grey))),
            ),
          ...thisMonthCat.entries.take(5).map((entry) {
            String cat = entry.key;
            double amountThis = entry.value;
            double amountLast = lastMonthCat[cat] ?? 0;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Last Mth: ${_formatAmount(amountLast)}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatAmount(amountThis), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      _buildTrendChip(amountThis, amountLast),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String thisMonthStr = DateFormat('MMMM yyyy').format(now);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: Colors.blue.shade900,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('Time Machine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade900, Colors.blue.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comparing $thisMonthStr to last month', style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 20),
                  _buildHeadlineBlock(),
                  const SizedBox(height: 24),
                  _buildBarChartSegment(),
                  const SizedBox(height: 24),
                  _buildCategoryComparison(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
