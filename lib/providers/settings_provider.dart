import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsProvider extends ChangeNotifier {
  String? _userId;

  String _baseCurrency = 'MYR';
  List<String> _activeCurrencies = ['USD', 'MYR', 'EUR', 'SGD', 'JPY'];
  List<String> _activeTags = ['Personal', 'Business', 'Trip', 'Family', 'Software', 'Food'];
  List<String> _expenseCategories = ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Other'];
  List<String> _incomeCategories = ['Salary', 'Freelance', 'Investment', 'Gift', 'Other'];
  bool _isPrivacyModeEnabled = false;
  String? _profileImagePath;
  double _monthlySavingsGoal = 0.0;
  String _savingsTag = 'Saving';

  Map<String, double> _wallets = {
    'Default Wallet': 0.0,
  };

  String get baseCurrency => _baseCurrency;
  List<String> get activeCurrencies => _activeCurrencies;
  List<String> get activeTags => _activeTags;
  List<String> get expenseCategories => _expenseCategories;
  List<String> get incomeCategories => _incomeCategories;
  bool get isPrivacyModeEnabled => _isPrivacyModeEnabled;
  String? get profileImagePath => _profileImagePath;
  double get monthlySavingsGoal => _monthlySavingsGoal;
  String get savingsTag => _savingsTag;
  Map<String, double> get wallets => _wallets;

  void updateUser(String? userId) {
    if (_userId != userId) {
      _userId = userId;
      if (_userId != null && _userId!.isNotEmpty) {
        _loadSettingsFromFirestore();
      } else {
        _resetToDefaults();
      }
    }
  }

  void _resetToDefaults() {
    _baseCurrency = 'MYR';
    _activeCurrencies = ['USD', 'MYR', 'EUR', 'SGD', 'JPY'];
    _activeTags = ['Personal', 'Business', 'Trip', 'Family', 'Software', 'Food'];
    _expenseCategories = ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Other'];
    _incomeCategories = ['Salary', 'Freelance', 'Investment', 'Gift', 'Other'];
    _isPrivacyModeEnabled = false;
    _profileImagePath = null;
    _monthlySavingsGoal = 0.0;
    _savingsTag = 'Saving';
    _wallets = {'Default Wallet': 0.0};
    notifyListeners();
  }

  Future<void> _loadSettingsFromFirestore() async {
    if (_userId == null || _userId!.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('settings')
          .doc('preferences')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _baseCurrency = data['baseCurrency'] ?? 'MYR';
        _activeCurrencies = List<String>.from(data['activeCurrencies'] ?? ['USD', 'MYR', 'EUR', 'SGD', 'JPY']);
        _activeTags = List<String>.from(data['activeTags'] ?? ['Personal', 'Business', 'Trip', 'Family', 'Software', 'Food']);
        _expenseCategories = List<String>.from(data['expenseCategories'] ?? ['Shopping', 'Food', 'Transport', 'Utilities', 'Entertainment', 'Health', 'Other']);
        _incomeCategories = List<String>.from(data['incomeCategories'] ?? ['Salary', 'Freelance', 'Investment', 'Gift', 'Other']);
        _isPrivacyModeEnabled = data['isPrivacyModeEnabled'] ?? false;
        _profileImagePath = data['profileImagePath'];
        _monthlySavingsGoal = data['monthlySavingsGoal'] is num 
            ? (data['monthlySavingsGoal'] as num).toDouble() 
            : 0.0;
        _savingsTag = data['savingsTag'] ?? 'Saving';
        
        if (data['userWallets'] != null) {
          final Map<String, dynamic> wData = data['userWallets'];
          _wallets = wData.map((key, value) {
            double parsedVal = 0.0;
            if (value is num) parsedVal = value.toDouble();
            if (value is String) parsedVal = double.tryParse(value) ?? 0.0;
            return MapEntry(key, parsedVal);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading settings from Firestore: $e');
    }
    
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    if (_userId == null || _userId!.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('settings')
          .doc('preferences')
          .set({
        'baseCurrency': _baseCurrency,
        'activeCurrencies': _activeCurrencies,
        'activeTags': _activeTags,
        'expenseCategories': _expenseCategories,
        'incomeCategories': _incomeCategories,
        'isPrivacyModeEnabled': _isPrivacyModeEnabled,
        'profileImagePath': _profileImagePath,
        'monthlySavingsGoal': _monthlySavingsGoal,
        'savingsTag': _savingsTag,
        'userWallets': _wallets,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving settings to Firestore: $e');
    }
  }

  void setProfileImage(String path) {
    _profileImagePath = path;
    notifyListeners();
    _saveSettings();
  }
  
  void setMonthlySavingsGoal(double value) {
    _monthlySavingsGoal = value;
    notifyListeners();
    _saveSettings();
  }

  void setSavingsTag(String tag) {
    if (_savingsTag != tag) {
      _savingsTag = tag;
      if (tag.isNotEmpty && !_activeTags.contains(tag)) {
        _activeTags.add(tag);
      }
      notifyListeners();
      _saveSettings();
    }
  }

  void setBaseCurrency(String currencyCode) {
    if (_baseCurrency != currencyCode) {
      _baseCurrency = currencyCode;
      if (!_activeCurrencies.contains(currencyCode)) {
        _activeCurrencies.add(currencyCode);
      }
      notifyListeners();
      _saveSettings();
    }
  }

  void addTag(String tag) {
    if (tag.isNotEmpty && !_activeTags.contains(tag)) {
      _activeTags.add(tag);
      notifyListeners();
      _saveSettings();
    }
  }

  void removeTag(String tag) {
    if (_activeTags.contains(tag)) {
      _activeTags.remove(tag);
      notifyListeners();
      _saveSettings();
    }
  }

  void addExpenseCategory(String category) {
    if (category.isNotEmpty && !_expenseCategories.contains(category)) {
      _expenseCategories.add(category);
      notifyListeners();
      _saveSettings();
    }
  }

  void removeExpenseCategory(String category) {
    if (_expenseCategories.contains(category) && _expenseCategories.length > 1) {
      _expenseCategories.remove(category);
      notifyListeners();
      _saveSettings();
    }
  }

  void addIncomeCategory(String category) {
    if (category.isNotEmpty && !_incomeCategories.contains(category)) {
      _incomeCategories.add(category);
      notifyListeners();
      _saveSettings();
    }
  }

  void removeIncomeCategory(String category) {
    if (_incomeCategories.contains(category) && _incomeCategories.length > 1) {
      _incomeCategories.remove(category);
      notifyListeners();
      _saveSettings();
    }
  }

  void addWallet(String idName, double initialBalance) {
    if (!_wallets.containsKey(idName)) {
      _wallets[idName] = initialBalance;
      notifyListeners();
      _saveSettings();
    }
  }

  void deleteWallet(String walletName) {
    if (_wallets.containsKey(walletName) && _wallets.length > 1) {
      _wallets.remove(walletName);
      notifyListeners();
      _saveSettings();
    }
  }

  void editWallet(String oldName, String newName) {
    if (_wallets.containsKey(oldName) && !_wallets.containsKey(newName) && newName.trim().isNotEmpty) {
      final balance = _wallets.remove(oldName)!;
      _wallets[newName] = balance;
      notifyListeners();
      _saveSettings();
    }
  }

  void toggleCurrency(String currencyCode, bool isActive) {
    if (isActive) {
      if (!_activeCurrencies.contains(currencyCode)) {
        _activeCurrencies.add(currencyCode);
        notifyListeners();
        _saveSettings();
      }
    } else {
      if (_activeCurrencies.contains(currencyCode) && _activeCurrencies.length > 1) {
        _activeCurrencies.remove(currencyCode);
        // Ensure baseCurrency is still valid
        if (_baseCurrency == currencyCode) {
          _baseCurrency = _activeCurrencies.first;
        }
        notifyListeners();
        _saveSettings();
      }
    }
  }


  void togglePrivacyMode() {
    _isPrivacyModeEnabled = !_isPrivacyModeEnabled;
    notifyListeners();
    _saveSettings();
  }
}
