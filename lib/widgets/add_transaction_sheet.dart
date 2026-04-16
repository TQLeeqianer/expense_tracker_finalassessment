import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import 'package:provider/provider.dart';
import '../utils/ui_helpers.dart';

class AddTransactionSheet extends StatefulWidget {
  final TransactionModel? existingTransaction;
  final TransactionType? initialType;
  final double? initialAmount;
  final String? initialTitle;
  final String? initialCategory;
  final DateTime? initialDate;

  const AddTransactionSheet({
    super.key,
    this.existingTransaction,
    this.initialType,
    this.initialAmount,
    this.initialTitle,
    this.initialCategory,
    this.initialDate,
  });

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  List<String> _selectedTags = [];
  
  String? _selectedFromAccount;
  String? _selectedToAccount;
  
  TransactionType _selectedType = TransactionType.expense;
  TransactionStatus _selectedStatus = TransactionStatus.completed;
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Shopping';
  String _selectedCurrency = 'USD';
  bool _isLoading = false;
  bool _isTransferMode = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.initialType != null) {
      if (widget.initialType == TransactionType.transfer) {
        _isTransferMode = true;
        _selectedType = TransactionType.expense;
        _selectedCategory = 'Transfer';
      } else {
        _selectedType = widget.initialType!;
        _selectedCategory = _currentCategories.first;
      }
    }

    if (widget.existingTransaction != null) {
      final t = widget.existingTransaction!;
      _titleController.text = t.title;
      _amountController.text = t.amount.toString();
      _selectedFromAccount = t.fromAccount;
      _selectedToAccount = t.toAccount;
      _selectedTags = List.from(t.tags);

      _selectedType = t.type;
      _selectedStatus = t.status;
      _selectedDate = t.date;
      _selectedCategory = t.type == TransactionType.transfer ? 'Transfer' : t.category;
      _selectedCurrency = t.currency;
    }
    if (widget.initialAmount != null) {
      _amountController.text = widget.initialAmount!.toStringAsFixed(2);
    }
    if (widget.initialTitle != null) {
      _titleController.text = widget.initialTitle!;
    }
    if (widget.initialCategory != null && _currentCategories.contains(widget.initialCategory)) {
      _selectedCategory = widget.initialCategory!;
    }
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    }
    _titleController.addListener(() => setState(() {}));
    _amountController.addListener(() => setState(() {}));
  }

  List<String> get _currentCategories {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (_selectedType == TransactionType.expense) {
      final list = List<String>.from(settings.expenseCategories);
      if (_selectedCategory != 'Transfer' && !list.contains(_selectedCategory)) list.add(_selectedCategory);
      return list.toSet().toList();
    } else if (_selectedType == TransactionType.income) {
      final list = List<String>.from(settings.incomeCategories);
      if (_selectedCategory != 'Transfer' && !list.contains(_selectedCategory)) list.add(_selectedCategory);
      return list.toSet().toList();
    } else {
      return ['Transfer'];
    }
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    final amt = double.tryParse(_amountController.text.trim());
    if (amt == null || amt <= 0) return false;
    if (_isTransferMode &&
        (_selectedFromAccount == null || _selectedToAccount == null)) return false;
    return true;
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

  Future<void> _submitTransfer() async {
    setState(() => _isLoading = true);
    try {
      final amount = double.parse(_amountController.text.trim());
      final title = _titleController.text.trim();

      final expense = TransactionModel(
        id: '',
        title: title,
        amount: amount,
        currency: _selectedCurrency,
        category: 'Transfer',
        date: _selectedDate,
        tags: List.from(_selectedTags),
        type: TransactionType.expense,
        status: _selectedStatus,
        fromAccount: _selectedFromAccount,
      );

      final income = TransactionModel(
        id: '',
        title: title,
        amount: amount,
        currency: _selectedCurrency,
        category: 'Transfer',
        date: _selectedDate,
        tags: List.from(_selectedTags),
        type: TransactionType.income,
        status: _selectedStatus,
        toAccount: _selectedToAccount,
      );

      await FirestoreService().addLinkedTransactions(expense, income);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        UIHelpers.showAlertDialog(context, 'Save Failed', e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  void _submit() async {
    if (_selectedType == TransactionType.expense && _selectedFromAccount == null) {
      _selectedFromAccount = 'Default Wallet';
    }
    if (_selectedType == TransactionType.income && _selectedToAccount == null) {
      _selectedToAccount = 'Default Wallet';
    }

    setState(() => _isLoading = true);

    try {
      final inputTags = _selectedTags;
      
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
            ? _selectedFromAccount : null,
        toAccount: (_selectedType == TransactionType.transfer || _selectedType == TransactionType.income) 
            ? _selectedToAccount : null,
      );

      if (widget.existingTransaction != null) {
        await FirestoreService().updateTransaction(transaction.id, transaction);
      } else {
        await FirestoreService().addTransaction(transaction);
      }

      if (mounted) {
        Navigator.pop(context, true); // signals a real save
      }
    } catch (e) {
      if (mounted) {
        UIHelpers.showAlertDialog(context, 'Save Failed', e.toString());
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
            
            if (!_isTransferMode) ...[
              DropdownButtonFormField<TransactionType>(
                value: _selectedType,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: TransactionType.expense, child: Text('Expense')),
                  DropdownMenuItem(value: TransactionType.income, child: Text('Income')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedType = val;
                      final setCategories = _currentCategories;
                      _selectedCategory = setCategories.isNotEmpty ? setCategories.first : 'Other';
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            if (widget.existingTransaction == null) ...[
              InkWell(
                onTap: () {
                  setState(() {
                    _isTransferMode = !_isTransferMode;
                    if (_isTransferMode) {
                      _selectedFromAccount = null;
                      _selectedToAccount = null;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isTransferMode ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isTransferMode ? Colors.blue : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz,
                          color: _isTransferMode ? Colors.blue : Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transfer Between Accounts',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isTransferMode ? Colors.blue : Colors.black87,
                              ),
                            ),
                            Text(
                              'Creates linked expense + income pair',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isTransferMode,
                        onChanged: (v) {
                          setState(() {
                            _isTransferMode = v;
                            if (v) {
                              _selectedFromAccount = null;
                              _selectedToAccount = null;
                            }
                          });
                        },
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

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
              Builder(
                builder: (context) {
                  final cats = _currentCategories;
                  if (!cats.contains(_selectedCategory)) {
                    cats.add(_selectedCategory);
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  );
                }
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
                  child: Builder(
                    builder: (context) {
                      final currencies = Provider.of<SettingsProvider>(context).activeCurrencies.toSet().toList();
                      if (!currencies.contains(_selectedCurrency)) {
                        currencies.add(_selectedCurrency);
                      }
                      return DropdownButtonFormField<String>(
                        value: _selectedCurrency,
                        decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
                        items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCurrency = val);
                        },
                      );
                    }
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
            
            Consumer<SettingsProvider>(
              builder: (context, settings, child) {
                final globalTags = settings.activeTags;
                final displayTags = {...globalTags, ..._selectedTags}.toList();
                
                if (displayTags.isEmpty) return const SizedBox.shrink();
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Text('Tags', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: displayTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag),
                          selected: isSelected,
                          showCheckmark: false, // hide the default checkmark for cleaner look
                          selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          labelStyle: TextStyle(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          backgroundColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          onSelected: (bool selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            
            if (_isTransferMode || _selectedType == TransactionType.expense) ...[
              Consumer<SettingsProvider>(
                builder: (context, settings, child) {
                  final availableWallets = settings.wallets.keys.toList();
                  if (_selectedFromAccount != null && !availableWallets.contains(_selectedFromAccount)) {
                    availableWallets.add(_selectedFromAccount!);
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedFromAccount,
                    decoration: InputDecoration(
                      labelText: _isTransferMode ? 'From Account' : 'Account',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.account_balance),
                    ),
                    items: availableWallets.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedFromAccount = val);
                    },
                  );
                }
              ),
              const SizedBox(height: 16),
            ],
            
            if (_isTransferMode || _selectedType == TransactionType.income) ...[
              Consumer<SettingsProvider>(
                builder: (context, settings, child) {
                  final availableWallets = settings.wallets.keys.toList();
                  if (_selectedToAccount != null && !availableWallets.contains(_selectedToAccount)) {
                    availableWallets.add(_selectedToAccount!);
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedToAccount,
                    decoration: InputDecoration(
                      labelText: _isTransferMode ? 'To Account' : 'Account',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.account_balance_wallet),
                    ),
                    items: availableWallets.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedToAccount = val);
                    },
                  );
                }
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
                          onPressed: (_canSave && !_isLoading) ? (_isTransferMode ? _submitTransfer : _submit) : null,
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
                                await FirestoreService().deleteLinkedTransaction(widget.existingTransaction!);
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                if (mounted) {
                                  UIHelpers.showAlertDialog(context, 'Delete Failed', e.toString());
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
