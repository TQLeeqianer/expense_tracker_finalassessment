# Gemini AI Receipt Scanning Design

**Date:** 2026-04-11
**Feature:** AI-powered receipt and bank transfer scanning using Google Gemini Vision

---

## Goal

Replace the manual amount-entry step in the Scan screen with automatic AI extraction. After a user uploads or photographs a receipt or bank transfer slip, Gemini analyzes the image and pre-fills all transaction fields. The user reviews the extracted values, edits any errors, and confirms to open the Add Transaction sheet fully pre-filled.

---

## Architecture

### New file
- `lib/services/gemini_service.dart` — API key constant, Gemini API call, prompt engineering, JSON parsing, `ScanResult` data class

### Modified files
- `lib/screens/scan_screen.dart` — replaces manual form with AI call + loading state + editable preview card
- `lib/widgets/add_transaction_sheet.dart` — add `initialTitle` (String?), `initialCategory` (String?), `initialDate` (DateTime?) parameters

### New dependency
- `google_generative_ai: ^0.4.6` added to `pubspec.yaml`

---

## GeminiService

### API key
Hardcoded as a private constant in `gemini_service.dart`:
```dart
const _kGeminiApiKey = 'YOUR_API_KEY_HERE';
```

### Model
`gemini-2.0-flash` — fast, cheap, strong multimodal vision capability.

### ScanResult data class
```dart
class ScanResult {
  final double? amount;
  final String? currency;   // ISO code e.g. 'MYR', 'USD'
  final String? type;       // 'expense' or 'income'
  final String? title;      // merchant name or transfer description
  final String? category;   // one of the app's category strings
  final DateTime? date;
}
```

### Prompt
The service sends the image bytes as inline data alongside this text prompt:

```
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
```

### Method signature
```dart
Future<ScanResult> analyzeReceipt(Uint8List imageBytes) async
```

Throws `GeminiScanException(String message)` on:
- API call failure (network error, quota exceeded)
- Response that is not valid JSON
- Response JSON missing all fields (completely unreadable image)

### JSON parsing
- Parse the response text as JSON
- Map fields to `ScanResult`, treating missing/null fields as `null`
- Parse `date` string with `DateTime.tryParse()`
- Validate `type` is `'expense'` or `'income'`; if neither, set to `null`
- Validate `amount` is positive; if zero or negative, set to `null`

---

## ScanScreen UI Flow

### States
1. **Initial** — document type selector (Receipt / Bank Transfer) + image preview area + Camera/Gallery buttons
2. **Loading** — full-area spinner with "Analyzing with AI…" text; Camera/Gallery buttons disabled
3. **Preview** — editable fields showing extracted values; "Confirm & Add" button
4. **Error** — SnackBar showing the error message + fallback to manual entry (show amount field + type selector as before)

### Preview card fields (all editable)
Each field is an inline editable widget (tappable to edit):
- **Type** — SegmentedButton: Expense / Income
- **Title** — TextField pre-filled with `result.title ?? ''`
- **Amount** — TextField (numeric) pre-filled with `result.amount?.toStringAsFixed(2) ?? ''`
- **Currency** — DropdownButtonFormField pre-filled with `result.currency ?? baseCurrency`
- **Category** — DropdownButtonFormField pre-filled with `result.category ?? 'Other'`
- **Date** — date picker pre-filled with `result.date ?? DateTime.now()`

### "Confirm & Add" button
Opens `AddTransactionSheet` with all pre-filled values:
```dart
AddTransactionSheet(
  initialType: type == 'income' ? TransactionType.income : TransactionType.expense,
  initialAmount: amount,
  initialTitle: title,
  initialCategory: category,
  initialDate: date,
)
```

### Error handling
- Network/API errors → SnackBar: "Could not analyze image. Please fill in manually." → show manual fallback fields
- Partial extraction (some fields null) → still show preview card with null fields left blank for user to fill
- Invalid/unreadable image → SnackBar: "Could not read this image. Try a clearer photo." → manual fallback

---

## AddTransactionSheet Changes

Add three new optional parameters:
- `final String? initialTitle`
- `final String? initialCategory`
- `final DateTime? initialDate`

In `initState`, after the existing `initialAmount` pre-fill block:
```dart
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

---

## Dependency

Add to `pubspec.yaml` under `dependencies`:
```yaml
google_generative_ai: ^0.4.6
```

Run `flutter pub get` after adding.

---

## Error States Summary

| Situation | Behaviour |
|-----------|-----------|
| Network error | SnackBar error + manual fallback fields |
| Gemini quota exceeded | SnackBar "AI quota exceeded. Fill manually." + fallback |
| Image unreadable / not a receipt | SnackBar "Could not read image." + fallback |
| Partial extraction (some null fields) | Show preview card, null fields left blank |
| User edits extracted value | Field updates locally before confirm |

---

## Out of Scope

- Real-time streaming of Gemini response (overkill for this use case)
- Storing the scanned image in Firebase Storage
- Training a custom OCR model
- Camera preview / live scanning (uses gallery/camera picker only)
