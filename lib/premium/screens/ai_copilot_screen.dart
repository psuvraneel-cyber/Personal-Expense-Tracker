import 'package:flutter/material.dart';
import 'package:pet/config/app_env.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:pet/premium/widgets/premium_gate.dart';

import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/premium/models/copilot_message.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/budget_provider.dart';
import 'package:pet/services/sms_service.dart';

const _suggestions = [
  'Where am I overspending this month?',
  'How long until I hit my savings goal?',
  'What\'s my biggest expense category?',
  'Am I on track with my budget?',
  'How much did I spend on food this week?',
];

class AiCopilotScreen extends StatefulWidget {
  const AiCopilotScreen({super.key});

  @override
  State<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends State<AiCopilotScreen> {
  final List<CopilotMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isSending = false;
  bool _showSuggestions = true;

  AiCopilotService? _service;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  void _initService() {
    _service = AiCopilotService(model: AppEnv.groqModel);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build financial context from live providers
  // ---------------------------------------------------------------------------

  FinancialContext _buildContext() {
    final txnProv = context.read<TransactionProvider>();
    final catProv = context.read<CategoryProvider>();
    final budgetProv = context.read<BudgetProvider>();

    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    // Category id → name lookup
    Category? catById(String id) => catProv.getCategoryById(id);

    // Category spending with human-readable names
    final catSpending = <String, double>{};
    for (final entry in txnProv.categoryWiseSpending.entries) {
      final name = catById(entry.key)?.name ?? entry.key;
      catSpending[name] = entry.value;
    }

    // Budget vs spent
    final budgets = <Map<String, dynamic>>[];
    for (final b in budgetProv.budgets) {
      final name = catById(b.categoryId)?.name ?? b.categoryId;
      final spent = budgetProv.getSpentForCategory(b.categoryId);
      budgets.add({'category': name, 'budget': b.amount, 'spent': spent});
    }

    // Recent transactions — capped at 10 to save tokens
    final recent = txnProv.allTransactions.take(10).map((t) {
      final catName = catById(t.categoryId)?.name ?? t.categoryId;
      final date = DateFormat('d MMM').format(t.date);
      final sign = t.type == TransactionType.income ? '+' : '-';
      final rawNote = t.note.isNotEmpty ? ' (${t.note})' : '';
      final note = SmsService.redactSensitiveData(rawNote);
      final merchant = t.merchantName != null ? ' at ${SmsService.redactSensitiveData(t.merchantName!)}' : '';
      return '$date: $sign₹${t.amount.toStringAsFixed(0)}$merchant — $catName via ${t.paymentMethod.displayName}$note';
    }).toList();

    return FinancialContext(
      monthLabel: monthLabel,
      totalIncome: txnProv.totalIncome,
      totalExpenses: txnProv.totalExpenses,
      totalSavings: txnProv.totalSavings,
      categorySpending: catSpending,
      budgets: budgets,
      recentTransactions: recent,
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text('AI Copilot'),
          ],
        ),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          if (_messages.isNotEmpty && _service != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withAlpha(isDark ? 30 : 18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _service!.quotaSummary,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.accentPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _showSuggestions = true;
                });
                _service?.clearHistory();
              },
            ),
        ],
      ),
      body: PremiumGate(
        title: 'Unlock AI Financial Copilot',
        subtitle: 'Get personalized insights and answers about your spending habits.',
        child: Column(
          children: [
            if (_showSuggestions && _messages.isEmpty)
              _buildSuggestions(isDark),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessage(context, _messages[index], isDark);
                },
              ),
            ),
            if (_isSending) _buildTypingIndicator(isDark),
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: AppTheme.warningYellow,
                ),
                const SizedBox(width: 6),
                Text(
                  'Try asking…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.white.withAlpha(140)
                        : Colors.black.withAlpha(100),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                return GestureDetector(
                  onTap: () {
                    _controller.text = _suggestions[i];
                    _send();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withAlpha(isDark ? 30 : 20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.accentPurple.withAlpha(
                          isDark ? 60 : 40,
                        ),
                      ),
                    ),
                    child: Text(
                      _suggestions[i],
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context, CopilotMessage msg, bool isDark) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: EdgeInsets.only(
          bottom: 10,
          left: isUser ? 40 : 0,
          right: isUser ? 0 : 40,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: isUser ? AppTheme.heroGradient : null,
          color: isUser ? null : (isDark ? AppTheme.cardDark : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(12)
                      : Colors.black.withAlpha(7),
                ),
          boxShadow: [
            BoxShadow(
              color: (isUser ? AppTheme.accentPurple : Colors.black).withAlpha(
                isUser ? 30 : 10,
              ),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            color: isUser ? Colors.white : null,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(10)
                : Colors.black.withAlpha(7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DotPulse(color: AppTheme.accentPurple, delay: 0),
            const SizedBox(width: 4),
            _DotPulse(color: AppTheme.accentPurple, delay: 200),
            const SizedBox(width: 4),
            _DotPulse(color: AppTheme.accentPurple, delay: 400),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withAlpha(10)
                : Colors.black.withAlpha(7),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Ask about your spending…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _isSending ? null : _send(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: _isSending ? null : AppTheme.heroGradient,
                    color: _isSending
                        ? (isDark
                              ? Colors.white.withAlpha(20)
                              : Colors.black.withAlpha(10))
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isSending ? null : _send,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'AI Copilot can make mistakes. Consider verifying important information.',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final service = _service;
    if (service == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Capture financial context while we still have BuildContext.
    final financialCtx = _buildContext();

    setState(() {
      _messages.add(
        CopilotMessage(role: 'user', content: text, createdAt: DateTime.now()),
      );
      _controller.clear();
      _isSending = true;
      _showSuggestions = false;
    });
    _scrollToBottom();

    try {
      final reply = await service.sendMessage(
        message: text,
        context: financialCtx,
      );
      if (mounted) {
        setState(() {
          _messages.add(
            CopilotMessage(
              role: 'assistant',
              content: reply,
              createdAt: DateTime.now(),
            ),
          );
        });
      }
    } on RateLimitException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            CopilotMessage(
              role: 'assistant',
              content: '🚦 $e',
              createdAt: DateTime.now(),
            ),
          );
        });
      }
    } on ClientErrorException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            CopilotMessage(
              role: 'assistant',
              content: '⚠️ ${e.message}',
              createdAt: DateTime.now(),
            ),
          );
        });
      }
    } catch (e) {
      final errorMsg = e.toString();
      String friendlyMsg;
      if (errorMsg.contains('401') || errorMsg.contains('Unauthorized')) {
        friendlyMsg =
            '🔑 Unauthorized. Please ensure your Cloudflare worker is configured correctly with the GROQ_API_KEY secret.';
      } else if (errorMsg.contains('SocketException') ||
          errorMsg.contains('network') ||
          errorMsg.contains('timeout')) {
        friendlyMsg =
            '📡 No internet connection. Please check your network and try again.';
      } else if (errorMsg.contains('429') || errorMsg.contains('rate')) {
        friendlyMsg =
            '⏱️ Groq API rate limit reached. Please wait a moment and try again.';
      } else {
        friendlyMsg =
            '⚠️ Couldn\'t reach the AI. Please try again.\n\nError: $errorMsg';
      }
      if (mounted) {
        setState(() {
          _messages.add(
            CopilotMessage(
              role: 'assistant',
              content: friendlyMsg,
              createdAt: DateTime.now(),
            ),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }
}

// ---------------------------------------------------------------------------
// Animated typing indicator dots
// ---------------------------------------------------------------------------

class _DotPulse extends StatefulWidget {
  final Color color;
  final int delay;

  const _DotPulse({required this.color, required this.delay});

  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
