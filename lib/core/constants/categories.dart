import 'package:flutter/material.dart';
import 'package:pet/data/models/category.dart';

final List<Category> defaultCategories = [
  // Expense categories
  Category(
    id: 'cat_food',
    name: 'Food & Dining',
    icon: Icons.restaurant,
    color: const Color(0xFFFF6B6B),
    type: 'expense',
  ),
  Category(
    id: 'cat_transport',
    name: 'Transport',
    icon: Icons.directions_car,
    color: const Color(0xFF4ECDC4),
    type: 'expense',
  ),
  Category(
    id: 'cat_bills',
    name: 'Bills & Utilities',
    icon: Icons.receipt_long,
    color: const Color(0xFFFFE66D),
    type: 'expense',
  ),
  Category(
    id: 'cat_shopping',
    name: 'Shopping',
    icon: Icons.shopping_bag,
    color: const Color(0xFFA78BFA),
    type: 'expense',
  ),
  Category(
    id: 'cat_health',
    name: 'Health',
    icon: Icons.local_hospital,
    color: const Color(0xFF22D3EE),
    type: 'expense',
  ),
  Category(
    id: 'cat_entertainment',
    name: 'Entertainment',
    icon: Icons.movie,
    color: const Color(0xFFF472B6),
    type: 'expense',
  ),
  Category(
    id: 'cat_education',
    name: 'Education',
    icon: Icons.school,
    color: const Color(0xFF60A5FA),
    type: 'expense',
  ),
  Category(
    id: 'cat_groceries',
    name: 'Groceries',
    icon: Icons.local_grocery_store,
    color: const Color(0xFF34D399),
    type: 'expense',
  ),
  Category(
    id: 'cat_rent',
    name: 'Rent',
    icon: Icons.home,
    color: const Color(0xFFFB923C),
    type: 'expense',
  ),
  Category(
    id: 'cat_recharge',
    name: 'Recharge & DTH',
    icon: Icons.phone_android,
    color: const Color(0xFF818CF8),
    type: 'expense',
  ),
  Category(
    id: 'cat_emi',
    name: 'EMI & Loans',
    icon: Icons.account_balance,
    color: const Color(0xFFEF4444),
    type: 'expense',
  ),
  Category(
    id: 'cat_other_expense',
    name: 'Other Expense',
    icon: Icons.more_horiz,
    color: const Color(0xFF94A3B8),
    type: 'expense',
  ),

  // Income categories
  Category(
    id: 'cat_salary',
    name: 'Salary',
    icon: Icons.account_balance_wallet,
    color: const Color(0xFF10B981),
    type: 'income',
  ),
  Category(
    id: 'cat_freelance',
    name: 'Freelance',
    icon: Icons.work,
    color: const Color(0xFF06B6D4),
    type: 'income',
  ),
  Category(
    id: 'cat_investment',
    name: 'Investment Returns',
    icon: Icons.trending_up,
    color: const Color(0xFF8B5CF6),
    type: 'income',
  ),
  Category(
    id: 'cat_gift_income',
    name: 'Gift / Reward',
    icon: Icons.card_giftcard,
    color: const Color(0xFFF59E0B),
    type: 'income',
  ),
  Category(
    id: 'cat_refund',
    name: 'Refund',
    icon: Icons.replay,
    color: const Color(0xFF14B8A6),
    type: 'income',
  ),
  Category(
    id: 'cat_other_income',
    name: 'Other Income',
    icon: Icons.attach_money,
    color: const Color(0xFF6B7280),
    type: 'income',
  ),
  // Money a person sent you (a friend paying back, family): shown and
  // tracked, but not counted as income. See TransactionRecord.countsAsIncome.
  Category(
    id: kFromPeopleCategoryId,
    name: 'From people',
    icon: Icons.people_alt_rounded,
    color: const Color(0xFF0EA5E9),
    type: 'income',
  ),
];

/// Category for money received from people (not counted as income).
const String kFromPeopleCategoryId = 'cat_from_people';
