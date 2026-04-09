class CurrencyHelper {
  static const Map<String, double> mockRates = {
    'USD': 1.0,
    'MYR': 4.75,
    'EUR': 0.92,
    'CNY': 7.23,
    'GBP': 0.79,
  };

  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'MYR': 'RM',
    'EUR': '€',
    'CNY': '¥',
    'GBP': '£',
  };

  static List<String> get availableCurrencies => mockRates.keys.toList();

  static double convert(double amount, String fromCurrency, String toCurrency) {
    if (fromCurrency == toCurrency) return amount;
    
    double fromRate = mockRates[fromCurrency] ?? 1.0;
    double toRate = mockRates[toCurrency] ?? 1.0;
    
    // First convert to USD base, then to target currency
    double amountInUsd = amount / fromRate;
    return amountInUsd * toRate;
  }

  static String getSymbol(String currencyCode) {
    return currencySymbols[currencyCode] ?? '\$';
  }
}
