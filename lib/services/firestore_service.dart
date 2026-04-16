import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user specific transactions collection
  CollectionReference get _userTransactions {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("User must be logged in to access database");
    }
    return _db.collection('users').doc(user.uid).collection('transactions');
  }

  // Add Transaction
  Future<void> addTransaction(TransactionModel transaction) async {
    await _userTransactions.add(transaction.toMap());
  }

  // Stream of Transactions ordered by date
  Stream<List<TransactionModel>> getTransactionsStream() {
    try {
      return _userTransactions
          .orderBy('date', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => TransactionModel.fromFirestore(doc))
              .toList());
    } catch (e) {
      // If user is not logged in, return an empty stream
      return Stream.value([]);
    }
  }
  // Update Transaction
  Future<void> updateTransaction(String id, TransactionModel transaction) async {
    await _userTransactions.doc(id).update(transaction.toMap());
  }
  
  // Delete Transaction (Soft Delete)
  Future<void> deleteTransaction(String id) async {
    await _userTransactions.doc(id).update({'isDeleted': true});
  }

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

  // Reassign all transactions from one wallet to another
  Future<void> reassignWalletTransactions(String oldWallet, String newWallet) async {
    try {
      final fromQuery = await _userTransactions.where('fromAccount', isEqualTo: oldWallet).get();
      for (var doc in fromQuery.docs) {
        await doc.reference.update({'fromAccount': newWallet});
      }
      
      final toQuery = await _userTransactions.where('toAccount', isEqualTo: oldWallet).get();
      for (var doc in toQuery.docs) {
        await doc.reference.update({'toAccount': newWallet});
      }
    } catch (e) {
      print('Error reassigning wallet: $e');
    }
  }

  // Add multiple transactions in a single batch
  Future<void> addTransactionsBatch(List<TransactionModel> transactions) async {
    if (transactions.isEmpty) return;
    final batch = _db.batch();
    for (var tx in transactions) {
      final docRef = _userTransactions.doc();
      batch.set(docRef, tx.toMap());
    }
    await batch.commit();
  }
}
