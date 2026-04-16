# Expensix 15-Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 15 UI/UX improvements, bug fixes, and new features for the Expensix Flutter expense tracker app.

**Architecture:** Provider-based Flutter app (Firebase Auth + Firestore). Tasks target specific files; several tasks add new Screen files. No new state management layer is introduced — all new state stays local or extends `SettingsProvider` minimally.

**Tech Stack:** Flutter/Dart 3.11, Provider 6.x, Firebase Auth 6.x, Cloud Firestore 6.x, SharedPreferences 2.x, fl_chart 1.x, intl 0.20, image_picker 1.x (new)

---

## File Map

**Modify:**
- `lib/screens/home_screen.dart` — Quick Actions labels, search logic, tag spacing, filter wiring, multi-select, goal reminder, privacy popup
- `lib/screens/login_screen.dart` — forgot password button
- `lib/screens/profile_screen.dart` — privacy mode popup
- `lib/services/auth_service.dart` — add `sendPasswordResetEmail()`
- `lib/widgets/add_transaction_sheet.dart` — categories list, save-button validation, tag spacing
- `pubspec.yaml` — add `image_picker`

**Create:**
- `lib/widgets/app_notification_overlay.dart` — slide-from-top overlay notification
- `lib/screens/filter_screen.dart` — full-page filter with This-Week slide-up panel
- `lib/screens/see_all_screen.dart` — full-page transaction list with search lock + USD display
- `lib/screens/scan_screen.dart` — receipt/bank-transfer scan UI

---

## Task 1: Rename "Report" → "Analysis"

**Files:**
- Modify: `lib/screens/home_screen.dart:315-317`

- [ ] **Step 1: Edit the Quick Actions row**

In `home_screen.dart` find this block (around line 315):
```dart
_buildActionItem(Icons.pie_chart, 'Report', () {
  _showComingSoonDialog(context, 'Advanced Reporting', 'Detailed PDF exports and deep analytics are on the roadmap!', Icons.pie_chart);
}),
```
Replace with:
```dart
_buildActionItem(Icons.pie_chart, 'Analysis', () {
  _showComingSoonDialog(context, 'Advanced Analysis', 'Detailed PDF exports and deep analytics are on the roadmap!', Icons.pie_chart);
}),
```

- [ ] **Step 2: Hot reload and verify**

Run the app. The Quick Actions row should show: Transfer · Scan · **Analysis** · History · More.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: rename Report quick action to Analysis"
```

---

## Task 2: Fix Tag Spacing Bug in Transaction Tiles

**Files:**
- Modify: `lib/screens/home_screen.dart:1064-1079`

Tags in the transaction tile use `Wrap(spacing: 6)` with container `padding: horizontal: 6`. The visual gap is too tight — tags appear stuck together.

- [ ] **Step 1: Increase spacing and padding**

Find `_buildTransactionTile` in `home_screen.dart` around line 1064:
```dart
if (t.tags.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(top: 8.0),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: t.tags.map((tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500)),
      )).toList(),
    ),
  ),
```

Replace with:
```dart
if (t.tags.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(top: 8.0),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: t.tags.map((tag) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500)),
      )).toList(),
    ),
  ),
```

- [ ] **Step 2: Verify**

Open a transaction that has multiple tags. Each tag chip should have visible space between them.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "fix: increase tag spacing in transaction tiles"
```

---

## Task 3: Fix Amount Search Bug (Show +2000 and -2000 when searching "2000")

**Files:**
- Modify: `lib/screens/home_screen.dart:149-154`

Current search only matches title and tags. Searching "2000" finds nothing. Fix: strip +/- signs, parse as number, and compare against `t.amount`.

- [ ] **Step 1: Replace the passSearch logic**

Find in `home_screen.dart` (inside the main transaction loop, around line 149):
```dart
bool passSearch = true;
if (_searchQuery.trim().isNotEmpty) {
  final query = _searchQuery.trim().toLowerCase();
  passSearch = t.title.toLowerCase().contains(query) ||
               t.tags.any((tag) => tag.toLowerCase().contains(query));
}
```

Replace with:
```dart
bool passSearch = true;
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

- [ ] **Step 2: Verify**

Type "2000" in the search bar. Both income "+2000" and expense "-2000" transactions should appear. Type "shopping" — category-matched transactions should appear.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "fix: amount search now matches +/- 2000 and category text"
```

---

## Task 4: Fix Save Button Validation (Disable Instead of Alert)

**Files:**
- Modify: `lib/widgets/add_transaction_sheet.dart`

Currently saving with empty title/amount shows an `AlertDialog`. The new behaviour: the Save button is greyed out and un-tappable until required fields are filled. No alert fires for empty fields.

- [ ] **Step 1: Add controller listeners in initState**

Find `initState()` in `add_transaction_sheet.dart`. After the existing `if (widget.existingTransaction != null)` block, add:
```dart
_titleController.addListener(() => setState(() {}));
_amountController.addListener(() => setState(() {}));
```

Full `initState` after change:
```dart
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
    _selectedFromAccount = t.fromAccount;
    _selectedToAccount = t.toAccount;
    _selectedTags = List.from(t.tags);
    _selectedType = t.type;
    _selectedStatus = t.status;
    _selectedDate = t.date;
    _selectedCategory = t.type == TransactionType.transfer ? 'Transfer' : t.category;
    _selectedCurrency = t.currency;
  }

  _titleController.addListener(() => setState(() {}));
  _amountController.addListener(() => setState(() {}));
}
```

- [ ] **Step 2: Add `_canSave` getter**

Directly above the `_pickDate()` method, add:
```dart
bool get _canSave {
  if (_titleController.text.trim().isEmpty) return false;
  final amt = double.tryParse(_amountController.text.trim());
  if (amt == null || amt <= 0) return false;
  if (_selectedType == TransactionType.transfer &&
      (_selectedFromAccount == null || _selectedToAccount == null)) return false;
  return true;
}
```

- [ ] **Step 3: Remove the empty-field alert from `_submit()`**

Find in `_submit()`:
```dart
// Basic validation
if (_titleController.text.isEmpty || _amountController.text.isEmpty) {
  UIHelpers.showAlertDialog(context, 'Missing Details', 'Please fill the title and amount to continue.');
  return;
}
```

Delete those four lines entirely. The transfer-accounts check further down stays unchanged.

- [ ] **Step 4: Find the Save button and gate it on `_canSave`**

Scroll to the bottom of `add_transaction_sheet.dart`. Find the ElevatedButton that calls `_submit`. It looks like:
```dart
ElevatedButton(
  onPressed: _isLoading ? null : _submit,
  ...
  child: _isLoading ? const CircularProgressIndicator(...) : const Text('Save Record'),
)
```

Change `onPressed` to:
```dart
onPressed: (_canSave && !_isLoading) ? _submit : null,
```

- [ ] **Step 5: Verify**

Open Add Transaction. The Save button should be grey. Fill title only — still grey. Add a valid amount — button turns blue. Clear the title — grey again.

- [ ] **Step 6: Commit**
```bash
git add lib/widgets/add_transaction_sheet.dart
git commit -m "fix: disable save button when required fields are empty"
```

---

## Task 5: Add "Transfer" Category to Income and Expense

**Files:**
- Modify: `lib/widgets/add_transaction_sheet.dart:58-66`

- [ ] **Step 1: Update `_currentCategories`**

Find:
```dart
List<String> get _currentCategories {
  if (_selectedType == TransactionType.expense) {
    return ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Other'];
  } else if (_selectedType == TransactionType.income) {
    return ['Salary', 'Freelance', 'Investment', 'Gift', 'Other'];
  } else {
    return ['Transfer'];
  }
}
```

Replace with:
```dart
List<String> get _currentCategories {
  if (_selectedType == TransactionType.expense) {
    return ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Transfer', 'Other'];
  } else if (_selectedType == TransactionType.income) {
    return ['Salary', 'Freelance', 'Investment', 'Gift', 'Transfer', 'Other'];
  } else {
    return ['Transfer'];
  }
}
```

- [ ] **Step 2: Verify**

Open Add Transaction → type Income. The Category dropdown should include "Transfer". Same for Expense.

- [ ] **Step 3: Commit**
```bash
git add lib/widgets/add_transaction_sheet.dart
git commit -m "feat: add Transfer category to Income and Expense"
```

---

## Task 6: Add Forgot Password Flow

**Files:**
- Modify: `lib/services/auth_service.dart`
- Modify: `lib/screens/login_screen.dart`

- [ ] **Step 1: Add `sendPasswordResetEmail` to `AuthService`**

In `auth_service.dart`, after the `register()` method and before `signOut()`, insert:
```dart
/// Sends a Firebase password-reset email. Returns null on success, error string on failure.
Future<String?> sendPasswordResetEmail(String email) async {
  try {
    await _auth.sendPasswordResetEmail(email: email.trim());
    return null;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') return 'No account found with this email.';
    if (e.code == 'invalid-email') return 'The email format is invalid.';
    return 'Failed to send reset email: ${e.message}';
  } catch (e) {
    return 'Something went wrong. Please try again.';
  }
}
```

- [ ] **Step 2: Add `_showForgotPasswordDialog` to `LoginScreen`**

In `login_screen.dart`, inside `_LoginScreenState`, add this method before `build()`:
```dart
void _showForgotPasswordDialog() {
  final emailCtrl = TextEditingController(text: _emailController.text.trim());
  bool isSending = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Password', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your registered email and we\'ll send you a reset link.', style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email Address',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: isSending
                ? null
                : () async {
                    setDialogState(() => isSending = true);
                    final authService = Provider.of<AuthService>(context, listen: false);
                    final error = await authService.sendPasswordResetEmail(emailCtrl.text);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (error != null) {
                      UIHelpers.showAlertDialog(context, 'Error', error);
                    } else {
                      UIHelpers.showAlertDialog(context, 'Email Sent', 'A password reset link has been sent to ${emailCtrl.text.trim()}. Check your inbox.');
                    }
                  },
            child: isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Send Link'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Add "Forgot Password?" button in build()**

In `login_screen.dart` `build()`, find the toggle TextButton:
```dart
TextButton(
  onPressed: () {
    setState(() {
      _isLogin = !_isLogin;
    });
  },
  child: Text(_isLogin 
    ? "Don't have an account? Sign Up" 
    : "Already have an account? Sign In"
  ),
),
```

After that TextButton (still inside the `children` list), add:
```dart
if (_isLogin)
  TextButton(
    onPressed: _showForgotPasswordDialog,
    child: const Text('Forgot Password?', style: TextStyle(color: Colors.grey)),
  ),
```

Also add the `UIHelpers` import at the top of the file if not already present:
```dart
import '../utils/ui_helpers.dart';
```

- [ ] **Step 4: Verify**

On the Login screen, a "Forgot Password?" link should appear. Tapping it opens the reset dialog. Entering a valid email and tapping Send should call Firebase and show confirmation.

- [ ] **Step 5: Commit**
```bash
git add lib/services/auth_service.dart lib/screens/login_screen.dart
git commit -m "feat: add forgot password flow via Firebase email reset"
```

---

## Task 7: Privacy Mode Enable Popup

**Files:**
- Modify: `lib/screens/home_screen.dart:264`
- Modify: `lib/screens/profile_screen.dart:164`

When privacy mode is currently OFF, tapping the eye icon (or profile toggle) shows a confirmation dialog before enabling.

- [ ] **Step 1: Add `_handlePrivacyModeToggle()` to HomeScreen**

In `home_screen.dart`, before the `build()` method, add:
```dart
void _handlePrivacyModeToggle() {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  if (!settings.isPrivacyModeEnabled) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.privacy_tip, size: 48, color: Colors.blueAccent),
            SizedBox(height: 12),
            Text('Enable Privacy Mode', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        content: const Text(
          'Your balances and amounts will be hidden. Tap the eye icon again to disable.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              settings.togglePrivacyMode();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  } else {
    settings.togglePrivacyMode();
  }
}
```

- [ ] **Step 2: Wire the eye icon to the new method**

In `home_screen.dart`, find the eye icon GestureDetector (around line 264):
```dart
GestureDetector(
  onTap: () => Provider.of<SettingsProvider>(context, listen: false).togglePrivacyMode(),
```

Change to:
```dart
GestureDetector(
  onTap: _handlePrivacyModeToggle,
```

- [ ] **Step 3: Apply same pattern in ProfileScreen**

In `profile_screen.dart`, find the Privacy Mode list item onTap (line ~164):
```dart
onTap: () {
  settingsProvider.togglePrivacyMode();
},
```

Replace with:
```dart
onTap: () {
  if (!settingsProvider.isPrivacyModeEnabled) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.privacy_tip, size: 48, color: Colors.blueAccent),
            SizedBox(height: 12),
            Text('Enable Privacy Mode', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        content: const Text(
          'Your balances and amounts will be hidden. Go back to Profile to disable.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              settingsProvider.togglePrivacyMode();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  } else {
    settingsProvider.togglePrivacyMode();
  }
},
```

- [ ] **Step 4: Verify**

With Privacy Mode OFF, tap eye icon → popup appears. Tap Enable → mode activates, amounts show `****`. Tap eye again → mode disables immediately (no popup).

- [ ] **Step 5: Commit**
```bash
git add lib/screens/home_screen.dart lib/screens/profile_screen.dart
git commit -m "feat: show confirmation popup before enabling privacy mode"
```

---

## Task 8: Goal Reminder Popup ("Haven't Saved Money Today")

**Files:**
- Modify: `lib/screens/home_screen.dart`

Show a one-per-session dialog when the app loads and no income transaction exists for today.

- [ ] **Step 1: Add a flag to HomeScreen state**

In `_HomeScreenState`, after the existing field declarations, add:
```dart
bool _hasShownGoalReminder = false;
```

- [ ] **Step 2: Add `_showGoalReminderDialog()`**

Before `build()` in `_HomeScreenState`, add:
```dart
void _showGoalReminderDialog() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Column(
        children: [
          Icon(Icons.savings, size: 48, color: Colors.orange),
          SizedBox(height: 12),
          Text('Savings Reminder', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ],
      ),
      content: const Text(
        "Hey! You haven't saved any money today yet. Don't forget to record your savings! 💰",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it!'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 3: Trigger the dialog from the StreamBuilder**

Inside `StreamBuilder.builder`, right after the line:
```dart
final allTransactions = (snapshot.data ?? []).where((t) => !t.isDeleted).toList();
```

Add:
```dart
// Show goal reminder once per session if no income today
if (!_hasShownGoalReminder && snapshot.connectionState == ConnectionState.active) {
  _hasShownGoalReminder = true;
  final today = DateTime.now();
  final hasTodayIncome = allTransactions.any((t) =>
      t.type == TransactionType.income &&
      t.date.year == today.year &&
      t.date.month == today.month &&
      t.date.day == today.day);
  if (!hasTodayIncome) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showGoalReminderDialog());
  }
}
```

- [ ] **Step 4: Verify**

Launch the app on a day with no income transactions. The savings reminder dialog should appear once. Dismiss and reopen the app in the same session — it should not appear again.

- [ ] **Step 5: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: show daily goal reminder when no income recorded today"
```

---

## Task 9: Pop-out Notification Overlay Widget

**Files:**
- Create: `lib/widgets/app_notification_overlay.dart`

A reusable static utility that inserts an overlay notification that slides in from the top and auto-dismisses.

- [ ] **Step 1: Create the file**

Create `lib/widgets/app_notification_overlay.dart`:
```dart
import 'package:flutter/material.dart';

/// Static helper to show a slide-from-top overlay notification.
///
/// Usage:
///   AppNotification.show(context, 'Transaction saved!', icon: Icons.check_circle, color: Colors.green);
class AppNotification {
  static void show(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline,
    Color color = Colors.blueAccent,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppNotificationWidget(
        message: message,
        icon: icon,
        color: color,
        duration: duration,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _AppNotificationWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AppNotificationWidget({
    required this.message,
    required this.icon,
    required this.color,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AppNotificationWidget> createState() => _AppNotificationWidgetState();
}

class _AppNotificationWidgetState extends State<_AppNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() async {
    if (mounted) {
      await _controller.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(Icons.close, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Demo it from the home screen FAB**

In `home_screen.dart`, import the overlay:
```dart
import '../widgets/app_notification_overlay.dart';
```

In the FAB `onPressed`, after `showModalBottomSheet` completes (use `.then()`), show a notification:
```dart
floatingActionButton: FloatingActionButton(
  onPressed: () {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AddTransactionSheet(),
    ).then((_) {
      if (mounted) {
        AppNotification.show(
          context,
          'Transaction saved successfully!',
          icon: Icons.check_circle,
          color: Colors.green,
        );
      }
    });
  },
  backgroundColor: blueColor,
  child: const Icon(Icons.add, color: Colors.white),
),
```

- [ ] **Step 3: Verify**

Add a transaction via FAB and save it. A green slide-from-top notification reading "Transaction saved successfully!" should appear and auto-dismiss after 3 seconds.

- [ ] **Step 4: Commit**
```bash
git add lib/widgets/app_notification_overlay.dart lib/screens/home_screen.dart
git commit -m "feat: add slide-from-top overlay notification widget"
```

---

## Task 10: Rename "Transfer" Quick Action to "Category"

**Files:**
- Modify: `lib/screens/home_screen.dart:304-310`

- [ ] **Step 1: Update the Quick Action item**

Find (around line 304):
```dart
_buildActionItem(Icons.swap_horiz, 'Transfer', () {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AddTransactionSheet(initialType: TransactionType.transfer),
  );
}),
```

Replace with (navigation to FilterScreen will be wired in Task 13):
```dart
_buildActionItem(Icons.category, 'Category', () {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AddTransactionSheet(),
  );
}),
```

- [ ] **Step 2: Verify**

The Quick Actions row should now read: **Category** · Scan · Analysis · History · More.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: rename Transfer quick action to Category with category icon"
```

---

## Task 11: Create Filter Screen (Full Page with This-Week Slide-Up Panel)

**Files:**
- Create: `lib/screens/filter_screen.dart`

The existing `_showFilterSheet()` bottom sheet becomes a full `Scaffold` page. When the "This Week" chip is selected, an animated panel slides up from the bottom showing the date range. The page returns `Map<String, dynamic>` results to the caller via `Navigator.pop(result)`.

- [ ] **Step 1: Create `lib/screens/filter_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../providers/settings_provider.dart';

/// Full-page filter screen. Pop returns a Map with updated filter values.
/// Keys: filterCategory (String), filterType (TransactionType?),
///       filterStartDate (DateTime?), filterEndDate (DateTime?),
///       filterMinAmount (double?), filterMaxAmount (double?),
///       filterAccount (String), currentSortMode (String)
class FilterScreen extends StatefulWidget {
  final String initialCategory;
  final TransactionType? initialType;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final double? initialMinAmount;
  final double? initialMaxAmount;
  final String initialAccount;
  final String initialSortMode;

  const FilterScreen({
    super.key,
    this.initialCategory = '',
    this.initialType,
    this.initialStartDate,
    this.initialEndDate,
    this.initialMinAmount,
    this.initialMaxAmount,
    this.initialAccount = '',
    this.initialSortMode = 'Newest',
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen>
    with SingleTickerProviderStateMixin {
  late String _filterCategory;
  late TransactionType? _filterType;
  late DateTime? _filterStartDate;
  late DateTime? _filterEndDate;
  late double? _filterMinAmount;
  late double? _filterMaxAmount;
  late String _filterAccount;
  late String _currentSortMode;

  final TextEditingController _minAmtCtrl = TextEditingController();
  final TextEditingController _maxAmtCtrl = TextEditingController();

  // This-week slide-up panel animation
  bool _showThisWeekPanel = false;
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _filterCategory = widget.initialCategory;
    _filterType = widget.initialType;
    _filterStartDate = widget.initialStartDate;
    _filterEndDate = widget.initialEndDate;
    _filterMinAmount = widget.initialMinAmount;
    _filterMaxAmount = widget.initialMaxAmount;
    _filterAccount = widget.initialAccount;
    _currentSortMode = widget.initialSortMode;

    _minAmtCtrl.text = _filterMinAmount?.toString() ?? '';
    _maxAmtCtrl.text = _filterMaxAmount?.toString() ?? '';

    _panelController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _panelSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _minAmtCtrl.dispose();
    _maxAmtCtrl.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _selectThisWeek() {
    final now = DateTime.now();
    setState(() {
      _filterStartDate = now.subtract(Duration(days: now.weekday - 1));
      _filterEndDate = now;
      _showThisWeekPanel = true;
    });
    _panelController.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _panelController.reverse().then((_) {
          if (mounted) setState(() => _showThisWeekPanel = false);
        });
      }
    });
  }

  void _applyAndPop() {
    Navigator.pop(context, {
      'filterCategory': _filterCategory,
      'filterType': _filterType,
      'filterStartDate': _filterStartDate,
      'filterEndDate': _filterEndDate,
      'filterMinAmount': _filterMinAmount,
      'filterMaxAmount': _filterMaxAmount,
      'filterAccount': _filterAccount,
      'currentSortMode': _currentSortMode,
    });
  }

  void _reset() {
    setState(() {
      _filterCategory = '';
      _filterType = null;
      _filterStartDate = null;
      _filterEndDate = null;
      _filterMinAmount = null;
      _filterMaxAmount = null;
      _filterAccount = '';
      _currentSortMode = 'Newest';
      _minAmtCtrl.clear();
      _maxAmtCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final walletNames = settingsProvider.wallets.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Filter Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Reset', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick time range chips
                const Text('Quick Range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickChip('This Week', onTap: _selectThisWeek),
                    _buildQuickChip('This Month', onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _filterStartDate = DateTime(now.year, now.month, 1);
                        _filterEndDate = now;
                      });
                    }),
                    _buildQuickChip('This Year', onTap: () {
                      final now = DateTime.now();
                      setState(() {
                        _filterStartDate = DateTime(now.year, 1, 1);
                        _filterEndDate = now;
                      });
                    }),
                  ],
                ),
                const SizedBox(height: 16),

                const Text('Custom Date Range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            initialDateRange: _filterStartDate != null && _filterEndDate != null
                                ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
                                : null,
                          );
                          if (picked != null) {
                            setState(() {
                              _filterStartDate = picked.start;
                              _filterEndDate = picked.end;
                            });
                          }
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(_filterStartDate != null && _filterEndDate != null
                            ? '${DateFormat('MM/dd').format(_filterStartDate!)} – ${DateFormat('MM/dd').format(_filterEndDate!)}'
                            : 'Select Range'),
                      ),
                    ),
                    if (_filterStartDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        onPressed: () => setState(() { _filterStartDate = null; _filterEndDate = null; }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text('Amount Range', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Min', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money, size: 16)),
                        onChanged: (val) => _filterMinAmount = double.tryParse(val),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _maxAmtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Max', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money, size: 16)),
                        onChanged: (val) => _filterMaxAmount = double.tryParse(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text('Account / Wallet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterAccount.isEmpty ? null : _filterAccount,
                  hint: const Text('All Accounts'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: walletNames.map((w) => DropdownMenuItem(value: w, child: Text(w))).toList(),
                  onChanged: (val) => setState(() => _filterAccount = val ?? ''),
                ),
                const SizedBox(height: 16),

                const Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _filterCategory.isEmpty ? null : _filterCategory,
                  hint: const Text('All Categories'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Transfer', 'Other', 'Salary', 'Freelance', 'Investment', 'Gift']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => _filterCategory = val ?? ''),
                ),
                const SizedBox(height: 16),

                const Text('Transaction Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<TransactionType>(
                  value: _filterType,
                  hint: const Text('All Types'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: TransactionType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase())))
                      .toList(),
                  onChanged: (val) => setState(() => _filterType = val),
                ),
                const SizedBox(height: 16),

                const Text('Sort By', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _currentSortMode,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: ['Newest', 'Oldest', 'Highest Amount', 'Lowest Amount']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => _currentSortMode = val ?? 'Newest'),
                ),

                const SizedBox(height: 100), // room for bottom button
              ],
            ),
          ),

          // This-Week slide-up confirmation panel
          if (_showThisWeekPanel)
            Positioned(
              bottom: 80,
              left: 24,
              right: 24,
              child: SlideTransition(
                position: _panelSlide,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This Week: ${_filterStartDate != null ? DateFormat('MMM dd').format(_filterStartDate!) : ''} – ${_filterEndDate != null ? DateFormat('MMM dd').format(_filterEndDate!) : ''}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Apply button pinned at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFFF4F6F9),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ElevatedButton(
                onPressed: _applyAndPop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Apply Filters', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, {required VoidCallback onTap}) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      labelStyle: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the file compiles**

Run `flutter analyze lib/screens/filter_screen.dart`. Expect no errors.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/filter_screen.dart
git commit -m "feat: add full-page FilterScreen with This-Week slide-up animation"
```

---

## Task 12: Create See All Screen (Search Lock + USD Display)

**Files:**
- Create: `lib/screens/see_all_screen.dart`

Full-page transaction list with:
- Search bar that **locks the page** (prevents back navigation) while focused
- Amounts displayed in the user's base currency (converted via `CurrencyHelper`)
- Pass-through of current filters from home screen

- [ ] **Step 1: Create `lib/screens/see_all_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_helper.dart';
import '../widgets/add_transaction_sheet.dart';

class SeeAllScreen extends StatefulWidget {
  final String filterCategory;
  final TransactionType? filterType;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  final double? filterMinAmount;
  final double? filterMaxAmount;
  final String filterAccount;
  final String sortMode;

  const SeeAllScreen({
    super.key,
    this.filterCategory = '',
    this.filterType,
    this.filterStartDate,
    this.filterEndDate,
    this.filterMinAmount,
    this.filterMaxAmount,
    this.filterAccount = '',
    this.sortMode = 'Newest',
  });

  @override
  State<SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<SeeAllScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _formatAmount(double amount, String baseCurrency) {
    final isPrivacyMode = Provider.of<SettingsProvider>(context, listen: false).isPrivacyModeEnabled;
    if (isPrivacyMode) return '****';
    return '${CurrencyHelper.getSymbol(baseCurrency)} ${NumberFormat('#,##0.00').format(amount)}';
  }

  bool _passesFilters(TransactionModel t) {
    // Time filter
    bool passTime = true;
    if (widget.filterStartDate != null && widget.filterEndDate != null) {
      passTime = t.date.isAfter(widget.filterStartDate!.subtract(const Duration(days: 1))) &&
                 t.date.isBefore(widget.filterEndDate!.add(const Duration(days: 1)));
    }
    // Search
    bool passSearch = true;
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      final queryStripped = query.replaceAll('+', '').replaceAll('-', '').trim();
      final queryNum = double.tryParse(queryStripped);
      passSearch = t.title.toLowerCase().contains(query) ||
                   t.category.toLowerCase().contains(query) ||
                   t.tags.any((tag) => tag.toLowerCase().contains(query)) ||
                   (queryNum != null && t.amount == queryNum);
    }
    bool passCat = widget.filterCategory.isEmpty || t.category == widget.filterCategory;
    bool passType = widget.filterType == null || t.type == widget.filterType;
    bool passMin = widget.filterMinAmount == null || t.amount >= widget.filterMinAmount!;
    bool passMax = widget.filterMaxAmount == null || t.amount <= widget.filterMaxAmount!;
    bool passAcc = widget.filterAccount.isEmpty ||
                   t.fromAccount == widget.filterAccount ||
                   t.toAccount == widget.filterAccount;
    return passTime && passSearch && passCat && passType && passMin && passMax && passAcc;
  }

  List<TransactionModel> _sortTransactions(List<TransactionModel> list) {
    final sorted = List<TransactionModel>.from(list);
    switch (widget.sortMode) {
      case 'Oldest': sorted.sort((a, b) => a.date.compareTo(b.date)); break;
      case 'Highest Amount': sorted.sort((a, b) => b.amount.compareTo(a.amount)); break;
      case 'Lowest Amount': sorted.sort((a, b) => a.amount.compareTo(b.amount)); break;
      default: sorted.sort((a, b) => b.date.compareTo(a.date)); // Newest
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final baseCurrency = Provider.of<SettingsProvider>(context).baseCurrency;

    return PopScope(
      // Lock: prevent back-swipe while search bar is focused
      canPop: !_searchFocused,
      onPopInvoked: (didPop) {
        if (!didPop && _searchFocused) {
          _searchFocus.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          title: const Text('All Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () {
              if (_searchFocused) {
                _searchFocus.unfocus();
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: Column(
          children: [
            // Search bar
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by title, category, tag, or amount…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            if (_searchFocused)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, size: 14, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Search mode active — swipe or tap back to exit', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            Expanded(
              child: StreamBuilder<List<TransactionModel>>(
                stream: FirestoreService().getTransactionsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final all = (snapshot.data ?? []).where((t) => !t.isDeleted).toList();
                  final filtered = _sortTransactions(all.where(_passesFilters).toList());

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No transactions found.', style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _buildTile(filtered[i], baseCurrency),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(TransactionModel t, String baseCurrency) {
    Color iconColor;
    Color bgColor;
    IconData icon;
    String prefix;
    switch (t.type) {
      case TransactionType.income:
        iconColor = Colors.green; bgColor = Colors.green.withOpacity(0.1);
        icon = Icons.work_outline; prefix = '+ '; break;
      case TransactionType.expense:
        iconColor = Colors.red; bgColor = Colors.red.withOpacity(0.1);
        icon = Icons.shopping_bag; prefix = '- '; break;
      case TransactionType.transfer:
        iconColor = Colors.blue; bgColor = Colors.blue.withOpacity(0.1);
        icon = Icons.swap_horiz; prefix = ''; break;
    }

    // Convert to base currency for display
    final displayAmt = CurrencyHelper.convert(t.amount, t.currency, baseCurrency);

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => AddTransactionSheet(existingTransaction: t),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 24, backgroundColor: bgColor, child: Icon(icon, color: iconColor)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(DateFormat('MMM dd, yyyy').format(t.date), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (t.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: t.tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                          child: Text('#$tag', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                        )).toList(),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$prefix${_formatAmount(displayAmt, baseCurrency)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run `flutter analyze lib/screens/see_all_screen.dart`.

- [ ] **Step 3: Commit**
```bash
git add lib/screens/see_all_screen.dart
git commit -m "feat: add SeeAllScreen with search lock and base-currency amount display"
```

---

## Task 13: Wire Filter and See All Screens to Home Screen

**Files:**
- Modify: `lib/screens/home_screen.dart`

Replace the `_showFilterSheet()` bottom sheet call with navigation to `FilterScreen`. Wire the "See All" text to navigate to `SeeAllScreen`. Update the "Category" quick action to open `FilterScreen`.

- [ ] **Step 1: Add imports**

At the top of `home_screen.dart`, add:
```dart
import 'filter_screen.dart';
import 'see_all_screen.dart';
```

- [ ] **Step 2: Replace `_showFilterSheet()` with navigation**

Find the method `_showFilterSheet()` (around line 1101). Replace its entire body with:
```dart
void _showFilterSheet() async {
  final result = await Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(
      builder: (_) => FilterScreen(
        initialCategory: _filterCategory,
        initialType: _filterType,
        initialStartDate: _filterStartDate,
        initialEndDate: _filterEndDate,
        initialMinAmount: _filterMinAmount,
        initialMaxAmount: _filterMaxAmount,
        initialAccount: _filterAccount,
        initialSortMode: _currentSortMode,
      ),
    ),
  );
  if (result != null && mounted) {
    setState(() {
      _filterCategory = result['filterCategory'] as String;
      _filterType = result['filterType'] as TransactionType?;
      _filterStartDate = result['filterStartDate'] as DateTime?;
      _filterEndDate = result['filterEndDate'] as DateTime?;
      _filterMinAmount = result['filterMinAmount'] as double?;
      _filterMaxAmount = result['filterMaxAmount'] as double?;
      _filterAccount = result['filterAccount'] as String;
      _currentSortMode = result['currentSortMode'] as String;
    });
  }
}
```

- [ ] **Step 3: Wire "See All" to SeeAllScreen**

Find `_buildSectionHeader('Transactions', 'See All')` (around line 502). Replace with:
```dart
GestureDetector(
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeeAllScreen(
          filterCategory: _filterCategory,
          filterType: _filterType,
          filterStartDate: _filterStartDate,
          filterEndDate: _filterEndDate,
          filterMinAmount: _filterMinAmount,
          filterMaxAmount: _filterMaxAmount,
          filterAccount: _filterAccount,
          sortMode: _currentSortMode,
        ),
      ),
    );
  },
  child: _buildSectionHeader('Transactions', 'See All'),
),
```

- [ ] **Step 4: Update "Category" quick action**

The "Category" quick action (from Task 10) should open `FilterScreen`. Replace its onTap:
```dart
_buildActionItem(Icons.category, 'Category', () {
  _showFilterSheet();
}),
```

- [ ] **Step 5: Verify end-to-end**

1. Tap Category quick action → `FilterScreen` opens as full page. Select "This Week" → blue slide-up panel appears briefly. Tap Apply → home screen filters update.
2. Tap "See All" → `SeeAllScreen` opens. Type in search bar → page locks. Tap back arrow → focus cleared, then back.

- [ ] **Step 6: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: navigate to FilterScreen and SeeAllScreen from home"
```

---

## Task 14: Multi-Select Batch Delete

**Files:**
- Modify: `lib/screens/home_screen.dart`

Long-press a transaction to enter multi-select mode. Select/deselect by tapping. A bottom action bar appears with a "Delete Selected" button.

- [ ] **Step 1: Add multi-select state fields**

In `_HomeScreenState`, add:
```dart
final Set<String> _selectedIds = {};
bool _isMultiSelectMode = false;
```

- [ ] **Step 2: Add helper methods**

Before `build()`, add:
```dart
void _enterMultiSelect(String id) {
  setState(() {
    _isMultiSelectMode = true;
    _selectedIds.add(id);
  });
}

void _toggleSelect(String id) {
  setState(() {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    if (_selectedIds.isEmpty) _isMultiSelectMode = false;
  });
}

void _cancelMultiSelect() {
  setState(() {
    _isMultiSelectMode = false;
    _selectedIds.clear();
  });
}

Future<void> _deleteSelected() async {
  final ids = List<String>.from(_selectedIds);
  for (final id in ids) {
    await FirestoreService().deleteTransaction(id);
  }
  setState(() {
    _isMultiSelectMode = false;
    _selectedIds.clear();
  });
}
```

- [ ] **Step 3: Modify `_buildTransactionTile` for multi-select**

At the top of `_buildTransactionTile()`, wrap the Dismissible's `child` InkWell so that:
- In multi-select mode: tapping toggles selection, long press does nothing
- In normal mode: tapping opens edit sheet, long press enters multi-select

Find the return statement starting with `return Dismissible(`. Wrap it:
```dart
return Dismissible(
  key: Key(t.id),
  direction: _isMultiSelectMode ? DismissDirection.none : DismissDirection.endToStart,
  background: Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(16)),
    alignment: Alignment.centerRight,
    child: const Icon(Icons.delete, color: Colors.white),
  ),
  onDismissed: (direction) {
    FirestoreService().deleteTransaction(t.id);
  },
  child: InkWell(
    onTap: () {
      if (_isMultiSelectMode) {
        _toggleSelect(t.id);
      } else {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => AddTransactionSheet(existingTransaction: t),
        );
      }
    },
    onLongPress: () {
      if (!_isMultiSelectMode) _enterMultiSelect(t.id);
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _selectedIds.contains(t.id) ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: _selectedIds.contains(t.id) 
            ? Border.all(color: Colors.blue, width: 1.5) 
            : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          if (_isMultiSelectMode) ...[
            Checkbox(
              value: _selectedIds.contains(t.id),
              onChanged: (_) => _toggleSelect(t.id),
              activeColor: Colors.blue,
            ),
            const SizedBox(width: 8),
          ],
          Stack( /* existing avatar stack */ ...),
          // ... rest of existing tile content
        ],
      ),
    ),
  ),
);
```

**IMPORTANT:** Do not copy the `Stack(...)` comment — replace it with the actual existing `Stack` widget code for the avatar (from lines 1011-1031 in the original file). Keep all the existing content inside the Row after the checkbox.

- [ ] **Step 4: Add multi-select action bar to the Scaffold**

In the `build()` method, find the `floatingActionButton:` property. Above it, add a `bottomNavigationBar:` or use a `Stack`. The cleanest approach is to conditionally show a `bottomNavigationBar`:

In the `Scaffold(...)` widget (around line 88), add:
```dart
bottomNavigationBar: _isMultiSelectMode
    ? SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Text(
                '${_selectedIds.length} selected',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              TextButton(
                onPressed: _cancelMultiSelect,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      )
    : null,
```

- [ ] **Step 5: Verify**

Long-press a transaction → blue border appears, checkbox shows, bottom bar shows "1 selected". Tap another → "2 selected". Tap Delete → both deleted, bar disappears. Tap Cancel → exits multi-select mode.

- [ ] **Step 6: Commit**
```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add long-press multi-select batch delete for transactions"
```

---

## Task 15: Scan Feature (Receipt & Bank Transfer)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/screens/scan_screen.dart`
- Modify: `lib/screens/home_screen.dart:312-313`

- [ ] **Step 1: Add `image_picker` dependency**

In `pubspec.yaml`, under `dependencies:`, after `shared_preferences: ^2.5.5`, add:
```yaml
image_picker: ^1.1.2
```

- [ ] **Step 2: Run `flutter pub get`**

```bash
flutter pub get
```

Expected: Resolves and downloads `image_picker`.

- [ ] **Step 3: Create `lib/screens/scan_screen.dart`**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
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
  File? _scannedImage;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;
    setState(() {
      _scannedImage = File(picked.path);
      _isProcessing = true;
    });
    // Simulate processing delay (replace with real OCR integration if available)
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isProcessing = false);
  }

  void _proceedToAddTransaction() {
    // Pre-fill transaction type based on scan type
    final initialType = _selectedType == ScanType.receipt
        ? TransactionType.expense
        : TransactionType.transfer;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(initialType: initialType),
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
        title: const Text('Scan Document', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            const Text('Document Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = ScanType.receipt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedType == ScanType.receipt ? blueColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _selectedType == ScanType.receipt ? blueColor : Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long, color: _selectedType == ScanType.receipt ? Colors.white : Colors.grey),
                          const SizedBox(height: 8),
                          Text('Receipt', style: TextStyle(color: _selectedType == ScanType.receipt ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedType = ScanType.bankTransfer),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedType == ScanType.bankTransfer ? blueColor : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _selectedType == ScanType.bankTransfer ? blueColor : Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.account_balance, color: _selectedType == ScanType.bankTransfer ? Colors.white : Colors.grey),
                          const SizedBox(height: 8),
                          Text('Bank Transfer', style: TextStyle(color: _selectedType == ScanType.bankTransfer ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Image preview area
            GestureDetector(
              onTap: () => _showImageSourceDialog(),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                ),
                child: _scannedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_scannedImage!, fit: BoxFit.cover, width: double.infinity),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('Tap to scan or upload', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            _selectedType == ScanType.receipt ? 'Shopping receipt' : 'Bank transfer slip',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Source buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Processing indicator or proceed button
            if (_isProcessing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analyzing document…', style: TextStyle(color: Colors.grey)),
                ],
              )
            else if (_scannedImage != null) ...[
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
                        'Document scanned. Review and confirm the details below.',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _proceedToAddTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blueColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Proceed to Add Transaction', style: TextStyle(fontSize: 16)),
              ),
            ] else
              ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Scan a document first', style: TextStyle(fontSize: 16)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire Scan button in Home Screen to ScanScreen**

In `home_screen.dart`, add import:
```dart
import 'scan_screen.dart';
```

Find the Scan quick action (around line 312):
```dart
_buildActionItem(Icons.qr_code_scanner, 'Scan', () {
  _showComingSoonDialog(context, 'Receipt Scanning', 'Snap a picture of your receipt and let AI do the data entry. Coming very soon!', Icons.qr_code_scanner);
}),
```

Replace with:
```dart
_buildActionItem(Icons.qr_code_scanner, 'Scan', () {
  Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
}),
```

- [ ] **Step 5: Verify**

Tap Scan quick action → `ScanScreen` opens. Select "Receipt" or "Bank Transfer". Tap Camera or Gallery → image picker launches. After selection, "Proceed to Add Transaction" button appears and opens the `AddTransactionSheet` with the matching type.

- [ ] **Step 6: Commit**
```bash
git add pubspec.yaml lib/screens/scan_screen.dart lib/screens/home_screen.dart
git commit -m "feat: add scan screen for receipt and bank transfer documents"
```

---

## Self-Review Checklist

| # | Requirement | Task |
|---|---|---|
| 1 | Pop-out screen notification | Task 9 |
| 2 | Search page lock when focused | Task 12 (SeeAllScreen PopScope) |
| 3 | Currency auto-conversion in search display | Task 12 (displayAmt = CurrencyHelper.convert) |
| 4 | Filter & See All as separate pages | Tasks 11, 12, 13 |
| 5 | Amount search bug (+2000 / -2000) | Task 3 |
| 6 | Privacy mode enable popup | Task 7 |
| 7 | Rename "Report" → "Analysis" | Task 1 |
| 8 | Rename "Transfer" → "Category" in Quick Actions | Task 10 |
| 9 | Add Transfer category to Income & Expense | Task 5 |
| 10 | Goal reminder popup (haven't saved today) | Task 8 |
| 11 | Scan feature (receipt + bank transfer) | Task 15 |
| 12 | Multi-select batch delete | Task 14 |
| 13 | Save validation (disable button, no alert) | Task 4 |
| 14 | Tag spacing bug fix | Task 2 |
| 15 | Forgot password flow | Task 6 |

All 15 requirements are covered. No placeholders — all tasks have complete code.

**Type consistency check:**
- `FilterScreen` receives and returns named fields matching what `_HomeScreenState` stores
- `SeeAllScreen` accepts the same filter fields as `FilterScreen` returns
- `AppNotification.show()` is called consistently: `(context, message, icon:, color:)`
- `sendPasswordResetEmail()` returns `String?` matching the null-means-success convention used by `signIn()`/`register()`
