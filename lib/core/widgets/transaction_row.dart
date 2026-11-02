import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/widgets/amount_text.dart';
import 'package:pet/core/widgets/category_avatar.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

/// One transaction as a row inside a [PetSection]: who it was with as the
/// title, the category and time underneath, and the signed amount.
///
/// Leading with the merchant ("Raju Medicals") rather than the category
/// ("Other Expense") makes a list scannable; the category's icon and colour
/// still say what kind of spend it was.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
    this.showDate = false,
  });

  final TransactionRecord transaction;
  final Category? category;
  final VoidCallback? onTap;

  /// Show the date as well as the time (for lists not grouped by day).
  final bool showDate;

  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _dateTime = DateFormat('d MMM, h:mm a');

  /// "Raju Medicals (HDFC Bank)" → "Raju Medicals"; empty or "Unknown"
  /// counterparties fall back to the category name.
  static String titleFor(TransactionRecord t, Category? category) {
    final merchant = t.merchantName?.trim() ?? '';
    if (merchant.isNotEmpty && !_isUnknown(merchant)) return merchant;
    var note = t.note.trim();
    final bank = note.lastIndexOf(' (');
    if (bank > 0 && note.endsWith(')')) note = note.substring(0, bank).trim();
    if (note.isNotEmpty && !_isUnknown(note)) return note;
    return category?.name ?? 'Transaction';
  }

  static bool _isUnknown(String s) {
    final l = s.toLowerCase();
    return l == 'unknown' || l == 'unknown merchant' || l == 'n/a';
  }

  AmountTone get _tone => switch (transaction.type) {
        TransactionType.expense => AmountTone.expense,
        TransactionType.income => AmountTone.income,
        TransactionType.transfer => AmountTone.transfer,
      };

  @override
  Widget build(BuildContext context) {
    final title = titleFor(transaction, category);
    final catName = category?.name;
    final when = (showDate ? _dateTime : _time).format(transaction.date);
    final parts = <String>[
      if (catName != null && catName != title) catName,
      when,
      if (transaction.isRecurring)
        transaction.recurringFrequency?.displayName ?? 'Recurring',
    ];
    return Semantics(
      label: '$title, ${transaction.type.name} '
          '₹${AmountText.digits(transaction.amount)}, ${parts.join(', ')}',
      excludeSemantics: true,
      button: onTap != null,
      child: PetRow(
        title: title,
        subtitle: parts.join(' · '),
        onTap: onTap,
        leading: CategoryAvatar(
          icon: category?.icon ?? _fallbackIcon,
          color: category?.color ?? _fallbackColor(context),
        ),
        trailing: AmountText(transaction.amount, tone: _tone, showSign: true),
      ),
    );
  }

  IconData get _fallbackIcon => switch (transaction.type) {
        TransactionType.income => Icons.south_west_rounded,
        TransactionType.transfer => Icons.swap_horiz_rounded,
        TransactionType.expense => Icons.north_east_rounded,
      };

  Color _fallbackColor(BuildContext context) => switch (transaction.type) {
        TransactionType.income => AppTheme.incomeGreen,
        TransactionType.transfer => ColorTokens.transfer,
        TransactionType.expense =>
          Theme.of(context).brightness == Brightness.dark
              ? AppTheme.textSecondary
              : AppTheme.textSecondaryLight,
      };
}
