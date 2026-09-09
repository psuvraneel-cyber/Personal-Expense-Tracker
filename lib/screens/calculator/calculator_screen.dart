import 'package:pet/core/utils/app_logger.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/screens/transactions/add_edit_transaction_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  /// Show the calculator as a modal bottom sheet from anywhere in the app.
  static Future<double?> showAsSheet(BuildContext context) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CalculatorSheet(),
    );
  }

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.tealGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.calculate_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Calculator'),
          ],
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: const _CalculatorBody(isSheet: false),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom-sheet wrapper
// ---------------------------------------------------------------------------
class _CalculatorSheet extends StatelessWidget {
  const _CalculatorSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.cardDark.withAlpha(240)
                    : Colors.white.withAlpha(245),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.black.withAlpha(8),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withAlpha(30)
                          : Colors.black.withAlpha(20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: AppTheme.tealGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.calculate_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Calculator',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Expanded(child: _CalculatorBody(isSheet: true)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Calculator logic and UI (shared between full-screen & sheet modes)
// ---------------------------------------------------------------------------
class _CalculatorBody extends StatefulWidget {
  final bool isSheet;
  const _CalculatorBody({required this.isSheet});

  @override
  State<_CalculatorBody> createState() => _CalculatorBodyState();
}

class _CalculatorBodyState extends State<_CalculatorBody> {
  String _expression = '';
  String _result = '0';
  final List<String> _history = [];
  bool _resultShown = false;

  // ------- button layout -------
  static const List<List<String>> _buttons = [
    ['C', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['00', '0', '.', '='],
  ];

  void _onButton(String label) {
    setState(() {
      switch (label) {
        case 'C':
          _expression = '';
          _result = '0';
          _resultShown = false;
          break;
        case '⌫':
          if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
            _liveEval();
          }
          break;
        case '=':
          _evaluate();
          break;
        case '%':
        case '÷':
        case '×':
        case '−':
        case '+':
          if (_resultShown) {
            _expression = _result + label;
            _resultShown = false;
          } else {
            if (_expression.isNotEmpty &&
                _isOperator(_expression[_expression.length - 1])) {
              _expression =
                  _expression.substring(0, _expression.length - 1) + label;
            } else {
              _expression += label;
            }
          }
          break;
        default: // digits & dot
          if (_resultShown) {
            _expression = label;
            _resultShown = false;
          } else {
            _expression += label;
          }
          _liveEval();
          break;
      }
    });
  }

  bool _isOperator(String c) =>
      c == '+' || c == '−' || c == '×' || c == '÷' || c == '%';

  void _liveEval() {
    final val = _calc(_expression);
    if (val != null) {
      _result = _formatResult(val);
    }
  }

  void _evaluate() {
    final val = _calc(_expression);
    if (val != null) {
      final formatted = _formatResult(val);
      if (_expression.isNotEmpty) {
        _history.insert(0, '$_expression = $formatted');
        if (_history.length > 20) _history.removeLast();
      }
      _result = formatted;
      _expression = formatted;
      _resultShown = true;
    } else if (_expression.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invalid expression'),
          backgroundColor: AppTheme.expenseRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatResult(double v) {
    if (v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    // Up to 8 decimal digits, strip trailing zeros
    String s = v.toStringAsFixed(8);
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  double? _calc(String expr) {
    if (expr.isEmpty) return null;
    try {
      // Tokenise
      final tokens = <String>[];
      String buf = '';
      for (int i = 0; i < expr.length; i++) {
        final c = expr[i];
        if (_isOperator(c)) {
          // Handle negative sign at start or after operator
          if (c == '−' &&
              buf.isEmpty &&
              (tokens.isEmpty || _isOperator(tokens.last))) {
            buf += '-';
          } else {
            if (buf.isNotEmpty) {
              tokens.add(buf);
              buf = '';
            }
            tokens.add(c);
          }
        } else {
          buf += c;
        }
      }
      if (buf.isNotEmpty) tokens.add(buf);

      // Convert to numbers & ops
      List<double> nums = [];
      List<String> ops = [];
      for (final t in tokens) {
        if (_isOperator(t)) {
          ops.add(t);
        } else {
          final n = double.tryParse(t);
          if (n == null) return null;
          nums.add(n);
        }
      }
      if (nums.isEmpty) return null;

      // Pass 1: ×, ÷, %
      int i = 0;
      while (i < ops.length) {
        if (ops[i] == '×' || ops[i] == '÷' || ops[i] == '%') {
          double res;
          if (ops[i] == '×') {
            res = nums[i] * nums[i + 1];
          } else if (ops[i] == '÷') {
            if (nums[i + 1] == 0) return double.infinity;
            res = nums[i] / nums[i + 1];
          } else {
            res = nums[i] * nums[i + 1] / 100;
          }
          nums[i] = res;
          nums.removeAt(i + 1);
          ops.removeAt(i);
        } else {
          i++;
        }
      }

      // Pass 2: +, −
      double result = nums[0];
      for (int j = 0; j < ops.length; j++) {
        if (ops[j] == '+') {
          result += nums[j + 1];
        } else if (ops[j] == '−') {
          result -= nums[j + 1];
        }
      }
      return result;
    } catch (e, stack) {
      AppLogger.debug('[Calculator] Evaluation error: $e\n$stack');
      return null;
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          // Display
          Expanded(flex: 3, child: _buildDisplay(context, isDark)),
          const SizedBox(height: 12),
          // Quick actions
          _buildQuickActions(context, isDark),
          const SizedBox(height: 14),
          // Button grid
          Expanded(flex: 5, child: _buildButtonGrid(context, isDark)),
          if (!widget.isSheet) const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDisplay(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(6) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.grey).withAlpha(
              isDark ? 25 : 12,
            ),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // History peek
          if (_history.isNotEmpty)
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => _showHistory(context, isDark),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textSecondaryLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _history.first,
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondaryLight,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          // Expression
          Text(
            _expression.isEmpty ? ' ' : _expression,
            style: TextStyle(
              color:
                  isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: 1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          // Result
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              _result,
              key: ValueKey(_result),
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color:
                    isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
                letterSpacing: -1,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Row(
      children: [
        _quickActionChip(
          context,
          label: 'Save as Expense',
          icon: Icons.north_east_rounded,
          color: AppTheme.expenseRed,
          isDark: isDark,
          onTap: () => _saveAsTransaction(context, 'expense'),
        ),
        const SizedBox(width: 10),
        _quickActionChip(
          context,
          label: 'Save as Income',
          icon: Icons.south_west_rounded,
          color: AppTheme.incomeGreen,
          isDark: isDark,
          onTap: () => _saveAsTransaction(context, 'income'),
        ),
        const Spacer(),
        _iconActionButton(
          icon: Icons.history_rounded,
          isDark: isDark,
          onTap: () => _showHistory(context, isDark),
        ),
      ],
    );
  }

  Widget _quickActionChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 20 : 15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconActionButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildButtonGrid(BuildContext context, bool isDark) {
    return Column(
      children: _buttons.map((row) {
        return Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: row.map((label) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _calcButton(context, label, isDark),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _calcButton(BuildContext context, String label, bool isDark) {
    final isOperator = label == '÷' ||
        label == '×' ||
        label == '−' ||
        label == '+' ||
        label == '%';
    final isEquals = label == '=';
    final isClear = label == 'C';
    final isBackspace = label == '⌫';

    Color bgColor;
    Color textColor;
    FontWeight weight = FontWeight.w600;
    double fontSize = 22;
    Gradient? gradient;

    if (isEquals) {
      bgColor = Colors.transparent;
      textColor = Colors.white;
      gradient = AppTheme.heroGradient;
      weight = FontWeight.bold;
    } else if (isOperator) {
      bgColor = AppTheme.accentPurple.withAlpha(isDark ? 25 : 18);
      textColor = AppTheme.accentPurple;
      weight = FontWeight.w700;
    } else if (isClear) {
      bgColor = AppTheme.expenseRed.withAlpha(isDark ? 25 : 18);
      textColor = AppTheme.expenseRed;
      weight = FontWeight.w700;
    } else if (isBackspace) {
      bgColor = AppTheme.warningYellow.withAlpha(isDark ? 25 : 18);
      textColor = AppTheme.warningYellow;
      fontSize = 20;
    } else {
      bgColor = isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6);
      textColor = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onButton(label),
        borderRadius: BorderRadius.circular(16),
        splashColor: AppTheme.accentPurple.withAlpha(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: gradient == null ? bgColor : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isEquals
                ? [
                    BoxShadow(
                      color: AppTheme.accentPurple.withAlpha(40),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isBackspace
                ? Icon(Icons.backspace_rounded, color: textColor, size: 20)
                : Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: weight,
                      letterSpacing: label == '=' ? 1 : 0,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ---------- Actions ----------

  void _saveAsTransaction(BuildContext context, String type) {
    final val = double.tryParse(_result.replaceAll(',', ''));
    if (val == null || val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a valid amount first'),
          backgroundColor: AppTheme.expenseRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Navigate to Add Transaction with the amount pre-filled
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, anim, secAnim) =>
            AddEditTransactionScreen(prefillAmount: val, prefillType: type),
        transitionsBuilder: (context, animation, secAnim, child) {
          return SlideTransition(
            position:
                Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _showHistory(BuildContext context, bool isDark) {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No calculation history yet'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.45,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(10)
                  : Colors.black.withAlpha(8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(30)
                      : Colors.black.withAlpha(20),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _history.clear());
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.expenseRed.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: AppTheme.expenseRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  itemCount: _history.length,
                  separatorBuilder: (context, index) => Divider(
                    color: isDark
                        ? Colors.white.withAlpha(8)
                        : Colors.black.withAlpha(6),
                  ),
                  itemBuilder: (context, index) {
                    final parts = _history[index].split(' = ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              parts.first,
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.textSecondary
                                    : AppTheme.textSecondaryLight,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            '= ${parts.length > 1 ? parts.last : ''}',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimaryLight,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
