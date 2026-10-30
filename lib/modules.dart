import 'package:flutter/material.dart';

import 'kit.dart';
import 'screens/buyers_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/materials_screen.dart';
import 'screens/new_bill_screen.dart';
import 'screens/profit_screen.dart';
import 'screens/purchases_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/scans_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/wages_screen.dart';
import 'screens/workforce_screen.dart';

/// One screen of the desktop's sidebar, in the same order.
class Module {
  const Module(this.id, this.label, this.emoji, this.build);
  final String id;
  final String label;
  final String emoji;
  final Widget Function(BuildContext) build;
}

final modules = <Module>[
  Module('home', 'Home', '🏠', (_) => const HomeScreen()),
  Module('bill', 'New Bill', '🧾', (_) => const NewBillScreen()),
  Module('stock', 'Stock', '📦', (_) => const StockScreen()),
  Module('buyers', 'Buyers', '👤', (_) => const BuyersScreen()),
  Module('history', 'Bill History', '📜', (_) => const HistoryScreen()),
  Module('reports', 'Reports', '📊', (_) => const ReportsScreen()),
  Module('workforce', 'Workforce', '👷', (_) => const WorkforceScreen()),
  // The desktop's 3D Lab opens a web viewer; the phone's part of it is capturing scans.
  Module('lab', '3D Lab', '🧊', (c) {
    final s = AppScope.of(c);
    return ScansScreen(session: s.session, onSignOut: s.onSignOut);
  }),
  Module('materials', 'Materials', '🌳', (_) => const MaterialsScreen()),
  Module('purchases', 'Purchases', '🛒', (_) => const PurchasesScreen()),
  Module('staff', 'Staff', '👥', (_) => const StaffScreen()),
  Module('wages', 'Wages', '💰', (_) => const WagesScreen()),
  Module('expenses', 'Expenses', '💸', (_) => const ExpensesScreen()),
  Module('profit', 'Profit', '💹', (_) => const ProfitScreen()),
];
