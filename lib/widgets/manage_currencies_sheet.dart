import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_helper.dart';

class ManageCurrenciesSheet extends StatelessWidget {
  const ManageCurrenciesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final activeCurrencies = settingsProvider.activeCurrencies;
    final allCurrencies = CurrencyHelper.availableCurrencies;

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
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ]
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Manage Currencies',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            color: Colors.blue.shade50,
            child: const Text(
              'Select the currencies you frequently use. These will appear in your default currency and transaction dropdowns.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              itemCount: allCurrencies.length,
              separatorBuilder: (ctx, idx) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final currency = allCurrencies[index];
                final symbol = CurrencyHelper.getSymbol(currency);
                final isActive = activeCurrencies.contains(currency);
                final isDefault = currency == settingsProvider.baseCurrency;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isActive ? Colors.blue.shade100 : Colors.grey.shade200,
                    child: Text(
                      symbol,
                      style: TextStyle(
                        color: isActive ? Colors.blue.shade800 : Colors.black54,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(currency, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Default', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                  onTap: () {
                    settingsProvider.setBaseCurrency(currency);
                  },
                  trailing: Switch(
                    value: isActive,
                    activeColor: Colors.blue,
                    onChanged: (val) {
                      settingsProvider.toggleCurrency(currency, val);
                    },
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
