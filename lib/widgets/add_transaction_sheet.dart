import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import '../utils/currency_helper.dart';

class AddTransactionSheet extends StatefulWidget {
  final TransactionModel? existingTransaction;
  final TransactionType? initialType;

  const AddTransactionSheet({super.key, this.existingTransaction, this.initialType});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _fromAccountController = TextEditingController();
  final _toAccountController = TextEditingController();
  final _tagsController = TextEditingController();
  
  TransactionType _selectedType = TransactionType.expense;
  TransactionStatus _selectedStatus = TransactionStatus.completed;
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Shopping';
  String _selectedCurrency = 'USD';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.initialType != null) {
      _selectedType = widget.initialType!;
      _selectedCategory = widget.initialType == TransactionType.transfer ? 'Transfer' : _currentCategories.first;
    }

    if (widget.existingTransaction != null) {
      final t = widget.existingTransaction!;
      _titleController.text = t.title;
      _amountController.text = t.amount.toString();
      _fromAccountController.text = t.fromAccount ?? '';
      _toAccountController.text = t.toAccount ?? '';
      _tagsController.text = t.tags.join(', ');
      
      _selectedType = t.type;
      _selectedStatus = t.status;
      _selectedDate = t.date;
      _selectedCategory = t.type == TransactionType.transfer ? 'Transfer' : t.category;
      _selectedCurrency = t.currency;
    }
  }

  List<String> get _currentCategories {
    if (_selectedType == TransactionType.expense) {
      return ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Other'];
    } else if (_selectedType == TransactionType.income) {
      return ['Salary', 'Freelance', 'Investment', 'Gift', 'Other'];
    } else {
      return ['Transfer'];
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _submit() async {
    // Basic validation
    if (_titleController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title and amount')),
      );
      return;
    }
    
    if (_selectedType == TransactionType.expense && _fromAccountController.text.isEmpty) {
      _fromAccountController.text = 'Default Wallet';
    }
    if (_selectedType == TransactionType.income && _toAccountController.text.isEmpty) {
      _toAccountController.text = 'Default Wallet';
    }

    if (_selectedType == TransactionType.transfer && 
        (_fromAccountController.text.isEmpty || _toAccountController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill both accounts for transfers')),
      );
      return;    
    }

    setState(() => _isLoading = true);

    try {
      final inputTags = _tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      
      final transaction = TransactionModel(
        id: widget.existingTransaction?.id ?? '', // Use existing ID if updating
        title: _titleController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        currency: _selectedCurrency,
        category: _selectedType == TransactionType.transfer ? 'Transfer' : _selectedCategory,
        date: _selectedDate,
        tags: inputTags,
        type: _selectedType,
        status: _selectedStatus,
        fromAccount: (_selectedType == TransactionType.transfer || _selectedType == TransactionType.expense) 
            ? _fromAccountController.text.trim() : null,
        toAccount: (_selectedType == TransactionType.transfer || _selectedType == TransactionType.income) 
            ? _toAccountController.text.trim() : null,
      );

      if (widget.existingTransaction != null) {
        await FirestoreService().updateTransaction(transaction.id, transaction);
      } else {
        await FirestoreService().addTransaction(transaction);
      }

      if (mounted) {
        Navigator.pop(context); // Close the BottomSheet on success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24, // Keep it above keyboard
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existingTransaction != null ? 'Edit Record' : 'Add New Record',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            DropdownButtonFormField<TransactionType>(
              value: _selectedType,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: TransactionType.expense, child: Text('Expense')),
                DropdownMenuItem(value: TransactionType.income, child: Text('Income')),
                DropdownMenuItem(value: TransactionType.transfer, child: Text('Transfer')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedType = val;
                    if (_selectedType == TransactionType.expense) {
                      _selectedCategory = 'Shopping';
                    } else if (_selectedType == TransactionType.income) {
                      _selectedCategory = 'Salary';
                    } else {
                      _selectedCategory = 'Transfer';
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<TransactionStatus>(
              value: _selectedStatus,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: TransactionStatus.completed, child: Text('Completed')),
                DropdownMenuItem(value: TransactionStatus.pending, child: Text('Pending')),
                DropdownMenuItem(value: TransactionStatus.failed, child: Text('Failed')),
                DropdownMenuItem(value: TransactionStatus.refunded, child: Text('Refunded')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedStatus = val);
              },
            ),
            const SizedBox(height: 16),
            
            if (_selectedType != TransactionType.transfer) ...[
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _currentCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 16),
            ],
  
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Starbucks Coffee, AWS Hosting',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _selectedCurrency,
                    decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
                    items: CurrencyHelper.availableCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCurrency = val);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  "${_selectedDate.toLocal()}".split(' ')[0],
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated, e.g. trip, software)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 16),
            
            if (_selectedType == TransactionType.transfer || _selectedType == TransactionType.expense) ...[
              TextField(
                controller: _fromAccountController,
                decoration: InputDecoration(
                  labelText: _selectedType == TransactionType.transfer ? 'From Account (e.g. Bank)' : 'Account (e.g. Cash)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.account_balance),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (_selectedType == TransactionType.transfer || _selectedType == TransactionType.income) ...[
              TextField(
                controller: _toAccountController,
                decoration: InputDecoration(
                  labelText: _selectedType == TransactionType.transfer ? 'To Account (e.g. Cash)' : 'Account (e.g. Bank)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.account_balance_wallet),
                ),
              ),
              const SizedBox(height: 16),
            ],
  
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)
                            ),
                          ),
                          onPressed: _submit,
                          child: Text(widget.existingTransaction != null ? 'Update Record' : 'Save Record', style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                      if (widget.existingTransaction != null) ...[
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              setState(() => _isLoading = true);
                              try {
                                await FirestoreService().deleteTransaction(widget.existingTransaction!.id);
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  setState(() => _isLoading = false);
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
