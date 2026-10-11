import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/utils/amount_input.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/auth_service.dart';
import 'package:pet/services/household_service.dart';

/// Shared household budgets: up to 6 people share monthly category limits
/// and see each other's category totals (not transactions).
///
/// Starting a household is a Premium feature; joining one is free.
class SharedBudgetsScreen extends StatefulWidget {
  const SharedBudgetsScreen({super.key, this.service});

  final HouseholdService? service;

  @override
  State<SharedBudgetsScreen> createState() => _SharedBudgetsScreenState();
}

class _SharedBudgetsScreenState extends State<SharedBudgetsScreen> {
  late final HouseholdService _service = widget.service ?? HouseholdService();
  final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  User? get _user => FirebaseAuth.instance.currentUser;
  bool get _signedIn => _user != null && !_user!.isAnonymous;
  String get _myName => AuthService.userName ?? _user?.displayName ?? 'Me';

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<String?> _prompt({
    required String title,
    required String hint,
    String initial = '',
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.sentences,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          textCapitalization: caps,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _create() async {
    if (!context.read<PremiumProvider>().isPremium) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PurchaseScreen(source: 'Household budgets'),
        ),
      );
      return;
    }
    final name =
        await _prompt(title: 'Name your household', hint: 'e.g. Home, Us two');
    if (name == null || name.isEmpty) return;
    try {
      await _service.create(uid: _user!.uid, displayName: _myName, name: name);
      HouseholdSync.reset();
      AnalyticsService.instance.logEvent('household_created');
    } catch (_) {
      _toast("Couldn't create the household. Check your connection.");
    }
  }

  Future<void> _join() async {
    final code = await _prompt(
      title: 'Join a household',
      hint: 'Invite code',
      caps: TextCapitalization.characters,
    );
    if (code == null || code.isEmpty) return;
    try {
      await _service.join(code: code, uid: _user!.uid, displayName: _myName);
      HouseholdSync.reset();
      HouseholdSync.publishMine();
      AnalyticsService.instance.logEvent('household_joined');
    } on HouseholdException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("Couldn't join. Check your connection and try again.");
    }
  }

  Future<void> _invite(Household h) async {
    try {
      final code =
          await _service.createInvite(householdId: h.id, uid: _user!.uid);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite to your household'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                style: Theme.of(ctx)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 3),
              ),
              const SizedBox(height: 8),
              const Text(
                'Valid for 7 days. They\'ll see your monthly totals per '
                'category (not your transactions), and you\'ll see theirs.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                SharePlus.instance.share(ShareParams(
                  text: 'Join my household "${h.name}" on P.E.T to share '
                      'budgets. In the app: Premium Hub → Household budgets '
                      '→ Join, and enter $code. Get P.E.T: '
                      '${AppLinks.playStoreListing}',
                ));
              },
              child: const Text('Share'),
            ),
          ],
        ),
      );
    } catch (_) {
      _toast("Couldn't create an invite. Check your connection.");
    }
  }

  Future<void> _editBudget(Household h, {SharedBudget? existing}) async {
    final categories = context.read<CategoryProvider>().expenseCategories;
    final categoryId = existing?.categoryId ??
        await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Category'),
            children: [
              for (final c in categories)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.id),
                  child: Row(children: [
                    Icon(c.icon, color: c.color, size: 20),
                    const SizedBox(width: 12),
                    Text(c.name),
                  ]),
                ),
            ],
          ),
        );
    if (categoryId == null || !mounted) return;
    final category =
        context.read<CategoryProvider>().getCategoryById(categoryId);
    final raw = await _prompt(
      title: 'Monthly limit for ${existing?.categoryName ?? category?.name}',
      hint: 'Amount in ₹',
      initial: existing == null ? '' : existing.amount.toStringAsFixed(0),
      keyboard: const TextInputType.numberWithOptions(decimal: true),
    );
    if (raw == null) return;
    final amount = AmountInput.parse(raw);
    if (amount == null || AmountInput.validate(raw) != null) {
      _toast('Enter a valid amount.');
      return;
    }
    try {
      await _service.setBudget(
        householdId: h.id,
        uid: _user!.uid,
        categoryId: categoryId,
        categoryName: existing?.categoryName ?? category?.name ?? categoryId,
        amount: amount,
      );
    } catch (_) {
      _toast("Couldn't save. Check your connection.");
    }
  }

  Future<void> _confirmThen(String title, String body, String action,
      Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await run();
      HouseholdSync.reset();
    } catch (_) {
      _toast('Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Household budgets')),
      body: !_signedIn
          ? const _Message(
              icon: Icons.login_rounded,
              text: 'Sign in with Google (Settings → Account) to share '
                  'budgets with your household.',
            )
          : StreamBuilder<Household?>(
              stream: _service.watchMine(_user!.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _Message(
                    icon: Icons.cloud_off_rounded,
                    text: "Couldn't load your household. Check your "
                        'connection.',
                  );
                }
                if (!snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final h = snapshot.data;
                return h == null ? _buildIntro() : _buildHousehold(h);
              },
            ),
    );
  }

  Widget _buildIntro() {
    final isPremium = context.watch<PremiumProvider>().isPremium;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.home_rounded, color: Colors.white, size: 32),
              SizedBox(height: 12),
              Text(
                'Budget together',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Share monthly budgets with your partner or family (up to 6 '
                'people). Everyone keeps tracking on their own phone; the '
                'budgets show what you have spent together.',
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Message(
          icon: Icons.privacy_tip_outlined,
          text: 'Members see each other\'s monthly total per category — '
              'never individual transactions, merchants or notes.',
          compact: true,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accentPurple,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _create,
          icon: Icon(isPremium
              ? Icons.add_home_rounded
              : Icons.workspace_premium_rounded),
          label: Text(
              isPremium ? 'Start a household' : 'Start a household (Premium)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _join,
          icon: const Icon(Icons.group_add_rounded),
          label: const Text('Join with an invite code (free)'),
        ),
      ],
    );
  }

  Widget _buildHousehold(Household h) {
    final me = _user!.uid;
    final isOwner = h.ownerUid == me;
    final month = DateTime.now();
    return StreamBuilder<List<SharedBudget>>(
      stream: _service.watchBudgets(h.id),
      builder: (context, budgetsSnap) {
        return StreamBuilder<List<MemberSpending>>(
          stream: _service.watchSpending(h.id, month),
          builder: (context, spendSnap) {
            final budgets = budgetsSnap.data ?? const <SharedBudget>[];
            final spending = (spendSnap.data ?? const <MemberSpending>[])
                .where((s) => h.memberUids.contains(s.uid))
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(h.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rename') {
                          _prompt(
                                  title: 'Rename household',
                                  hint: 'Name',
                                  initial: h.name)
                              .then((name) {
                            if (name != null && name.isNotEmpty) {
                              _service.rename(h.id, name);
                            }
                          });
                        } else if (v == 'leave') {
                          _confirmThen(
                              'Leave ${h.name}?',
                              'Your shared totals will be removed from the '
                                  'household.',
                              'Leave',
                              () => _service.leave(h, me));
                        } else if (v == 'delete') {
                          _confirmThen(
                              'Delete ${h.name}?',
                              'This removes the shared budgets and everyone\'s '
                                  'shared totals. Personal data on each phone '
                                  'is not affected.',
                              'Delete',
                              () => _service.deleteHousehold(h));
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename', child: Text('Rename')),
                        if (isOwner)
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete household'))
                        else
                          const PopupMenuItem(
                              value: 'leave', child: Text('Leave household')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final uid in h.memberUids)
                      InputChip(
                        avatar: Icon(uid == h.ownerUid
                            ? Icons.star_rounded
                            : Icons.person_rounded),
                        label: Text(uid == me
                            ? '${h.nameOf(uid)} (you)'
                            : h.nameOf(uid)),
                        onDeleted: isOwner && uid != me
                            ? () => _confirmThen(
                                'Remove ${h.nameOf(uid)}?',
                                'They will no longer see the household.',
                                'Remove',
                                () => _service.removeMember(h, uid))
                            : null,
                      ),
                    if (h.memberUids.length < Household.maxMembers)
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Invite'),
                        onPressed: () => _invite(h),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${DateFormat('MMMM').format(month)} budgets',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _editBudget(h),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (budgets.isEmpty)
                  const _Message(
                    icon: Icons.savings_outlined,
                    text: 'No shared budgets yet. Add one for groceries, '
                        'eating out or anything you spend on together.',
                    compact: true,
                  )
                else
                  for (final b in budgets) _buildBudget(h, b, spending),
                const SizedBox(height: 16),
                Text(
                  'Totals update when each member opens P.E.T. Only monthly '
                  'totals per category are shared.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBudget(
      Household h, SharedBudget b, List<MemberSpending> spending) {
    final perMember = <String, double>{
      for (final s in spending)
        if ((s.byCategory[b.categoryId] ?? 0) > 0)
          s.uid: s.byCategory[b.categoryId]!,
    };
    final spent = perMember.values.fold(0.0, (a, v) => a + v);
    final ratio = b.amount > 0 ? spent / b.amount : 0.0;
    final over = spent > b.amount;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editBudget(h, existing: b),
        onLongPress: () => _confirmThen(
            'Remove ${b.categoryName} budget?',
            'The shared limit is removed for everyone.',
            'Remove',
            () => _service.deleteBudget(h.id, b.categoryId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(b.categoryName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    '${_inr.format(spent)} / ${_inr.format(b.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: over ? AppTheme.expenseRed : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: over
                    ? AppTheme.expenseRed
                    : ratio > 0.9
                        ? AppTheme.warningYellow
                        : AppTheme.accentTeal,
              ),
              if (perMember.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  perMember.entries
                      .map((e) => '${h.nameOf(e.key)} ${_inr.format(e.value)}')
                      .join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(
      {required this.icon, required this.text, this.compact = false});

  final IconData icon;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accentTeal),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
    return compact
        ? body
        : Center(
            child: Padding(padding: const EdgeInsets.all(32), child: body));
  }
}
