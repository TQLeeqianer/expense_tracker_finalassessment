import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class ManageCategoriesSheet extends StatefulWidget {
  const ManageCategoriesSheet({super.key});

  @override
  State<ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<ManageCategoriesSheet> {
  void _showAddCategoryDialog(BuildContext context, SettingsProvider provider, bool isExpense) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isExpense ? 'New Expense Category' : 'New Income Category'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Category Name',
            hintText: isExpense ? 'e.g. Pets, Tax, Crypto' : 'e.g. Bonus, Sold Items',
            prefixIcon: Icon(isExpense ? Icons.money_off : Icons.attach_money),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                if (isExpense) {
                  provider.addExpenseCategory(nameController.text.trim());
                } else {
                  provider.addIncomeCategory(nameController.text.trim());
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final expenseCategories = settingsProvider.expenseCategories;
    final incomeCategories = settingsProvider.incomeCategories;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manage Categories',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              children: [
                // Expense Section
                Row(
                  children: [
                    Icon(Icons.arrow_circle_up, color: Colors.red.shade400),
                    const SizedBox(width: 8),
                    const Text('Expense Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ...expenseCategories.map((evt) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  title: Text(evt, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () {
                      if (expenseCategories.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must have at least one expense category.')));
                        return;
                      }
                      settingsProvider.removeExpenseCategory(evt);
                    },
                  ),
                )),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  leading: const Icon(Icons.add, color: Colors.blue),
                  title: const Text('Add Expense Category', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  onTap: () => _showAddCategoryDialog(context, settingsProvider, true),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(),
                ),

                // Income Section
                Row(
                  children: [
                    Icon(Icons.arrow_circle_down, color: Colors.green.shade400),
                    const SizedBox(width: 8),
                    const Text('Income Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ...incomeCategories.map((evt) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  title: Text(evt, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () {
                      if (incomeCategories.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must have at least one income category.')));
                        return;
                      }
                      settingsProvider.removeIncomeCategory(evt);
                    },
                  ),
                )),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                  leading: const Icon(Icons.add, color: Colors.blue),
                  title: const Text('Add Income Category', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  onTap: () => _showAddCategoryDialog(context, settingsProvider, false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
