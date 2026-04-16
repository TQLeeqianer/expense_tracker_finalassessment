import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import '../models/transaction_model.dart';

class BankStatementSheet extends StatefulWidget {
  const BankStatementSheet({super.key});

  @override
  State<BankStatementSheet> createState() => _BankStatementSheetState();
}

class _BatchItem {
  bool isSelected = true;
  double amount;
  String currency;
  String type;
  String title;
  String category;
  DateTime date;

  _BatchItem.fromScanResult(ScanResult rs, String baseCurrency)
      : amount = rs.amount ?? 0.0,
        currency = rs.currency ?? baseCurrency,
        type = rs.type ?? 'expense',
        title = rs.title ?? 'Transaction',
        category = rs.category ?? 'Other',
        date = rs.date ?? DateTime.now();
}

class _BankStatementSheetState extends State<BankStatementSheet> {
  bool _isLoading = false;
  String? _loadingMessage;
  List<_BatchItem>? _extractedItems;
  String? _selectedWallet;

  Future<void> _pickAndAnalyzePdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      setState(() {
        _isLoading = true;
        _loadingMessage = 'Uploading statement...\nAI is interpreting data...';
      });

      final baseCurrency = Provider.of<SettingsProvider>(context, listen: false).baseCurrency;
      final results = await GeminiService().analyzeBankStatementPdf(result.files.single.bytes!);

      setState(() {
        _extractedItems = results.map((r) => _BatchItem.fromScanResult(r, baseCurrency)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('PDF Parse Error: $e');
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _importSelected() async {
    if (_selectedWallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a Wallet first!'), backgroundColor: Colors.orange));
      return;
    }

    final toImport = _extractedItems?.where((e) => e.isSelected).toList() ?? [];
    if (toImport.isEmpty) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Importing ${toImport.length} records...';
    });

    try {
      final fs = FirestoreService();
      final txBatch = <TransactionModel>[];
      
      for (var item in toImport) {
        final tx = TransactionModel(
          id: '',
          title: item.title,
          amount: item.amount,
          date: item.date,
          type: item.type == 'expense' ? TransactionType.expense : TransactionType.income,
          category: item.category,
          fromAccount: item.type == 'expense' ? _selectedWallet : null,
          toAccount: item.type == 'income' ? _selectedWallet : null,
          currency: item.currency,
          tags: ['AI Statement'],
        );
        txBatch.add(tx);
      }
      
      await fs.addTransactionsBatch(txBatch);
      
      if (mounted) {
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      print('Import Error: $e');
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_loadingMessage ?? 'Processing...', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (_extractedItems != null) {
      return _buildReviewSheet();
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Import Bank Statement', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Text('Upload your monthly PDF statement from Maybank, CIMB, or others. AI will instantly extract all transactions for you.', style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
          const Spacer(),
          GestureDetector(
            onTap: _pickAndAnalyzePdf,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200, width: 2, style: BorderStyle.solid), // Actually dashed is ideal but solid is fine
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf, size: 40, color: Colors.blue),
                  SizedBox(height: 8),
                  Text('Tap to Select PDF File', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildReviewSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Review Transactions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Consumer<SettingsProvider>(
            builder: (context, settings, child) {
              final wallets = settings.wallets.keys.toList();
              if (_selectedWallet == null && wallets.isNotEmpty) _selectedWallet = wallets.first;
              return DropdownButtonFormField<String>(
                value: _selectedWallet,
                decoration: const InputDecoration(labelText: 'Import Into Wallet', border: OutlineInputBorder(), prefixIcon: Icon(Icons.account_balance_wallet)),
                items: wallets.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                onChanged: (v) => setState(() => _selectedWallet = v),
              );
            }
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _extractedItems!.length,
              itemBuilder: (context, index) {
                final item = _extractedItems![index];
                return CheckboxListTile(
                  value: item.isSelected,
                  onChanged: (val) => setState(() => item.isSelected = val ?? false),
                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${item.date.toString().substring(0,10)} • ${item.category}'),
                  secondary: SizedBox(
                    width: 85,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text('${item.type == 'expense' ? '-' : '+'}${item.amount.toStringAsFixed(2)} ${item.currency}', style: TextStyle(color: item.type == 'expense' ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF19326D),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _importSelected,
              child: Text('Import Selected (${_extractedItems!.where((e) => e.isSelected).length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
