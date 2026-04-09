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
}
