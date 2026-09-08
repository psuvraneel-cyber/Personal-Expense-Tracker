import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class SpendPauseScreen extends StatefulWidget {
  const SpendPauseScreen({super.key});

  @override
  State<SpendPauseScreen> createState() => _SpendPauseScreenState();
}

class _SpendPauseScreenState extends State<SpendPauseScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathCtrl;
  late final Animation<double> _breathAnim;
  String _selectedDuration = 'Until midnight';
  DateTime? _customUntil;
  final Set<String> _selectedCategoryIds = {};

  static const _durations = ['1 hour', 'Until midnight', '3 days', 'Custom'];

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _breathAnim = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pauseProvider = context.watch<SpendPauseProvider>();
    final catProvider = context.watch<CategoryProvider>();
    final expenseCategories = catProvider.categories
        .where((c) => c.type == 'expense')
        .toList();

    // Sync selected category IDs from provider if active
    if (pauseProvider.isActive && _selectedCategoryIds.isEmpty) {
      _selectedCategoryIds.addAll(pauseProvider.blockedCategoryIds);
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      appBar: AppBar(
        title: const Text('Focus Mode'),
        backgroundColor: isDark ? AppTheme.primaryDark : AppTheme.primaryLight,
      ),
      body: PremiumGate(
        title: 'Focus Mode',
        subtitle: 'Temporarily pause spending to hit your goals faster.',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
          children: [
            const SizedBox(height: 16),
            _buildToggleHero(pauseProvider, isDark),
            const SizedBox(height: 24),
            if (!pauseProvider.isActive) ...[
              _buildDurationSection(isDark),
              const SizedBox(height: 20),
              _buildCategoryBlock(expenseCategories, isDark),
            ] else ...[
              _buildActiveInfo(pauseProvider, catProvider, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleHero(SpendPauseProvider pauseProvider, bool isDark) {
    final canToggle = pauseProvider.isActive || _selectedCategoryIds.isNotEmpty;
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: canToggle ? () => _handleToggle(pauseProvider) : null,
            child: AnimatedBuilder(
              animation: _breathAnim,
              builder: (_, child) {
                final scale = pauseProvider.isActive ? _breathAnim.value : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: pauseProvider.isActive
                      ? LinearGradient(
                          colors: [
                            AppTheme.accentPurple.withAlpha(220),
                            AppTheme.accentTeal.withAlpha(180),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            (isDark ? Colors.white : Colors.black).withAlpha(
                              isDark ? 20 : 12,
                            ),
                            (isDark ? Colors.white : Colors.black).withAlpha(
                              isDark ? 10 : 5,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  boxShadow: pauseProvider.isActive
                      ? [
                          BoxShadow(
                            color: AppTheme.accentPurple.withAlpha(100),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                  border: Border.all(
                    color: pauseProvider.isActive
                        ? Colors.white.withAlpha(80)
                        : (isDark
                            ? Colors.white.withAlpha(20)
                            : Colors.black.withAlpha(12)),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      pauseProvider.isActive
                          ? Icons.shield_rounded
                          : Icons.shield_outlined,
                      size: 44,
                      color: pauseProvider.isActive
                          ? Colors.white
                          : AppTheme.textTertiary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pauseProvider.isActive ? 'ACTIVE' : 'OFF',
                      style: TextStyle(
                        color: pauseProvider.isActive
                            ? Colors.white
                            : AppTheme.textTertiary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            pauseProvider.isActive
                ? (pauseProvider.until != null
                    ? _formatUntil(pauseProvider.until!)
                    : 'Active Indefinitely')
                : 'Tap to Activate Focus Mode',
            style: TextStyle(
              color: pauseProvider.isActive
                  ? AppTheme.accentTeal
                  : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pause Duration',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _durations.map((d) {
            final selected = _selectedDuration == d;
            return ChoiceChip(
              label: Text(d),
              selected: selected,
              onSelected: (_) {
                if (d == 'Custom') {
                  _pickCustomDate();
                } else {
                  setState(() => _selectedDuration = d);
                }
              },
              selectedColor: AppTheme.accentPurple.withAlpha(40),
              backgroundColor: isDark
                  ? Colors.white.withAlpha(8)
                  : Colors.black.withAlpha(5),
              labelStyle: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? AppTheme.accentPurple
                    : AppTheme.textSecondary,
              ),
              side: BorderSide(
                color: selected
                    ? AppTheme.accentPurple
                    : (isDark
                        ? Colors.white.withAlpha(15)
                        : Colors.black.withAlpha(10)),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryBlock(List<dynamic> categories, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pause Spending In',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Selected categories will trigger a reminder when you spend.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        ...categories.map((c) {
          final isSelected = _selectedCategoryIds.contains(c.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accentPurple.withAlpha(isDark ? 25 : 18)
                  : (isDark ? AppTheme.cardDark : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppTheme.accentPurple
                    : (isDark
                        ? Colors.white.withAlpha(10)
                        : Colors.black.withAlpha(7)),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withAlpha(isDark ? 30 : 20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  IconData(c.iconCodePoint, fontFamily: c.iconFontFamily ?? 'MaterialIcons'),
                  color: AppTheme.accentPurple,
                  size: 20,
                ),
              ),
              title: Text(
                c.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected
                    ? AppTheme.accentPurple
                    : AppTheme.textTertiary,
              ),
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedCategoryIds.remove(c.id);
                  } else {
                    _selectedCategoryIds.add(c.id);
                  }
                });
              },
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedCategoryIds.isEmpty
                ? null
                : () => _handleToggle(context.read<SpendPauseProvider>()),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Activate Focus Mode'),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveInfo(
    SpendPauseProvider pauseProvider,
    CategoryProvider catProvider,
    bool isDark,
  ) {
    final blockedNames = pauseProvider.blockedCategoryIds
        .map((id) => catProvider.categories.firstWhere(
              (c) => c.id == id,
              orElse: () => catProvider.categories.first,
            ).name)
        .toSet()
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentPurple.withAlpha(isDark ? 40 : 25),
            AppTheme.accentTeal.withAlpha(isDark ? 30 : 18),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentPurple.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.incomeGreen),
              SizedBox(width: 8),
              Text(
                'Focus Mode is On',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pauseProvider.until != null
                ? _formatUntil(pauseProvider.until!)
                : 'Duration: Indefinite',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentTeal,
                ),
          ),
          if (blockedNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Paused: $blockedNames',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => pauseProvider.deactivate(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.expenseRed,
                side: const BorderSide(color: AppTheme.expenseRed),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Deactivate'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUntil(DateTime until) {
    final now = DateTime.now();
    final diff = until.difference(now);

    if (diff.isNegative) {
      return 'Expired';
    }

    if (diff.inDays < 1) {
      final h = diff.inHours;
      final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
      if (h > 0) return 'Ends in $h:$m:$s';
      return 'Ends in $m:$s';
    } else {
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return 'Active until ${until.day} ${months[until.month]}';
    }
  }

  Future<void> _handleToggle(SpendPauseProvider provider) async {
    if (provider.isActive) {
      await provider.deactivate();
      setState(() => _selectedCategoryIds.clear());
    } else {
      final now = DateTime.now();
      DateTime? until;
      switch (_selectedDuration) {
        case '1 hour':
          until = now.add(const Duration(hours: 1));
        case 'Until midnight':
          until = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case '3 days':
          until = now.add(const Duration(days: 3));
        case 'Custom':
          if (_customUntil == null || !_customUntil!.isAfter(now)) {
            await _pickCustomDate();
            if (_customUntil == null || !_customUntil!.isAfter(now)) return;
          }
          until = _customUntil;
        default:
          until = null;
      }
      await provider.activate(
        until: until,
        categoryIds: _selectedCategoryIds.toList(),
      );
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (pickedTime == null) return;

    setState(() {
      _customUntil = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _selectedDuration = 'Custom';
    });
  }
}
