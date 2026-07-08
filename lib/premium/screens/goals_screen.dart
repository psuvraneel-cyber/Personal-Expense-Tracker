import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

// Quick-pick goal emojis
const _goalEmojis = [
  '🏖️',
  '🚗',
  '🏠',
  '💍',
  '📱',
  '✈️',
  '🎓',
  '💰',
  '🏋️',
  '🎮',
];

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with SingleTickerProviderStateMixin {
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalProvider>().load();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Savings Goals'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
        actions: [
          IconButton(
            onPressed: () => _showAddGoal(context),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PremiumGate(
        title: 'Savings Goals',
        subtitle: 'Set targets, track progress, and top up anytime.',
        child: Consumer<GoalProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.goals.isEmpty) {
              return _buildEmpty(isDark);
            }

            final totalTarget = provider.goals.fold(
              0.0,
              (s, g) => s + g.targetAmount,
            );
            final totalSaved = provider.goals.fold(
              0.0,
              (s, g) => s + g.currentAmount,
            );
            final overall = totalTarget > 0 ? totalSaved / totalTarget : 0.0;
            final completedCount = provider.goals
                .where((g) => g.currentAmount >= g.targetAmount)
                .length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              children: [
                const SizedBox(height: 8),
                _buildHeroBanner(
                  totalSaved,
                  totalTarget,
                  overall,
                  completedCount,
                  provider.goals.length,
                  isDark,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Your Goals',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${provider.goals.length} total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...provider.goals.asMap().entries.map(
                  (e) =>
                      _buildGoalCard(context, e.value, provider, isDark, e.key),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroBanner(
    double saved,
    double target,
    double progress,
    int completed,
    int total,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withAlpha(70),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Portfolio',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmt.format(saved),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'of ${_fmt.format(target)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Circular progress arc
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _animCtrl,
                      builder: (_, _) {
                        return CustomPaint(
                          size: const Size(72, 72),
                          painter: _ArcPainter(
                            progress: (progress * _animCtrl.value).clamp(0, 1),
                          ),
                        );
                      },
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(progress * 100).round().clamp(0, 100)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'saved',
                          style: TextStyle(color: Colors.white60, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, _) => LinearProgressIndicator(
                value: (progress * _animCtrl.value).clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.white.withAlpha(30),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completed of $total goals achieved',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  progress >= 1
                      ? '🎉 All complete!'
                      : progress >= 0.5
                      ? '💪 Halfway there'
                      : '🚀 Keep going',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(
    BuildContext context,
    SavingGoal goal,
    GoalProvider provider,
    bool isDark,
    int index,
  ) {
    final progress = goal.targetAmount > 0
        ? goal.currentAmount / goal.targetAmount
        : 0.0;
    final daysLeft = goal.targetDate?.difference(DateTime.now()).inDays;
    final isComplete = progress >= 1.0;

    // Monthly needed to finish on time
    String? monthlyNeeded;
    if (!isComplete && daysLeft != null && daysLeft > 0) {
      final months = (daysLeft / 30).clamp(1, double.infinity);
      final needed = (goal.targetAmount - goal.currentAmount) / months;
      monthlyNeeded = _fmt.format(needed.clamp(0, double.infinity));
    }

    // Staggered entrance animation
    final delay = (index * 0.08).clamp(0.0, 0.5);
    final animation = CurvedAnimation(
      parent: _animCtrl,
      curve: Interval(delay, (delay + 0.5).clamp(0, 1), curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - animation.value)),
        child: Opacity(opacity: animation.value.clamp(0, 1), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isComplete
                ? AppTheme.incomeGreen.withAlpha(isDark ? 60 : 40)
                : (isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.black.withAlpha(7)),
          ),
          boxShadow: isComplete
              ? [
                  BoxShadow(
                    color: AppTheme.incomeGreen.withAlpha(isDark ? 25 : 15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // emoji
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isComplete
                        ? AppTheme.incomeGreen.withAlpha(isDark ? 35 : 22)
                        : AppTheme.accentPurple.withAlpha(isDark ? 30 : 18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      isComplete ? '🏆' : (goal.emoji ?? '🎯'),
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (goal.isPaused)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warningYellow.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Paused',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.warningYellow,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (isComplete)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.incomeGreen.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '✓ Goal Reached!',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.incomeGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (daysLeft != null && !isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: daysLeft <= 7
                          ? AppTheme.expenseRed.withAlpha(25)
                          : AppTheme.accentPurple.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          daysLeft <= 0 ? '0' : '$daysLeft',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: daysLeft <= 7
                                ? AppTheme.expenseRed
                                : AppTheme.accentPurple,
                          ),
                        ),
                        Text(
                          'days',
                          style: TextStyle(
                            fontSize: 9,
                            color: daysLeft <= 7
                                ? AppTheme.expenseRed
                                : AppTheme.accentPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppTheme.textTertiary,
                    size: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (v) async {
                    if (v == 'pause') {
                      await provider.togglePause(goal.id);
                    } else if (v == 'delete') {
                      await provider.deleteGoal(goal.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pause',
                      child: Row(
                        children: [
                          Icon(
                            goal.isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_circle_outline_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(goal.isPaused ? 'Resume' : 'Pause'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.expenseRed,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: AppTheme.expenseRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Amounts row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saved',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    Text(
                      _fmt.format(goal.currentAmount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isComplete
                            ? AppTheme.incomeGreen
                            : AppTheme.accentPurple,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Target',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    Text(
                      _fmt.format(goal.targetAmount),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Animated progress bar
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (progress * _animCtrl.value).clamp(0, 1),
                  minHeight: 12,
                  backgroundColor: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.black.withAlpha(6),
                  valueColor: AlwaysStoppedAnimation(
                    isComplete ? AppTheme.incomeGreen : AppTheme.accentPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).round().clamp(0, 100)}% complete',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isComplete
                        ? AppTheme.incomeGreen
                        : AppTheme.accentPurple,
                  ),
                ),
                if (monthlyNeeded != null)
                  Text(
                    '$monthlyNeeded/mo needed',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isComplete
                    ? null
                    : () => _showTopUp(context, goal, provider),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Top Up'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isComplete
                      ? AppTheme.incomeGreen
                      : AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple.withAlpha(60),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.flag_rounded,
                size: 42,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'No Goals Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Set a savings goal and track your progress.\nEvery rupee counts!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _showAddGoal(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add First Goal'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTopUp(
    BuildContext context,
    SavingGoal goal,
    GoalProvider provider,
  ) async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(goal.emoji ?? '🎯', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Up — ${goal.name}',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    Text(
                      '${_fmt.format(goal.currentAmount)} / ${_fmt.format(goal.targetAmount)}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Quick amount chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [500, 1000, 2000, 5000].map((amt) {
                return GestureDetector(
                  onTap: () => controller.text = amt.toString(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.accentPurple.withAlpha(50),
                      ),
                    ),
                    child: Text(
                      '+₹$amt',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentPurple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(controller.text.trim()) ?? 0;
                  if (amount > 0) {
                    provider.topUpGoal(goal.id, amount);
                    Navigator.pop(ctx);
                  }
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Add to Goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddGoal(BuildContext context) async {
    final provider = context.read<GoalProvider>();
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    DateTime? targetDate;
    String selectedEmoji = _goalEmojis[0];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Savings Goal',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              // Emoji picker
              const Text(
                'Pick an icon',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _goalEmojis.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = _goalEmojis[i] == selectedEmoji;
                    return GestureDetector(
                      onTap: () => setS(() => selectedEmoji = _goalEmojis[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.accentPurple.withAlpha(35)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppTheme.accentPurple
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _goalEmojis[i],
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Goal name (e.g. Goa Trip)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 90)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setS(() => targetDate = picked);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        targetDate == null
                            ? 'Target date (optional)'
                            : DateFormat('dd MMM yyyy').format(targetDate!),
                        style: targetDate == null
                            ? const TextStyle(color: AppTheme.textTertiary)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (name.isEmpty || amount <= 0) return;
                    provider.addGoal(
                      name: name,
                      targetAmount: amount,
                      targetDate: targetDate,
                      emoji: selectedEmoji,
                    );
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Create Goal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Circular arc painter for the hero
class _ArcPainter extends CustomPainter {
  final double progress;
  _ArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const startAngle = -pi / 2;

    final trackPaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final arcPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * pi,
      false,
      trackPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}
