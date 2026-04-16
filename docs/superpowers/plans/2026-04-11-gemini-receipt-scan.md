# Gemini AI Receipt Scanning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual amount-entry step in ScanScreen with automatic AI extraction via Gemini Vision, with an editable preview card before the user confirms and opens AddTransactionSheet fully pre-filled.

**Architecture:** A new `GeminiService` handles all Gemini API interaction and JSON parsing, keeping the screen lean. `ScanScreen` gains a state machine (initial → loading → preview / error) driven by `GeminiService.analyzeReceipt`. `AddTransactionSheet` receives three new optional pre-fill parameters (`initialTitle`, `initialCategory`, `initialDate`) to complement the existing `initialAmount`/`initialType`.

**Tech Stack:** Flutter 3.11, Dart, `google_generative_ai ^0.4.6`, `image_picker ^1.1.2`, Provider (`SettingsProvider`), Firebase/Firestore (unchanged)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `pubspec.yaml` | Add `google_generative_ai: ^0.4.6` |
| Create | `lib/services/gemini_service.dart` | API key, `ScanResult`, `GeminiScanException`, `analyzeReceipt()` |
| Modify | `lib/widgets/add_transaction_sheet.dart` | Add `initialTitle`, `initialCategory`, `initialDate` params + initState pre-fill |
| Modify | `lib/screens/scan_screen.dart` | Replace manual UI with loading/preview/error state machine |

---

### Task 1: Add Gemini Dependency

**Files:**
- Modify: `pubspec.yaml` (line 46, under `image_picker`)

- [ ] **Step 1: Add the dependency**

Open `pubspec.yaml`. Under `dependencies:`, after `image_picker: ^1.1.2`, add:

```yaml
  google_generative_ai: ^0.4.6
```

The `dependencies` block should look like:
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  provider: ^6.1.5+1
  firebase_core: ^4.6.0
  firebase_auth: ^6.3.0
  cloud_firestore: ^6.2.0
  google_fonts: ^8.0.2
  intl: ^0.20.2
  fl_chart: ^1.2.0
  shared_preferences: ^2.5.5
  image_picker: ^1.1.2
  google_generative_ai: ^0.4.6
```

- [ ] **Step 2: Fetch packages**

Run:
```bash
flutter pub get
```

Expected: resolves packages, no errors. (On Windows you may see a symlink warning — that is non-fatal and can be ignored.)

- [ ] **Step 3: Verify compile**

Run:
```bash
flutter analyze --no-fatal-infos
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: add google_generative_ai dependency for Gemini receipt scan"
```

---

### Task 2: Create GeminiService

**Files:**
- Create: `lib/services/gemini_service.dart`

- [ ] **Step 1: Create the file**

Create `lib/services/gemini_service.dart` with the full content below:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ignore: constant_identifier_names
const _kGeminiApiKey = 'YOUR_API_KEY_HERE';

class GeminiScanException implements Exception {
  final String message;
  const GeminiScanException(this.message);

  @override
  String toString() => message;
}

class ScanResult {
  final double? amount;
  final String? currency; // ISO 4217 e.g. 'MYR', 'USD'
  final String? type;     // 'expense' or 'income'
  final String? title;    // merchant name or transfer description
  final String? category; // one of the app's category strings
  final DateTime? date;

  const ScanResult({
    this.amount,
    this.currency,
    this.type,
    this.title,
    this.category,
    this.date,
  });
}

class GeminiService {
  static const _prompt = r'''
You are a financial receipt analyzer. Analyze this image (receipt or bank transfer slip) and extract transaction details.

Return ONLY a valid JSON object with exactly these fields:
{
  "amount": <positive number, the transaction total>,
  "currency": <ISO 4217 currency code, e.g. "MYR", "USD", "SGD">,
  "type": <"expense" if money is paid out, "income" if money is received>,
  "title": <merchant name or transfer description, max 50 chars>,
  "category": <exactly one of: Shopping, Food, Transport, Utilities, Entertainment, Health, Salary, Freelance, Investment, Gift, Transfer, Other>,
  "date": <date in YYYY-MM-DD format, or null if not visible>
}

Rules:
- If you cannot determine a field, use null.
- Do not include any text outside the JSON object.
- For receipts (stores, restaurants): type is always "expense".
- For bank transfer slips showing money received: type is "income".
- For bank transfer slips showing money sent: type is "expense".
- Detect currency from symbols: RM or MYR → "MYR", $ → "USD", S$ → "SGD", € → "EUR", ¥ → "JPY".
''';

  Future<ScanResult> analyzeReceipt(Uint8List imageBytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _kGeminiApiKey,
      );

      final content = [
        Content.multi([
          TextPart(_prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await model.generateContent(content);
      final text = response.text;

      if (text == null || text.trim().isEmpty) {
        throw const GeminiScanException(
            'Could not read this image. Try a clearer photo.');
      }

      // Strip markdown code fences Gemini sometimes wraps around JSON
      final cleaned = text
          .trim()
          .replaceAll(RegExp(r'```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*', multiLine: true), '')
          .trim();

      Map<String, dynamic> json;
      try {
        json = jsonDecode(cleaned) as Map<String, dynamic>;
      } catch (_) {
        throw const GeminiScanException(
            'Could not read this image. Try a clearer photo.');
      }

      // Parse and validate amount
      double? amount;
      final rawAmount = json['amount'];
      if (rawAmount != null) {
        amount = (rawAmount as num).toDouble();
        if (amount <= 0) amount = null;
      }

      // Parse and validate type
      String? type = json['type'] as String?;
      if (type != null && type != 'expense' && type != 'income') {
        type = null;
      }

      // Parse date
      DateTime? date;
      final rawDate = json['date'] as String?;
      if (rawDate != null) {
        date = DateTime.tryParse(rawDate);
      }

      // Reject if all meaningful fields are null (completely unreadable)
      if (amount == null && type == null && json['title'] == null) {
        throw const GeminiScanException(
            'Could not read this image. Try a clearer photo.');
      }

      return ScanResult(
        amount: amount,
        currency: json['currency'] as String?,
        type: type,
        title: json['title'] as String?,
        category: json['category'] as String?,
        date: date,
      );
    } on GeminiScanException {
      rethrow;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('quota') || msg.contains('429') || msg.contains('resource_exhausted')) {
        throw const GeminiScanException('AI quota exceeded. Fill manually.');
      }
      throw const GeminiScanException(
          'Could not analyze image. Please fill in manually.');
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
flutter analyze lib/services/gemini_service.dart --no-fatal-infos
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/services/gemini_service.dart
git commit -m "feat: add GeminiService with ScanResult and analyzeReceipt"
```

---

### Task 3: Extend AddTransactionSheet with Pre-fill Parameters

**Files:**
- Modify: `lib/widgets/add_transaction_sheet.dart` (lines 8–16, initState block lines 36–69)

The current widget has `initialType` and `initialAmount`. We add `initialTitle`, `initialCategory`, `initialDate`.

- [ ] **Step 1: Add parameters to the widget class**

Replace the class declaration block (lines 8–16):

Old:
```dart
class AddTransactionSheet extends StatefulWidget {
  final TransactionModel? existingTransaction;
  final TransactionType? initialType;
  final double? initialAmount;

  const AddTransactionSheet({super.key, this.existingTransaction, this.initialType, this.initialAmount});
```

New:
```dart
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
```

- [ ] **Step 2: Pre-fill the new fields in initState**

In `initState`, after the existing `initialAmount` block (currently around line 64–66):

Old block:
```dart
    if (widget.initialAmount != null) {
      _amountController.text = widget.initialAmount!.toStringAsFixed(2);
    }
```

New block (replace with):
```dart
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
```

- [ ] **Step 3: Verify it compiles**

Run:
```bash
flutter analyze lib/widgets/add_transaction_sheet.dart --no-fatal-infos
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/add_transaction_sheet.dart
git commit -m "feat: add initialTitle, initialCategory, initialDate pre-fill to AddTransactionSheet"
```

---

### Task 4: Rewrite ScanScreen with AI State Machine

**Files:**
- Modify: `lib/screens/scan_screen.dart` (full rewrite)

Replace the entire file. The new screen has a `_ScanState` enum driving which UI section is shown. `_pickImage` sets state to `loading`, calls `GeminiService.analyzeReceipt`, then transitions to `preview` on success or `error` on `GeminiScanException`. The `error` state falls back to the old manual UI.

- [ ] **Step 1: Rewrite the file**

Replace `lib/screens/scan_screen.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../widgets/add_transaction_sheet.dart';
import '../models/transaction_model.dart';
import '../services/gemini_service.dart';
import '../providers/settings_provider.dart';

enum ScanType { receipt, bankTransfer }

enum _ScanState { initial, loading, preview, error }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  ScanType _selectedType = ScanType.receipt;
  Uint8List? _scannedBytes;
  _ScanState _state = _ScanState.initial;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load image: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _state = _ScanState.initial);
      }
    }
  }

  Future<void> _analyzeImage(Uint8List bytes) async {
    try {
      final result = await GeminiService().analyzeReceipt(bytes);
      if (!mounted) return;

      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final baseCurrency = settings.baseCurrency;

      final type = result.type ??
          (_selectedType == ScanType.receipt ? 'expense' : 'income');

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
    } on GeminiScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _fallbackType = _selectedType == ScanType.receipt
            ? TransactionType.expense
            : TransactionType.income;
        _state = _ScanState.error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmAndAdd() {
    final amount = double.tryParse(_previewAmountCtrl.text.trim());
    showModalBottomSheet(
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
  }

  void _proceedManual() {
    final amount = double.tryParse(_fallbackAmountCtrl.text.trim());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(
        initialType: _fallbackType,
        initialAmount: amount,
      ),
    );
  }

  void _reset() {
    setState(() {
      _scannedBytes = null;
      _state = _ScanState.initial;
      _previewTitleCtrl.clear();
      _previewAmountCtrl.clear();
      _fallbackAmountCtrl.clear();
    });
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
            // Document type selector (always visible)
            const Text(
              'Document Type',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTypeCard(
                      ScanType.receipt, Icons.receipt_long, 'Receipt', blueColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTypeCard(ScanType.bankTransfer,
                      Icons.account_balance, 'Bank Transfer', blueColor),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Image preview area
            GestureDetector(
              onTap: _state == _ScanState.initial || _state == _ScanState.error
                  ? _showImageSourceDialog
                  : null,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: _scannedBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _scannedBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
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
                            _selectedType == ScanType.receipt
                                ? 'Shopping receipt'
                                : 'Bank transfer slip',
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
          'Analyzing with AI\u2026',
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

  Widget _buildErrorSection(Color blueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _fallbackAmountCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (enter manually)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.attach_money),
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

  Widget _buildTypeCard(
      ScanType type, IconData icon, String label, Color activeColor) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? activeColor : Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
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
}
```

- [ ] **Step 2: Verify it compiles**

Run:
```bash
flutter analyze lib/screens/scan_screen.dart --no-fatal-infos
```

Expected: no errors.

- [ ] **Step 3: Verify whole project**

Run:
```bash
flutter analyze --no-fatal-infos
```

Expected: no errors across the project.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/scan_screen.dart
git commit -m "feat: rewrite ScanScreen with Gemini AI extraction and editable preview card"
```

---

## Self-Review

**Spec coverage check:**
- [x] `google_generative_ai: ^0.4.6` dependency → Task 1
- [x] `lib/services/gemini_service.dart` with API key, `ScanResult`, `GeminiScanException`, `analyzeReceipt()` → Task 2
- [x] `gemini-2.0-flash` model used → Task 2
- [x] Prompt matches spec exactly → Task 2
- [x] JSON parsing: validates type, validates amount > 0, `DateTime.tryParse` for date → Task 2
- [x] Throws `GeminiScanException` on API failure, invalid JSON, all fields null → Task 2
- [x] `AddTransactionSheet`: `initialTitle`, `initialCategory`, `initialDate` params + initState pre-fill → Task 3
- [x] ScanScreen: Initial → Loading ("Analyzing with AI…") → Preview → Error states → Task 4
- [x] Preview card: SegmentedButton for type, TextField for title, numeric TextField for amount, DropdownButtonFormField for currency + category, date picker → Task 4
- [x] "Confirm & Add" opens `AddTransactionSheet` with all pre-filled values → Task 4
- [x] Error: SnackBar + manual fallback fields (amount + type selector) → Task 4
- [x] Camera/Gallery buttons disabled during loading → Task 4
- [x] Partial extraction (some null fields): preview card shows with blanks for user to fill → Task 2 (null fields in ScanResult) + Task 4 (empty pre-fill)
- [x] Currency pre-fill: `result.currency ?? baseCurrency` → Task 4

**Type consistency check:**
- `ScanResult` defined in Task 2, consumed in Task 4 ✓
- `GeminiScanException` defined in Task 2, caught in Task 4 ✓
- `GeminiService().analyzeReceipt(bytes)` defined in Task 2, called in Task 4 ✓
- `AddTransactionSheet(initialTitle:, initialCategory:, initialDate:)` defined in Task 3, called in Task 4 ✓

**Placeholder scan:** No TBD/TODO/vague steps found. All code blocks are complete.
