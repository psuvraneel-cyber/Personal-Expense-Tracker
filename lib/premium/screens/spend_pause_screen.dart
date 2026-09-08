import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/services/spend_pause_service.dart';
import 'package:pet/premium/widgets/premium_gate.dart';

class SpendPauseScreen extends StatefulWidget {
  const SpendPauseScreen({super.key});

  @override
  State<SpendPauseScreen> createState() => _SpendPauseScreenState();
}

class _SpendPauseScreenState extends State<SpendPauseScreen>
    with SingleTickerProviderStateMixin {
  SpendPause _pause = SpendPause(enabled: false);
  late final AnimationController _breathCtrl;
  late final Animation<double> _breathAnim;
  String _selectedDuration = 'Until midnight';
  DateTime? _customUntil;
  Timer? _countdownTimer;

  static const _durations = ['1 hour', 'Until midnight', '3 days', 'Custom'];

  static const _blockedIcons = {
    'Food & Dining': Icons.restaurant_rounded,
    'Entertainment': Icons.movie_rounded,
    'Shopping': Icons.shopping_bag_rounded,
    'Travel': Icons.flight_rounded,
  };

  final Set<String> _blockedCategories = {};

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
    _load();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_pause.enabled && _pause.until != null && mounted) {
        setState(() {}); // Trigger rebuild to update countdown text
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _breathCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await SpendPauseService.getState();
    setState(() {
      _pause = state;
      // Restore UI state from persisted pause so active-info is always correct.
      if (state.isActive) {
        _blockedCategories
          ..clear()
          ..addAll(state.blockedCategories);
        // Restore duration label from the stored until time
        if (state.until != null) {
          final remaining = state.until!.difference(DateTime.now());
          if (remaining.inDays >= 3) {
            _selectedDuration = '3 days';
          } else if (remaining.inHours >= 1 && remaining.inDays < 1) {
            _selectedDuration = '1 hour';
          } else {
            _selectedDuration = 'Until midnight';
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            _buildToggleHero(isDark),
            const SizedBox(height: 24),
            if (!_pause.isActive) ...[
              _buildDurationSection(isDark),
              const SizedBox(height: 20),
              _buildCategoryBlock(isDark),
            ] else ...[
              _buildActiveInfo(isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggleHero(bool isDark) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            // Hero button activates only if categories are selected (or deactivates)
            onTap: (_pause.isActive || _blockedCategories.isNotEmpty)
                ? _togglePause
                : null,
            child: AnimatedBuilder(
              animation: _breathAnim,
              builder: (_, child) {
                final scale = _pause.enabled ? _breathAnim.value : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _pause.enabled
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
                              isDark ? 10 : 6,
                            ),
                          ],
                        ),
                  boxShadow: _pause.enabled
                      ? [
                          BoxShadow(
                            color: AppTheme.accentPurple.withAlpha(80),
                            blurRadius: 30,
                            spreadRadius: 6,
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  _pause.enabled
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 60,
                  color: _pause.enabled ? Colors.white : AppTheme.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _pause.isActive
                ? 'Focus Mode Active'
                : _blockedCategories.isEmpty
                ? 'Select categories below'
                : 'Tap to Enable',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: _pause.isActive
                  ? AppTheme.accentPurple
                  : _blockedCategories.isEmpty
                  ? AppTheme.textTertiary
                  : AppTheme.accentTeal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _pause.isActive
                ? (_pause.until != null
                      ? _formatUntil(_pause.until!)
                      : 'Active indefinitely')
                : 'Set a duration below and activate',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _customUntil = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
        _selectedDuration = 'Custom';
      });
    }
  }

  Widget _buildDurationSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duration',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _durations.map((d) {
            final selected = d == _selectedDuration;
            final labelText = (d == 'Custom' && _customUntil != null)
                ? 'Custom (${_customUntil!.day}/${_customUntil!.month})'
                : d;
            return ChoiceChip(
              label: Text(labelText),
              selected: selected,
              onSelected: (_) {
                if (d == 'Custom') {
                  _pickCustomDate();
                } else {
                  setState(() {
                    _selectedDuration = d;
                  });
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

  Widget _buildCategoryBlock(bool isDark) {
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
        ..._blockedIcons.entries.map((e) {
          final isSelected = _blockedCategories.contains(e.key);
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
                child: Icon(e.value, color: AppTheme.accentPurple, size: 20),
              ),
              title: Text(
                e.key,
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
                    _blockedCategories.remove(e.key);
                  } else {
                    _blockedCategories.add(e.key);
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
            onPressed: _blockedCategories.isEmpty ? null : _togglePause,
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

  Widget _buildActiveInfo(bool isDark) {
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
            'Duration: $_selectedDuration',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_pause.blockedCategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Paused: ${_pause.blockedCategories.join(', ')}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _togglePause,
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
      // Multi-day — show date
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return 'Active until ${until.day} ${months[until.month]}';
    }
  }

  Future<void> _togglePause() async {
    if (_pause.enabled) {
      // Deactivate
      final updated = SpendPause(enabled: false);
      await SpendPauseService.setState(updated);
      setState(() {
        _pause = updated;
        _blockedCategories.clear();
      });
    } else {
      // Activate — compute the `until` DateTime from the selected duration label
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
            if (_customUntil == null || !_customUntil!.isAfter(now)) {
              return; // User cancelled date selection
            }
          }
          until = _customUntil;
        default:
          until = null;
      }
      final updated = SpendPause(
        enabled: true,
        until: until,
        blockedCategories: _blockedCategories.toList(),
      );
      await SpendPauseService.setState(updated);
      setState(() => _pause = updated);
    }
  }
}
