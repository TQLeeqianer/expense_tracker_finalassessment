import 'dart:convert';
void main() {
  String walletsJson = '{"Default": null}';
  final decodedJson = jsonDecode(walletsJson) as Map<String, dynamic>;
  try {
    final wallets = decodedJson.map((key, value) => MapEntry(key, (value as num).toDouble()));
    print(wallets);
  } catch (e) {
    print(e);
  }
}
