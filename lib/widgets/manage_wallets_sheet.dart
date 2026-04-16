import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_helper.dart';
import 'package:intl/intl.dart';

class ManageWalletsSheet extends StatefulWidget {
  const ManageWalletsSheet({super.key});

  @override
  State<ManageWalletsSheet> createState() => _ManageWalletsSheetState();
}

class _ManageWalletsSheetState extends State<ManageWalletsSheet> {
  void _showAddWalletDialog(BuildContext context, SettingsProvider provider) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Wallet Name',
                hintText: 'e.g. Maybank, Cash, PayPal',
                prefixIcon: Icon(Icons.account_balance_wallet),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Initial Balance',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(CurrencyHelper.getSymbol(provider.baseCurrency), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                final balance = double.tryParse(balanceController.text.trim()) ?? 0.0;
                provider.addWallet(nameController.text.trim(), balance);
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
    final wallets = settingsProvider.wallets;

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
                  'Manage Wallets',
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
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: wallets.length,
              separatorBuilder: (ctx, idx) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                String walletName = wallets.keys.elementAt(index);
                double initialBalance = wallets.values.elementAt(index);
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                  ),
                  title: Text(walletName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  subtitle: const Text('Initial Balance'),
                  trailing: Text(
                    '${CurrencyHelper.getSymbol(settingsProvider.baseCurrency)} ${NumberFormat("#,##0.00").format(initialBalance)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                );
              },
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddWalletDialog(context, settingsProvider),
                icon: const Icon(Icons.add),
                label: const Text('Add New Wallet'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
