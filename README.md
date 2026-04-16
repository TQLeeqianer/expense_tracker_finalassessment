# 📈 Enterprise-Grade Financial Dashboard

## 🌟 Overview
A high-performance, data-driven financial tracking application built with Flutter and Firebase. Designed with enterprise-grade UX/UI principles, this dashboard provides robust transaction management, multi-currency support, advanced privacy controls, and a highly optimized rendering architecture.

## ✨ Key Features

### 1. High-Density "Sliver" Architecture
- **Collapsible Header (`SliverAppBar`)**: Maximizes screen real estate. The deep blue command center provides quick access to actions (Transfer, Scan, Report) but dynamically collapses into a pinned "Total Net Worth" header as the user scrolls down.
- **Infinite Smooth Scrolling**: Replaced traditional static columns with Flutter's advanced `CustomScrollView` and `SliverList.builder`. This guarantees 60-120 FPS fluid scrolling even when rendering thousands of historical transaction records by recycling off-screen elements.

### 2. Multi-Currency Settlement Engine
- **Native Currency Identity**: Every transaction strictly holds both a numeric `<Amount>` and a `<Currency Code>` (e.g., USD, MYR, EUR). 
- **Global Base Conversion**: Built-in `CurrencyHelper` engine allowing users to select a base dashboard currency. All distinct transactions are normalized and aggregated through this engine before rendering the Total Net Worth and Cashflow breakdown charts.

### 3. Ultimate Privacy Shield
- **Public-Safe Viewing**: Integrated a global "Eye Icon" privacy toggle specifically designed for the financial sector. 
- **Zero-Leak Obscuration**: Upon activation, an interception layer (`_formatAmount`) masks all sensitive outputs (Total Assets, Wallet Balances, individual transaction amounts) into `****`, eliminating data exposure in public spaces like subways or cafes.

### 4. Advanced Funneling & Search Engine
- **Multi-Dimensional Querying**: Users can instantly filter records via:
  - Global Search (String matching algorithms on Title and Tags)
  - Date Range Filtering (Cashflow timeframes)
  - Amount Range Constraints (Min/Max value matching)
  - Type & Category Isolation (Income vs. Expense vs. Transfer)
- **Dynamic Sorting**: Intelligent arrangement layers logic (Newest, Oldest, Highest Amount, Lowest Amount) for complex audit-ready reviews.

### 5. Pixel-Perfect UX Redesign
- **WCAG Compliant Typography**: Deep contrast ratios ensuring outdoor readability, with strict adherence to kerning offsets (e.g., matching padding between `+$` and `-$`).
- **Cognitive Load Reduction**: Eliminated redundant Floating Action Buttons. The unified `Transfer` routing intercepts intent and pre-selects the context inside the `AddTransactionSheet`.
- **Title Case Formatting**: Input strictness enforced at the framework level, automatically capitalizing unformatted user entries (e.g., `uber eats` → `Uber Eats`) to maintain ledger reporting aesthetics.

## 🛠 Technology Stack

* **Framework:** Flutter SDK
* **Language:** Dart
* **Backend as a Service (BaaS):** 
  * Firebase Authentication (Secure session management)
  * Firebase Cloud Firestore (NoSQL Realtime Database for instant transaction syncing)
* **State Management:** `Provider` (Global Auth State) and optimized localized `setState` aggregations.
* **Localization & Formatting:** `intl` library for deep DateTime and financial digit structuring.

## 📂 Project Structure

```text
lib/
 ├── main.dart                  # Application entry point & Theme Configuration
 ├── models/         
 │    └── transaction_model.dart # Abstract data structures and Firestore mappers
 ├── screens/
 │    ├── login_screen.dart      # Enterprise Auth Guard
 │    └── home_screen.dart       # Core Dashboard (Slivers, Aggregation, Filtering)
 ├── services/
 │    ├── auth_service.dart      # Firebase Authentication logic
 │    └── firestore_service.dart # CRUD operations for the Ledger
 ├── utils/
 │    └── currency_helper.dart   # Multi-currency mappings and conversion engine
 └── widgets/
      └── add_transaction_sheet.dart # Transaction entry form 
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK installed (Verify using `flutter doctor`)
- An Android Emulator, iOS Simulator, or physical device with USB Debugging enabled.
- A configured Firebase project containing `google-services.json` (Android) / `GoogleService-Info.plist` (iOS).

### Installation
1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Run the application:
   ```bash
   flutter run
   ```
