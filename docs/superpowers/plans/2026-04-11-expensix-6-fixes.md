# Expensix 6-Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 bugs/features: notification spam, remove redundant Category quick action, tag filtering + type colours in SeeAll, replace Transfer type with linked Expense+Income pairs, fix amount-search sign logic, and fix scan upload crash with amount pre-fill.

**Architecture:** Provider-based Flutter app. All fixes are local — no new state-management layer. Transfer linking uses a Firestore batch write to guarantee atomicity. Scan platform issue fixed by switching from `dart:io File` to `XFile.readAsBytes()` for cross-platform image display.

**Tech Stack:** Flutter/Dart 3.11, Provider 6.x, Cloud Firestore 6.x, image_picker 1.x

---

## File Map

**Modify:**
- `lib/models/transaction_model.dart` — add `linkedTransactionId` field
- `lib/services/firestore_service.dart` — add `addLinkedTransactions()` batch write + linked delete
- `lib/widgets/add_transaction_sheet.dart` — remove Transfer from type dropdown, add Transfer toggle mode, accept `initialAmount`, pass `true` on save
- `lib/screens/home_screen.dart` — fix FAB notification, remove Category action item, fix search sign logic, show link badge on linked tiles, delete linked pair on swipe
- `lib/screens/see_all_screen.dart` — add tag filter chip row, type-coloured tag chips, fix search sign logic
- `lib/screens/scan_screen.dart` — switch to XFile+bytes (fixes upload crash), add post-scan amount field + type detection

---

## Task 1: Fix Notification — Only Show After Actual Save

**Files:**
- Modify: `lib/widgets/add_transaction_sheet.dart:134-136`
- Modify: `lib/screens/home_screen.dart:697-712`

The FAB calls `.then((_) { AppNotification.show(...) })` which fires on ANY dismissal — cancel, swipe, back button. Fix: `AddTransactionSheet` pops with `true` only on a real save; the FAB checks the returned value.

- [ ] **Step 1: Pop with `true` in `_submit()` on success**

In `add_transaction_sheet.dart`, find the success pop inside `_submit()`:
```dart
if (mounted) {
  Navigator.pop(context); // Close the BottomSheet on success
}
```
Replace with:
```dart
if (mounted) {
  Navigator.pop(context, true); // signals a real save
}
```

- [ ] **Step 2: Guard notification on save result in FAB**

In `home_screen.dart`, find the FAB `onPressed` (around line 696):
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => const AddTransactionSheet(),
).then((_) {
  if (mounted) {
    AppNotification.show(
      overlay,
      'Transaction saved successfully!',
      icon: Icons.check_circle,
      color: Colors.green,
    );
  }
});
```
Replace with:
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => const AddTransactionSheet(),
).then((saved) {
  if (mounted && saved == true) {
    AppNotification.show(
      overlay,
      'Transaction saved successfully!',
      icon: Icons.check_circle,
      color: Colors.green,
    );
  }
});
```

- [ ] **Step 3: Commit**
```bash
git add lib/widgets/add_transaction_sheet.dart lib/screens/home_screen.dart
git commit -m "fix: only show save notification when transaction is actually saved"
```

---

## Task 2: Remove Category Quick Action

**Files:**
- Modify: `lib/screens/home_screen.dart:438-440`

The Category quick action duplicates the Filter screen already accessible from the bottom filter button. Remove it so the row reads: Scan · Analysis · History · More.

- [ ] **Step 1: Delete the Category action item**

In `home_screen.dart`, find the quick actions Row children. Remove these lines entirely:
```dart
_buildActionItem(Icons.category, 'Category', () {
  _showFilterSheet();
}),
```

The resulting Row children will be:
```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    _buildActionItem(Icons.qr_code_scanner, 'Scan', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    }),
    _buildActionItem(Icons.pie_chart, 'Analysis', () {
      _showComingSoonDialog(context, 'Advanced Analysis', 'Detailed PDF exports and deep analytics are on the roadmap!', Icons.pie_chart);
    }),
    _buildActionItem(Icons.history, 'History', () {
      _showComingSoonDialog(context, 'Transaction History', 'A dedicated full-page history log is in development and will be available shortly.', Icons.history);
    }),
    _buildActionItem(Icons.grid_view, 'More', () {
      _showComingSoonDialog(context, 'More Features', 'We are actively developing incredible new tools. Stay tuned!', Icons.rocket_launch);
    }),
  ],
),
```

- [ ] **Step 2: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: remove Category quick action (filter is accessible from bottom bar)"
```

---

## Task 3: Tag Filtering + Type-Coloured Tag Chips in SeeAll

**Files:**
- Modify: `lib/screens/see_all_screen.dart`
- Modify: `lib/screens/home_screen.dart` (tag chip colours in `_buildTransactionTile`)

Tag chips on transaction tiles are currently all grey. Change them to be coloured by the transaction's type (expense=red, income=green, transfer=blue). Add a tag filter chip row at the top of `SeeAllScreen`.

- [ ] **Step 1: Add `_filterTag` state and tag colour helper to `SeeAllScreen`**

In `see_all_screen.dart`, add to the `_SeeAllScreenState` fields (after `_searchFocused`):
```dart
String _filterTag = '';
```

Add a helper method before `_passesFilters`:
```dart
Color _tagBgColor(TransactionType type) {
  switch (type) {
    case TransactionType.expense: return Colors.red.shade100;
    case TransactionType.income: return Colors.green.shade100;
    case TransactionType.transfer: return Colors.blue.shade100;
  }
}

Color _tagTextColor(TransactionType type) {
  switch (type) {
    case TransactionType.expense: return Colors.red.shade700;
    case TransactionType.income: return Colors.green.shade700;
    case TransactionType.transfer: return Colors.blue.shade700;
  }
}
```

- [ ] **Step 2: Add tag filter to `_passesFilters`**

In `_passesFilters`, add one more bool after `bool passAcc = ...`:
```dart
bool passTag = _filterTag.isEmpty || t.tags.contains(_filterTag);
return passTime && passSearch && passCat && passType && passMin && passMax && passAcc && passTag;
```

- [ ] **Step 3: Add tag filter chip row to `build()`**

In `build()`, inside the `StreamBuilder`, after the search lock banner and `const SizedBox(height: 8)` but BEFORE the `Expanded` list, add:

```dart
// Tag filter chips
StreamBuilder<List<TransactionModel>>(
  stream: FirestoreService().getTransactionsStream(),
  builder: (context, snapshot) {
    final allTags = (snapshot.data ?? [])
        .where((t) => !t.isDeleted)
        .expand((t) => t.tags)
        .toSet()
        .toList()
      ..sort();
    if (allTags.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All Tags'),
            selected: _filterTag.isEmpty,
            onSelected: (_) => setState(() => _filterTag = ''),
            selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          ),
          const SizedBox(width: 8),
          ...allTags.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('#$tag'),
              selected: _filterTag == tag,
              onSelected: (_) => setState(() => _filterTag = _filterTag == tag ? '' : tag),
              selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            ),
          )),
        ],
      ),
    );
  },
),
const SizedBox(height: 8),
```

- [ ] **Step 4: Apply type colours to tag chips in `_buildTile`**

In `_buildTile`, find the tag Wrap:
```dart
children: t.tags.map((tag) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
  child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54)),
)).toList(),
```

Replace with:
```dart
children: t.tags.map((tag) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: _tagBgColor(t.type),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    '#$tag',
    style: TextStyle(fontSize: 10, color: _tagTextColor(t.type), fontWeight: FontWeight.w600),
  ),
)).toList(),
```

- [ ] **Step 5: Apply type colours to tag chips in `home_screen.dart` `_buildTransactionTile`**

In `home_screen.dart`, find `_buildTransactionTile`. Locate the Wrap for tags:
```dart
children: t.tags.map((tag) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: Colors.grey.shade200,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500)),
)).toList(),
```

Replace with:
```dart
children: t.tags.map((tag) {
  Color chipBg;
  Color chipText;
  switch (t.type) {
    case TransactionType.expense:
      chipBg = Colors.red.shade100; chipText = Colors.red.shade700; break;
    case TransactionType.income:
      chipBg = Colors.green.shade100; chipText = Colors.green.shade700; break;
    case TransactionType.transfer:
      chipBg = Colors.blue.shade100; chipText = Colors.blue.shade700; break;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
    child: Text('#$tag', style: TextStyle(fontSize: 10, color: chipText, fontWeight: FontWeight.w600)),
  );
}).toList(),
```

- [ ] **Step 6: Commit**
```bash
git add lib/screens/see_all_screen.dart lib/screens/home_screen.dart
git commit -m "feat: add tag filter chips in SeeAllScreen and type-coloured tag chips"
```

---

## Task 4: Replace Transfer Type with Linked Expense+Income Pair

**Files:**
- Modify: `lib/models/transaction_model.dart`
- Modify: `lib/services/firestore_service.dart`
- Modify: `lib/widgets/add_transaction_sheet.dart`
- Modify: `lib/screens/home_screen.dart`

Transfer transactions are replaced by two linked regular transactions: one expense (money out of account A) and one income (money into account B). They share a `linkedTransactionId` field pointing to each other. Deleting one auto-deletes its partner. Existing `type: transfer` data continues to display correctly.

### 4a: Model — add `linkedTransactionId`

- [ ] **Step 1: Add field to `TransactionModel`**

In `transaction_model.dart`, in the class body after `final String? toAccount;`, add:
```dart
final String? linkedTransactionId;
```

Add it to the constructor after `this.toAccount`:
```dart
this.linkedTransactionId,
```

In `fromFirestore`, after the `toAccount` line:
```dart
linkedTransactionId: data['linkedTransactionId'],
```

In `toMap()`, after the `toAccount` if-block:
```dart
if (linkedTransactionId != null) 'linkedTransactionId': linkedTransactionId,
```

Full updated `TransactionModel` class:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { income, expense, transfer }
enum TransactionStatus { pending, completed, failed, refunded }

class TransactionModel {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final List<String> tags;
  final bool isDeleted;
  final String currency;
  final TransactionType type;
  final TransactionStatus status;
  final String? fromAccount;
  final String? toAccount;
  final String? linkedTransactionId;

  TransactionModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.tags = const [],
    this.isDeleted = false,
    this.currency = 'USD',
    required this.type,
    this.status = TransactionStatus.completed,
    this.fromAccount,
    this.toAccount,
    this.linkedTransactionId,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    TransactionType parsedType = TransactionType.expense;
    if (data.containsKey('type')) {
      parsedType = TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.expense,
      );
    } else if (data.containsKey('isExpense')) {
      parsedType = data['isExpense'] == true
          ? TransactionType.expense
          : TransactionType.income;
    }

    TransactionStatus parsedStatus = TransactionStatus.completed;
    if (data.containsKey('status')) {
      parsedStatus = TransactionStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => TransactionStatus.completed,
      );
    }

    return TransactionModel(
      id: doc.id,
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      category: data['category'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      tags: data['tags'] != null ? List<String>.from(data['tags']) : [],
      isDeleted: data['isDeleted'] ?? false,
      currency: data['currency'] ?? 'USD',
      type: parsedType,
      status: parsedStatus,
      fromAccount: data['fromAccount'],
      toAccount: data['toAccount'],
      linkedTransactionId: data['linkedTransactionId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'category': category,
      'date': Timestamp.fromDate(date),
      'tags': tags,
      'isDeleted': isDeleted,
      'currency': currency,
      'type': type.name,
      'status': status.name,
      if (fromAccount != null) 'fromAccount': fromAccount,
      if (toAccount != null) 'toAccount': toAccount,
      if (linkedTransactionId != null) 'linkedTransactionId': linkedTransactionId,
    };
  }
}
```

- [ ] **Step 2: Commit model**
```bash
git add lib/models/transaction_model.dart
git commit -m "feat: add linkedTransactionId field to TransactionModel"
```

### 4b: Service — batch create linked pair + delete partner

- [ ] **Step 3: Add `addLinkedTransactions` and `deleteLinkedTransaction` to `FirestoreService`**

In `firestore_service.dart`, after `deleteTransaction()`, add:

```dart
/// Creates two linked transactions atomically (expense + income).
/// Each transaction's linkedTransactionId points to the other's document ID.
Future<void> addLinkedTransactions(
    TransactionModel expense, TransactionModel income) async {
  final batch = _db.batch();
  final expenseRef = _userTransactions.doc();
  final incomeRef = _userTransactions.doc();

  batch.set(expenseRef, {
    ...expense.toMap(),
    'linkedTransactionId': incomeRef.id,
  });
  batch.set(incomeRef, {
    ...income.toMap(),
    'linkedTransactionId': expenseRef.id,
  });

  await batch.commit();
}

/// Soft-deletes a transaction and its linked partner (if any).
Future<void> deleteLinkedTransaction(TransactionModel t) async {
  await _userTransactions.doc(t.id).update({'isDeleted': true});
  if (t.linkedTransactionId != null) {
    await _userTransactions
        .doc(t.linkedTransactionId)
        .update({'isDeleted': true});
  }
}
```

- [ ] **Step 4: Commit service**
```bash
git add lib/services/firestore_service.dart
git commit -m "feat: add addLinkedTransactions batch write and deleteLinkedTransaction"
```

### 4c: AddTransactionSheet — remove Transfer type, add Transfer toggle

- [ ] **Step 5: Add `_isTransferMode` state and remove Transfer from type dropdown**

In `add_transaction_sheet.dart`, in `_AddTransactionSheetState` fields (after `bool _isLoading = false;`), add:
```dart
bool _isTransferMode = false;
```

In `initState`, after the `if (widget.initialType != null)` block, update the Transfer condition to use `_isTransferMode`:
```dart
if (widget.initialType != null) {
  _selectedType = widget.initialType!;
  if (widget.initialType == TransactionType.transfer) {
    _isTransferMode = true;
    _selectedType = TransactionType.expense; // internally use expense as default
    _selectedCategory = 'Transfer';
  } else {
    _selectedCategory = _currentCategories.first;
  }
}
```

- [ ] **Step 6: Update `_canSave` to use `_isTransferMode`**

Replace the existing `_canSave` getter:
```dart
bool get _canSave {
  if (_titleController.text.trim().isEmpty) return false;
  final amt = double.tryParse(_amountController.text.trim());
  if (amt == null || amt <= 0) return false;
  if (_isTransferMode &&
      (_selectedFromAccount == null || _selectedToAccount == null)) return false;
  return true;
}
```

- [ ] **Step 7: Add `_submitTransfer` method**

Before `_submit()`, add:
```dart
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
```

- [ ] **Step 8: Remove Transfer from the type dropdown items**

Find the `DropdownButtonFormField<TransactionType>` for type. Change items from:
```dart
items: const [
  DropdownMenuItem(value: TransactionType.expense, child: Text('Expense')),
  DropdownMenuItem(value: TransactionType.income, child: Text('Income')),
  DropdownMenuItem(value: TransactionType.transfer, child: Text('Transfer')),
],
```
To:
```dart
items: const [
  DropdownMenuItem(value: TransactionType.expense, child: Text('Expense')),
  DropdownMenuItem(value: TransactionType.income, child: Text('Income')),
],
```

Also wrap the entire type dropdown in `if (!_isTransferMode)`:
```dart
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
          _selectedCategory = _selectedType == TransactionType.expense ? 'Shopping' : 'Salary';
        });
      }
    },
  ),
  const SizedBox(height: 16),
],
```

- [ ] **Step 9: Add Transfer toggle chip (after the type dropdown)**

After the type dropdown block and before the Status dropdown, add:
```dart
// Transfer mode toggle — only show when not editing an existing transaction
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
        color: _isTransferMode
            ? Colors.blue.shade50
            : Colors.grey.shade100,
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
```

- [ ] **Step 10: Wire account dropdowns for transfer mode**

In transfer mode, show both From Account and To Account regardless of type. Replace the two existing `if (_selectedType == TransactionType.transfer || _selectedType == TransactionType.expense)` and `if (_selectedType == TransactionType.transfer || _selectedType == TransactionType.income)` blocks with:

```dart
// From Account — shown for expense or transfer mode
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
    },
  ),
  const SizedBox(height: 16),
],

// To Account — shown for income or transfer mode
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
    },
  ),
  const SizedBox(height: 16),
],
```

- [ ] **Step 11: Wire Save button to call correct submit method**

Find the `ElevatedButton` that calls `_submit`. Change `onPressed`:
```dart
onPressed: (_canSave && !_isLoading) ? (_isTransferMode ? _submitTransfer : _submit) : null,
```

- [ ] **Step 12: Commit sheet changes**
```bash
git add lib/widgets/add_transaction_sheet.dart
git commit -m "feat: replace Transfer type with linked Expense+Income toggle in AddTransactionSheet"
```

### 4d: Home screen — show link badge, delete linked partner on swipe

- [ ] **Step 13: Show link badge on linked transaction tiles**

In `home_screen.dart`, in `_buildTransactionTile`, find the `Stack` for the avatar (around the `CircleAvatar`):
```dart
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
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          padding: const EdgeInsets.all(2),
          child: statusIndicator,
        ),
      ),
  ],
),
```

Add the link badge after the status indicator:
```dart
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
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          padding: const EdgeInsets.all(2),
          child: statusIndicator,
        ),
      ),
    if (t.linkedTransactionId != null)
      Positioned(
        right: -4,
        bottom: -4,
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          padding: const EdgeInsets.all(2),
          child: const Icon(Icons.link, size: 12, color: Colors.blue),
        ),
      ),
  ],
),
```

- [ ] **Step 14: Delete linked partner on swipe dismiss**

In `_buildTransactionTile`, change the `onDismissed` callback from:
```dart
onDismissed: (direction) {
  FirestoreService().deleteTransaction(t.id);
},
```
To:
```dart
onDismissed: (direction) {
  FirestoreService().deleteLinkedTransaction(t);
},
```

- [ ] **Step 15: Delete linked partner from AddTransactionSheet delete button**

In `add_transaction_sheet.dart`, in the delete `IconButton.onPressed`, replace:
```dart
await FirestoreService().deleteTransaction(widget.existingTransaction!.id);
```
With:
```dart
await FirestoreService().deleteLinkedTransaction(widget.existingTransaction!);
```

- [ ] **Step 16: Commit home screen + sheet delete fix**
```bash
git add lib/screens/home_screen.dart lib/widgets/add_transaction_sheet.dart
git commit -m "feat: show link badge on linked transactions and delete partner on remove"
```

---

## Task 5: Fix Amount Search Sign Logic

**Files:**
- Modify: `lib/screens/home_screen.dart:288-295`
- Modify: `lib/screens/see_all_screen.dart:70-77`

**Current bug:** Searching "-2000" strips the `-` and matches amount=2000 for all types.

**Correct behaviour:**
- `"2000"` → match any transaction where `amount == 2000` (both income +2000 and expense -2000)
- `"-2000"` → match only **expense** transactions where `amount == 2000` (the `-` means "show me the outgoing one")
- `"+2000"` → match only **income** transactions where `amount == 2000`

- [ ] **Step 1: Fix search logic in `home_screen.dart`**

Find (around line 288):
```dart
if (_searchQuery.trim().isNotEmpty) {
  final query = _searchQuery.trim().toLowerCase();
  final queryStripped = query.replaceAll('+', '').replaceAll('-', '').trim();
  final queryNum = double.tryParse(queryStripped);
  passSearch = t.title.toLowerCase().contains(query) ||
               t.category.toLowerCase().contains(query) ||
               t.tags.any((tag) => tag.toLowerCase().contains(query)) ||
               (queryNum != null && t.amount == queryNum);
}
```

Replace with:
```dart
if (_searchQuery.trim().isNotEmpty) {
  final rawQuery = _searchQuery.trim();
  final queryLower = rawQuery.toLowerCase();
  final isNegativeSearch = rawQuery.startsWith('-');
  final isPositiveSearch = rawQuery.startsWith('+');
  final queryStripped = rawQuery.replaceAll('+', '').replaceAll('-', '').trim();
  final queryNum = double.tryParse(queryStripped);
  bool amountMatch = false;
  if (queryNum != null) {
    if (isNegativeSearch) {
      amountMatch = t.amount == queryNum && t.type == TransactionType.expense;
    } else if (isPositiveSearch) {
      amountMatch = t.amount == queryNum && t.type == TransactionType.income;
    } else {
      amountMatch = t.amount == queryNum;
    }
  }
  passSearch = t.title.toLowerCase().contains(queryLower) ||
               t.category.toLowerCase().contains(queryLower) ||
               t.tags.any((tag) => tag.toLowerCase().contains(queryLower)) ||
               amountMatch;
}
```

- [ ] **Step 2: Fix search logic in `see_all_screen.dart`**

Find the identical block in `_passesFilters` (around line 70):
```dart
if (_searchQuery.trim().isNotEmpty) {
  final query = _searchQuery.trim().toLowerCase();
  final queryStripped = query.replaceAll('+', '').replaceAll('-', '').trim();
  final queryNum = double.tryParse(queryStripped);
  passSearch = t.title.toLowerCase().contains(query) ||
               t.category.toLowerCase().contains(query) ||
               t.tags.any((tag) => tag.toLowerCase().contains(query)) ||
               (queryNum != null && t.amount == queryNum);
}
```

Replace with:
```dart
if (_searchQuery.trim().isNotEmpty) {
  final rawQuery = _searchQuery.trim();
  final queryLower = rawQuery.toLowerCase();
  final isNegativeSearch = rawQuery.startsWith('-');
  final isPositiveSearch = rawQuery.startsWith('+');
  final queryStripped = rawQuery.replaceAll('+', '').replaceAll('-', '').trim();
  final queryNum = double.tryParse(queryStripped);
  bool amountMatch = false;
  if (queryNum != null) {
    if (isNegativeSearch) {
      amountMatch = t.amount == queryNum && t.type == TransactionType.expense;
    } else if (isPositiveSearch) {
      amountMatch = t.amount == queryNum && t.type == TransactionType.income;
    } else {
      amountMatch = t.amount == queryNum;
    }
  }
  passSearch = t.title.toLowerCase().contains(queryLower) ||
               t.category.toLowerCase().contains(queryLower) ||
               t.tags.any((tag) => tag.toLowerCase().contains(queryLower)) ||
               amountMatch;
}
```

- [ ] **Step 3: Commit**
```bash
git add lib/screens/home_screen.dart lib/screens/see_all_screen.dart
git commit -m "fix: amount search respects +/- sign to filter by transaction type"
```

---

## Task 6: Fix Scan Upload Crash + Amount Pre-fill

**Files:**
- Modify: `lib/screens/scan_screen.dart`
- Modify: `lib/widgets/add_transaction_sheet.dart`

**Root cause of upload crash:** The app is run on Chrome (web) where `dart:io File` and `Image.file()` are unavailable. Fix: store `XFile` and display with `Image.memory()` via `readAsBytes()`.

**Pre-fill:** After picking image, show an editable amount field and a type selector. Pass `initialAmount` and `initialType` to `AddTransactionSheet` when proceeding.

### 6a: AddTransactionSheet — accept `initialAmount`

- [ ] **Step 1: Add `initialAmount` parameter to `AddTransactionSheet`**

In `add_transaction_sheet.dart`, add to the widget parameters (after `initialType`):
```dart
final double? initialAmount;
```

Update the constructor:
```dart
const AddTransactionSheet({
  super.key,
  this.existingTransaction,
  this.initialType,
  this.initialAmount,
});
```

In `initState`, after the existing-transaction block, add:
```dart
if (widget.initialAmount != null) {
  _amountController.text = widget.initialAmount!.toStringAsFixed(2);
}
```

- [ ] **Step 2: Commit sheet change**
```bash
git add lib/widgets/add_transaction_sheet.dart
git commit -m "feat: AddTransactionSheet accepts initialAmount for scan pre-fill"
```

### 6b: ScanScreen — XFile bytes + amount field + type detection

- [ ] **Step 3: Rewrite `scan_screen.dart` for cross-platform image display and pre-fill**

Replace the entire file with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/add_transaction_sheet.dart';
import '../models/transaction_model.dart';

enum ScanType { receipt, bankTransfer }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  ScanType _selectedType = ScanType.receipt;
  XFile? _scannedFile;
  Uint8List? _scannedBytes;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  // Pre-fill fields shown after scanning
  final TextEditingController _detectedAmountCtrl = TextEditingController();
  TransactionType _detectedTransactionType = TransactionType.expense;

  @override
  void dispose() {
    _detectedAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _isProcessing = true);
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _scannedFile = picked;
          _scannedBytes = bytes;
          // Default type detection based on scan mode
          _detectedTransactionType = _selectedType == ScanType.receipt
              ? TransactionType.expense
              : TransactionType.income;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _proceedToAddTransaction() {
    final amount = double.tryParse(_detectedAmountCtrl.text.trim());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(
        initialType: _detectedTransactionType,
        initialAmount: amount,
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
        title: const Text('Scan Document',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scan type selector
            const Text('Document Type',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildTypeCard(ScanType.receipt, Icons.receipt_long, 'Receipt', blueColor)),
                const SizedBox(width: 16),
                Expanded(child: _buildTypeCard(ScanType.bankTransfer, Icons.account_balance, 'Bank Transfer', blueColor)),
              ],
            ),
            const SizedBox(height: 24),

            // Image preview
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: _scannedBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(_scannedBytes!,
                            fit: BoxFit.cover, width: double.infinity),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Tap to scan or upload',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 16)),
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
                    onPressed: () => _pickImage(ImageSource.camera),
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
                    onPressed: () => _pickImage(ImageSource.gallery),
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

            // Post-scan: detected info + proceed
            if (_isProcessing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading image…',
                      style: TextStyle(color: Colors.grey)),
                ],
              )
            else if (_scannedBytes != null) ...[
              // Success banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Image loaded. Enter the amount and confirm the type.',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount field
              TextField(
                controller: _detectedAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

              // Transaction type selector
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
                onPressed: _proceedToAddTransaction,
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
            ] else
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
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedTypeCard(
      TransactionType type, IconData icon, String label, Color color) {
    final isSelected = _detectedTransactionType == type;
    return GestureDetector(
      onTap: () => setState(() => _detectedTransactionType = type),
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
            Text(label,
                style: TextStyle(
                    color: isSelected ? color : Colors.black87,
                    fontWeight: FontWeight.w600)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
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

- [ ] **Step 4: Run flutter analyze on changed files**

```bash
flutter analyze lib/screens/scan_screen.dart lib/widgets/add_transaction_sheet.dart
```

Expected: only info-level deprecation warnings, no errors.

- [ ] **Step 5: Commit scan screen**
```bash
git add lib/screens/scan_screen.dart lib/widgets/add_transaction_sheet.dart
git commit -m "fix: scan upload crash (XFile bytes), add amount field and type selector after scan"
```

---

## Self-Review

**Spec coverage:**
1. ✅ Notification only on real save — Task 1
2. ✅ Remove Category quick action — Task 2
3. ✅ Tag filter in SeeAll + type colours — Task 3
4. ✅ Transfer → linked Expense+Income pair — Task 4 (model, service, sheet, home tile)
5. ✅ Search sign logic (-2000 = expense only) — Task 5
6. ✅ Scan upload crash fix + amount pre-fill + type selector — Task 6

**Placeholder scan:** None — all steps have complete code blocks.

**Type consistency:**
- `linkedTransactionId` used consistently across model, service, and UI
- `deleteLinkedTransaction(TransactionModel)` signature matches usage in home_screen and add_transaction_sheet
- `initialAmount` parameter name consistent between ScanScreen call and AddTransactionSheet
- `_isTransferMode` used consistently in `_canSave`, `_submitTransfer`, type dropdown guard, and account dropdown guards
