class CurrencyHelper {
  static const Map<String, double> mockRates = {
    'USD': 1.0, 'MYR': 4.75, 'EUR': 0.92, 'CNY': 7.23, 'GBP': 0.79,
    'JPY': 151.3, 'KRW': 1350.5, 'AUD': 1.53, 'CAD': 1.35, 'SGD': 1.34,
    'INR': 83.2, 'CHF': 0.90, 'HKD': 7.82, 'NZD': 1.66, 'ZAR': 18.7,
    'THB': 36.5, 'IDR': 15800.0, 'VND': 25000.0, 'PHP': 56.4, 'TWD': 32.1,
    'BRL': 5.05, 'MXN': 16.5, 'RUB': 92.5, 'TRY': 32.0, 'AED': 3.67,
    'SAR': 3.75, 'SEK': 10.6, 'NOK': 10.8, 'DKK': 6.8, 'PLN': 3.96,
  };

  static const Map<String, String> currencySymbols = {
    'USD': '\$', 'MYR': 'RM', 'EUR': '€', 'CNY': '¥', 'GBP': '£',
    'JPY': '¥', 'KRW': '₩', 'AUD': 'A\$', 'CAD': 'C\$', 'SGD': 'S\$',
    'INR': '₹', 'CHF': 'CHF', 'HKD': 'HK\$', 'NZD': 'NZ\$', 'ZAR': 'R',
    'THB': '฿', 'IDR': 'Rp', 'VND': '₫', 'PHP': '₱', 'TWD': 'NT\$',
    'BRL': 'R\$', 'MXN': '\$', 'RUB': '₽', 'TRY': '₺', 'AED': 'د.إ',
    'SAR': '﷼', 'SEK': 'kr', 'NOK': 'kr', 'DKK': 'kr', 'PLN': 'zł',
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
