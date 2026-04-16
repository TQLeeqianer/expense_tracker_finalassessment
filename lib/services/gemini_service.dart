import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ignore: constant_identifier_names
const _kGeminiApiKey = 'yourapikeythanks';

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
You are a financial receipt analyzer. Analyze this image (receipt, bank statement, or transfer slip) and extract transaction details.

First, determine if this image contains valid transactions.
Return ONLY a valid JSON object matching exactly this schema:
{
  "transactions": [
    {
      "is_valid_document": <true if it looks like a valid transaction, false otherwise>,
      "amount": <positive number, the transaction total>,
      "currency": <ISO 4217 currency code, e.g. "MYR", "USD", "SGD">,
      "type": <"expense" if money is paid out, "income" if money is received>,
      "title": <merchant name or transfer description, max 50 chars>,
      "category": <exactly one of: Shopping, Food, Transport, Utilities, Entertainment, Health, Salary, Freelance, Investment, Gift, Transfer, Other>,
      "date": <date in YYYY-MM-DD format, or null if not visible>
    }
  ]
}

Rules:
- If you see a bank statement with multiple records, extract EVERY transaction into the array.
- If it's a single receipt/slip, return an array with exactly 1 item.
- For receipts (stores, restaurants): type is always "expense".
- For banking apps or transfer slips:
  * If the amount is preceded by a minus sign (e.g., "- 300.00"), or the UI indicates money went "To" someone else, or says "Money Sent" / "Debit", type is "expense".
  * If the transaction details contain words like "CREDIT", "IBG CREDIT", "Deposit", "Received", or shows a positive amount without explicitly indicating money was sent to others, type is "income".
- Detect currency from symbols: RM or MYR → "MYR", $ → "USD", S$ → "SGD", € → "EUR", ¥ → "JPY". If none assume MYR.
''';

  Future<List<ScanResult>> analyzeReceipt(Uint8List imageBytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
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

      // Super robust JSON extractor: Finds the first { or [ and the last } or ]
      String cleaned = text.trim();
      final firstBrace = cleaned.indexOf('{');
      final firstBracket = cleaned.indexOf('[');
      final lastBrace = cleaned.lastIndexOf('}');
      final lastBracket = cleaned.lastIndexOf(']');

      int startIdx = -1;
      int endIdx = -1;

      if (firstBrace != -1 && firstBracket != -1) {
        startIdx = firstBrace < firstBracket ? firstBrace : firstBracket;
      } else if (firstBrace != -1) {
        startIdx = firstBrace;
      } else if (firstBracket != -1) {
        startIdx = firstBracket;
      }

      if (lastBrace != -1 && lastBracket != -1) {
        endIdx = lastBrace > lastBracket ? lastBrace : lastBracket;
      } else if (lastBrace != -1) {
        endIdx = lastBrace;
      } else if (lastBracket != -1) {
        endIdx = lastBracket;
      }

      if (startIdx != -1 && endIdx != -1 && endIdx >= startIdx) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }

      dynamic parsedJson;
      try {
        parsedJson = jsonDecode(cleaned);
      } catch (_) {
        throw const GeminiScanException(
            'Could not read this image. Try a clearer photo.');
      }

      // Make it indestructible: AI might forget the wrapper and return a list or flat map directly
      List<dynamic> txs = [];
      if (parsedJson is Map) {
        if (parsedJson.containsKey('transactions') && parsedJson['transactions'] is List) {
          txs = parsedJson['transactions'] as List<dynamic>;
        } else if (parsedJson.containsKey('amount') || parsedJson.containsKey('is_valid_document')) {
          txs = [parsedJson];
        }
      } else if (parsedJson is List) {
        txs = parsedJson;
      }

      if (txs.isEmpty) {
        throw const GeminiScanException(
            'This image does not appear to contain any valid transactions. Please upload a correct document.');
      }

      List<ScanResult> results = [];
      for (var tx in txs) {
        if (tx is! Map) continue;
        if (tx['is_valid_document'] == false) continue;

        // Parse and validate amount heavily
        double? amount;
        final rawAmount = tx['amount'];
        if (rawAmount != null) {
          if (rawAmount is num) {
            amount = rawAmount.toDouble().abs();
          } else if (rawAmount is String) {
            // Strip out currency symbols or spaces if AI hallucinated them
            amount = double.tryParse(rawAmount.replaceAll(RegExp(r'[^0-9.]'), ''))?.abs();
          }
        }

        // Parse and validate type
        String? type = tx['type'] as String?;
        if (type != null && type != 'expense' && type != 'income') {
          type = null;
        }

        // Parse date
        DateTime? date;
        final rawDate = tx['date'] as String?;
        if (rawDate != null) {
          date = DateTime.tryParse(rawDate);
        }

        // Reject entirely empty entries
        if (amount == null && type == null && tx['title'] == null) {
          continue;
        }

        results.add(ScanResult(
          amount: amount,
          currency: tx['currency'] as String?,
          type: type,
          title: tx['title'] as String?,
          category: tx['category'] as String?,
          date: date,
        ));
      }

      if (results.isEmpty) {
        throw const GeminiScanException(
            'Could not read clear information from this image. Try a clearer photo.');
      }

      return results;
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

  Future<List<ScanResult>> analyzeBankStatementPdf(Uint8List pdfBytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: _kGeminiApiKey,
      );

      final content = [
        Content.multi([
          TextPart('''
You are a senior forensic financial analyst. 
Analyze this PDF bank statement Document.
Extract EVERY SINGLE valid physical transaction found across ALL pages. Ignore summary balances or headers.
Return ONLY a strictly valid JSON object matching this exact schema:
{
  "transactions": [
    {
      "is_valid_document": true,
      "amount": <positive float number>,
      "currency": <ISO 4217, e.g. "MYR">,
      "type": <"expense" if money out (e.g. Debit), "income" if money in (e.g. Credit/Deposit)>,
      "title": <merchant name or transaction short description, max 50 chars>,
      "category": <exactly one of: Shopping, Food, Transport, Utilities, Entertainment, Health, Salary, Freelance, Investment, Gift, Transfer, Other>,
      "date": <date in YYYY-MM-DD format>
    }
  ]
}
'''),
          DataPart('application/pdf', pdfBytes),
        ])
      ];

      final response = await model.generateContent(content);
      final text = response.text;

      if (text == null || text.trim().isEmpty) {
        throw const GeminiScanException('Could not read this PDF statement.');
      }

      // JSON parsing blocks
      String cleaned = text.trim();
      final firstBrace = cleaned.indexOf('{');
      final firstBracket = cleaned.indexOf('[');
      final lastBrace = cleaned.lastIndexOf('}');
      final lastBracket = cleaned.lastIndexOf(']');

      int startIdx = -1;
      int endIdx = -1;

      if (firstBrace != -1 && firstBracket != -1) {
        startIdx = firstBrace < firstBracket ? firstBrace : firstBracket;
      } else if (firstBrace != -1) {
        startIdx = firstBrace;
      } else if (firstBracket != -1) {
        startIdx = firstBracket;
      }

      if (lastBrace != -1 && lastBracket != -1) {
        endIdx = lastBrace > lastBracket ? lastBrace : lastBracket;
      } else if (lastBrace != -1) {
        endIdx = lastBrace;
      } else if (lastBracket != -1) {
        endIdx = lastBracket;
      }

      if (startIdx != -1 && endIdx != -1 && endIdx >= startIdx) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }

      dynamic parsedJson;
      try {
        parsedJson = jsonDecode(cleaned);
      } catch (_) {
        throw const GeminiScanException('Could not read this PDF correctly.');
      }

      List<dynamic> txs = [];
      if (parsedJson is Map) {
        if (parsedJson.containsKey('transactions') && parsedJson['transactions'] is List) {
          txs = parsedJson['transactions'] as List<dynamic>;
        } else if (parsedJson.containsKey('amount')) {
          txs = [parsedJson];
        }
      } else if (parsedJson is List) {
        txs = parsedJson;
      }

      if (txs.isEmpty) {
        throw const GeminiScanException('This PDF does not appear to contain any valid transactions.');
      }

      List<ScanResult> results = [];
      for (var tx in txs) {
        if (tx is! Map) continue;
        if (tx['is_valid_document'] == false) continue;

        double? amount;
        final rawAmount = tx['amount'];
        if (rawAmount != null) {
          if (rawAmount is num) amount = rawAmount.toDouble().abs();
          else if (rawAmount is String) amount = double.tryParse(rawAmount.replaceAll(RegExp(r'[^0-9.]'), ''))?.abs();
        }

        String? type = tx['type'] as String?;
        if (type != 'expense' && type != 'income') type = null;

        DateTime? date;
        final rawDate = tx['date'] as String?;
        if (rawDate != null) date = DateTime.tryParse(rawDate);

        if (amount == null && type == null && tx['title'] == null) continue;

        results.add(ScanResult(
          amount: amount,
          currency: tx['currency'] as String?,
          type: type,
          title: tx['title'] as String?,
          category: tx['category'] as String?,
          date: date,
        ));
      }

      if (results.isEmpty) {
        throw const GeminiScanException('Could not extract valid records from this PDF.');
      }

      return results;
    } on GeminiScanException { rethrow; }
    catch (e) {
      throw GeminiScanException('Failed to process PDF: $e');
    }
  }

  Future<String> getFinancialAdvice(Map<String, dynamic> summary) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _kGeminiApiKey,
      );

      final prompt = '''
You are an expert, friendly personal financial advisor. 
Analyze the following financial summary data of a user for the current time period.
Summary Data (JSON):
${jsonEncode(summary)}

Based on their top expenses, total net worth, and income vs expense ratio:
1. Briefly evaluate their financial health in a friendly, encouraging tone.
2. Highlight where their money is mostly going.
3. Provide 2-3 specific, actionable piece of advice to optimize their spending or boost savings based EXACTLY on their listed categories.
    
Use attractive, highly readable markdown formatting (bold text, bullet points, maybe a relevant emoji). Keep your response concise, around 3 short paragraphs. Output ONLY the markdown text.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw const GeminiScanException('Advisor failed to generate insights. Please try again.');
      }
      return text.trim();
    } catch (e) {
      if (e is GeminiScanException) rethrow;
      throw GeminiScanException('Could not connect to AI Advisor. Error: $e');
    }
  }
}
