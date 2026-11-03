import 'package:flutter/material.dart';

import 'kit.dart';
import 'screens/budgets_screen.dart';
import 'screens/buyers_screen.dart';
import 'screens/designs_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/letters_screen.dart';
import 'screens/machines_screen.dart';
import 'screens/materials_screen.dart';
import 'screens/new_bill_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/places_screen.dart';
import 'screens/profit_screen.dart';
import 'screens/purchases_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/restoration_screen.dart';
import 'screens/scans_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/wages_screen.dart';
import 'screens/workforce_screen.dart';

/// One screen of the desktop's sidebar. [section] is the heading it sits under (Home has none).
class Module {
  const Module(this.id, this.label, this.emoji, this.build, {this.section});
  final String id;
  final String label;
  final String emoji;
  final String? section;
  final Widget Function(BuildContext) build;
}

/// Same order, headings and names as the desktop's side panel (NAV_ITEMS and NAV_SECTIONS in
/// its main_window.py): every screen the desktop has.
final modules = <Module>[
  Module('home', 'Home', '🏠', (_) => const HomeScreen()),
  Module('bill', 'New Bill', '🧾', (_) => const NewBillScreen(), section: 'Selling'),
  Module('history', 'Bill History', '📜', (_) => const HistoryScreen(), section: 'Selling'),
  Module('orders', 'Orders', '📋', (_) => const OrdersScreen(), section: 'Selling'),
  Module('buyers', 'Buyers', '👤', (_) => const BuyersScreen(), section: 'Selling'),
  Module('letters', 'Letters', '✉️', (_) => const LettersScreen(), section: 'Selling'),
  Module('stock', 'Stock', '📦', (_) => const StockScreen(), section: 'Stock and buying'),
  Module('materials', 'Materials', '🌳', (_) => const MaterialsScreen(), section: 'Stock and buying'),
  Module('purchases', 'Purchases', '🛒', (_) => const PurchasesScreen(), section: 'Stock and buying'),
  Module('places', 'Places', '📍', (_) => const PlacesScreen(), section: 'Stock and buying'),
  // The desktop's 3D Lab opens a web viewer; the phone's part of it is capturing scans.
  Module('lab', '3D Lab', '🧊', (c) {
    final s = AppScope.of(c);
    return ScansScreen(session: s.session, onSignOut: s.onSignOut);
  }, section: 'Workshop'),
  Module('restoration', 'Restoration', '🏛️', (_) => const RestorationScreen(), section: 'Workshop'),
  Module('designs', 'Designs', '🎨', (_) => const DesignsScreen(), section: 'Workshop'),
  Module('machines', 'Machines and tools', '🛠️', (_) => const MachinesScreen(), section: 'Workshop'),
  Module('workforce', 'Attendance', '👷', (_) => const WorkforceScreen(), section: 'People and pay'),
  Module('wages', 'Wages', '💰', (_) => const WagesScreen(), section: 'People and pay'),
  Module('staff', 'Staff', '👥', (_) => const StaffScreen(), section: 'People and pay'),
  Module('expenses', 'Expenses', '💸', (_) => const ExpensesScreen(), section: 'Money'),
  Module('profit', 'Profit', '💹', (_) => const ProfitScreen(), section: 'Money'),
  Module('budgets', 'Budgets', '🎯', (_) => const BudgetsScreen(), section: 'Money'),
  Module('reports', 'Reports', '📊', (_) => const ReportsScreen(), section: 'Money'),
];
