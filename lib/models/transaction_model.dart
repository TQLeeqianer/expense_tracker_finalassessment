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
      amount: data['amount'] is num 
          ? (data['amount'] as num).toDouble() 
          : double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0,
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
