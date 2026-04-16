import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  final apiKey = 'AIzaSyDyqZadEO_dXCCUN_MRltUzGXxZIUiQf44'; 
  try {
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
    final response = await model.generateContent([Content.text('Hello')]);
    print('SUCCESS: ' + (response.text ?? ''));
  } catch (e) {
    print('ACTUAL_ERROR_MSG_BEGIN');
    print(e.toString());
    print('ACTUAL_ERROR_MSG_END');
  }
}
