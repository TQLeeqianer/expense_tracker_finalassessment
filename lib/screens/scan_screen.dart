import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../widgets/add_transaction_sheet.dart';
import '../models/transaction_model.dart';
import '../services/gemini_service.dart';
import '../providers/settings_provider.dart';

import '../services/firestore_service.dart';

enum _ScanState { initial, loading, preview, previewBatch, error }

class _BatchItem {
  bool isSelected = true;
  double amount = 0.0;
  String currency = 'MYR';
  String type = 'expense';
  String title = '';
  String category = 'Other';
  DateTime date = DateTime.now();

  _BatchItem.fromScanResult(ScanResult rs, String baseCurrency) {
    amount = rs.amount ?? 0.0;
    currency = rs.currency ?? baseCurrency;
    type = rs.type ?? 'expense';
    title = rs.title ?? (type == 'expense' ? 'Expense' : 'Income');
    category = rs.category ?? 'Other';
    date = rs.date ?? DateTime.now();
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Uint8List? _scannedBytes;
  _ScanState _state = _ScanState.initial;
  List<_BatchItem> _batchItems = [];
  final ImagePicker _picker = ImagePicker();

  // Preview card state (populated after successful Gemini extraction)
  String _previewType = 'expense';
  final _previewTitleCtrl = TextEditingController();
  final _previewAmountCtrl = TextEditingController();
  String _previewCurrency = 'USD';
  String _previewCategory = 'Other';
  DateTime _previewDate = DateTime.now();

  // Manual fallback state (shown in error state)
  final _fallbackAmountCtrl = TextEditingController();
  TransactionType _fallbackType = TransactionType.expense;

  static const _expenseCategories = [
    'Shopping', 'Food', 'Transport', 'Utilities',
    'Entertainment', 'Health', 'Transfer', 'Other'
  ];
  static const _incomeCategories = [
    'Salary', 'Freelance', 'Investment', 'Gift', 'Transfer', 'Other'
  ];

  List<String> get _previewCategories =>
      _previewType == 'expense' ? _expenseCategories : _incomeCategories;

  @override
  void dispose() {
    _previewTitleCtrl.dispose();
    _previewAmountCtrl.dispose();
    _fallbackAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() {
        _scannedBytes = bytes;
        _state = _ScanState.loading;
      });

      await _analyzeImage(bytes);
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Could not load image: $e');
        setState(() => _state = _ScanState.initial);
      }
    }
  }

  Future<void> _analyzeImage(Uint8List bytes) async {
    try {
      final results = await GeminiService().analyzeReceipt(bytes);
      if (!mounted) return;

      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final baseCurrency = settings.baseCurrency;

      if (results.length == 1) {
        final result = results.first;
        final type = result.type ?? 'expense';

        final categories =
            type == 'expense' ? _expenseCategories : _incomeCategories;
        final category = (result.category != null &&
                categories.contains(result.category))
            ? result.category!
            : 'Other';

        setState(() {
          _previewType = type;
          _previewTitleCtrl.text = result.title ?? '';
          _previewAmountCtrl.text = result.amount?.toStringAsFixed(2) ?? '';
          _previewCurrency = result.currency ?? baseCurrency;
          _previewCategory = category;
          _previewDate = result.date ?? DateTime.now();
          _state = _ScanState.preview;
        });
      } else {
        setState(() {
          _batchItems = results.map((r) => _BatchItem.fromScanResult(r, baseCurrency)).toList();
          _state = _ScanState.previewBatch;
        });
      }
    } on GeminiScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _fallbackType = TransactionType.expense;
        _state = _ScanState.error;
      });
      _showErrorDialog(e.message);
    }
  }

  void _confirmAndAdd() async {
    final amount = double.tryParse(_previewAmountCtrl.text.trim());
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(
        initialType: _previewType == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        initialAmount: amount,
        initialTitle: _previewTitleCtrl.text.trim().isEmpty
            ? null
            : _previewTitleCtrl.text.trim(),
        initialCategory: _previewCategory,
        initialDate: _previewDate,
      ),
    );

    if (saved == true && mounted) {
      _showSuccessDialog();
    }
  }

  void _confirmAndAddBatch() async {
    final selectedItems = _batchItems.where((e) => e.isSelected).toList();
    if (selectedItems.isEmpty) return;

    setState(() => _state = _ScanState.loading); // Visual cue during import

    List<TransactionModel> txs = selectedItems.map((item) {
      return TransactionModel(
        id: '',
        title: item.title.isEmpty ? 'Batch Scan' : item.title,
        amount: item.amount,
        category: item.category,
        date: item.date,
        tags: [],
        type: item.type == 'expense' ? TransactionType.expense : TransactionType.income,
        currency: item.currency,
        fromAccount: item.type == 'expense' ? 'Default Wallet' : null,
        toAccount: item.type == 'income' ? 'Default Wallet' : null,
        status: TransactionStatus.completed,
      );
    }).toList();

    try {
      await FirestoreService().addTransactionsBatch(txs);
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Failed to import batch: $e');
        setState(() => _state = _ScanState.previewBatch);
      }
    }
  }

  void _proceedManual() async {
    final amount = double.tryParse(_fallbackAmountCtrl.text.trim());
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(
        initialType: _fallbackType,
        initialAmount: amount,
      ),
    );

    if (saved == true && mounted) {
      _showSuccessDialog();
    }
  }

  void _reset() {
    setState(() {
      _scannedBytes = null;
      _state = _ScanState.initial;
      _previewTitleCtrl.clear();
      _previewAmountCtrl.clear();
      _fallbackAmountCtrl.clear();
      _batchItems.clear();
    });
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan Alert'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Success'),
          ],
        ),
        content: const Text('Transaction saved successfully!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Go back to Home
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              _reset(); // Reset to scan another document
            },
            child: const Text('Scan Another'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blueColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: blueColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Scan Document',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_state != _ScanState.initial)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Scan again',
              onPressed: _reset,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [


            // Image preview area
            GestureDetector(
              onTap: _state == _ScanState.initial || _state == _ScanState.error
                  ? _showImageSourceDialog
                  : () {
                      if (_scannedBytes != null) _showFullImageDialog();
                    },
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: _scannedBytes != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _scannedBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to scan or upload',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Receipt or Bank Slip',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Camera / Gallery buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _state == _ScanState.loading
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _state == _ScanState.loading
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // State-driven body
            if (_state == _ScanState.loading) _buildLoadingSection(),
            if (_state == _ScanState.preview) _buildPreviewSection(blueColor),
            if (_state == _ScanState.previewBatch) _buildPreviewBatchSection(blueColor),
            if (_state == _ScanState.error) _buildErrorSection(blueColor),
            if (_state == _ScanState.initial)
              ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Upload a document first',
                    style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSection() {
    return const Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text(
          'Analyzing with AI…',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildPreviewSection(Color blueColor) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Type selector
            const Text('Transaction Type',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'expense',
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward)),
                ButtonSegment(
                    value: 'income',
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_previewType},
              onSelectionChanged: (Set<String> val) {
                setState(() {
                  _previewType = val.first;
                  // Reset category to 'Other' when type changes
                  _previewCategory = 'Other';
                });
              },
            ),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _previewTitleCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Amount + Currency
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: settings.activeCurrencies.contains(_previewCurrency)
                        ? _previewCurrency
                        : settings.baseCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: settings.activeCurrencies
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _previewCurrency = val);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _previewAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Category
            DropdownButtonFormField<String>(
              value: _previewCategories.contains(_previewCategory)
                  ? _previewCategory
                  : 'Other',
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _previewCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _previewCategory = val);
              },
            ),
            const SizedBox(height: 16),

            // Date
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _previewDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                );
                if (picked != null) setState(() => _previewDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                  filled: true,
                  fillColor: Colors.white,
                ),
                child: Text(
                  '${_previewDate.toLocal()}'.split(' ')[0],
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Confirm button
            ElevatedButton(
              onPressed: _confirmAndAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: blueColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirm & Add',
                  style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreviewBatchSection(Color blueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Multiple Transactions Detected',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _batchItems.length,
          itemBuilder: (ctx, i) {
            final item = _batchItems[i];
            final categories = item.type == 'expense' ? _expenseCategories : _incomeCategories;
            // Ensure category is valid dynamically
            if (!categories.contains(item.category)) {
              item.category = 'Other';
            }

            return Card(
              color: item.isSelected ? Colors.white : Colors.grey.shade100,
              elevation: item.isSelected ? 2 : 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: item.isSelected,
                          activeColor: blueColor,
                          onChanged: (val) {
                            setState(() => item.isSelected = val ?? false);
                          },
                        ),
                        Expanded(
                          child: Text(
                            item.title.isEmpty ? 'Unknown' : item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: item.isSelected ? Colors.black87 : Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        ),
                        Text(
                          '${item.type == 'expense' ? '-' : '+'} ${item.currency} ${item.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: !item.isSelected ? Colors.grey : (item.type == 'expense' ? Colors.red : Colors.green),
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48.0, top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: item.isSelected ? DropdownButtonFormField<String>(
                              value: item.category,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                border: OutlineInputBorder(),
                              ),
                              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => item.category = val);
                              },
                            ) : Text(item.category, style: const TextStyle(color: Colors.grey)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${item.date.toLocal()}'.split(' ')[0],
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _batchItems.any((e) => e.isSelected) ? _confirmAndAddBatch : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: blueColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Import ${_batchItems.where((e) => e.isSelected).length} Selected', style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildErrorSection(Color blueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _fallbackAmountCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (enter manually)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.attach_money),
            hintText: '0.00',
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        const Text('Transaction Type',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black54)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDetectedTypeCard(
                  TransactionType.expense, Icons.arrow_upward, 'Expense',
                  Colors.red),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDetectedTypeCard(
                  TransactionType.income, Icons.arrow_downward, 'Income',
                  Colors.green),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _proceedManual,
          style: ElevatedButton.styleFrom(
            backgroundColor: blueColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Proceed to Add Transaction',
              style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }



  Widget _buildDetectedTypeCard(
      TransactionType type, IconData icon, String label, Color color) {
    final isSelected = _fallbackType == type;
    return GestureDetector(
      onTap: () => setState(() => _fallbackType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                  color: isSelected ? color : Colors.black87,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImageDialog() {
    if (_scannedBytes == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(
                _scannedBytes!,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
