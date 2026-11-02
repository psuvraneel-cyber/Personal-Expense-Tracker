import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/widgets/amount_text.dart';
import 'package:pet/core/widgets/pet_section.dart';
import 'package:pet/core/widgets/pressable.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/screens/home/standalone_tab.dart';

Widget _app(Widget child, {MediaQueryData? media}) => MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: media == null
          ? Scaffold(body: child)
          : MediaQuery(data: media, child: Scaffold(body: child)),
    );

String _plain(WidgetTester tester, Finder f) => tester
    .widget<Text>(find.descendant(of: f, matching: find.byType(Text)))
    .textSpan!
    .toPlainText();

void main() {
  group('AmountText', () {
    testWidgets('uses Indian grouping and a sign for the tone', (t) async {
      await t.pumpWidget(_app(const Column(children: [
        AmountText(103500, key: Key('a')),
        AmountText(240,
            key: Key('b'), tone: AmountTone.expense, showSign: true),
        AmountText(50000,
            key: Key('c'), tone: AmountTone.income, showSign: true),
      ])));
      expect(_plain(t, find.byKey(const Key('a'))), '₹1,03,500');
      expect(_plain(t, find.byKey(const Key('b'))), '− ₹240');
      expect(_plain(t, find.byKey(const Key('c'))), '+ ₹50,000');
    });

    testWidgets('digits are tabular and screen readers hear one label',
        (t) async {
      await t.pumpWidget(_app(const AmountText(1234.5, decimals: 2)));
      final text = t.widget<Text>(find.byType(Text));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(find.bySemanticsLabel('₹1,234.50'), findsOneWidget);
    });
  });

  group('Pressable', () {
    testWidgets('shrinks while held and calls onTap on release', (t) async {
      var taps = 0;
      await t.pumpWidget(_app(Center(
        child: Pressable(
          onTap: () => taps++,
          child: const SizedBox(width: 100, height: 50),
        ),
      )));
      final gesture =
          await t.startGesture(t.getCenter(find.byType(SizedBox).last));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          Motion.pressedScale);
      await gesture.up();
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('does not scale when reduced motion is on', (t) async {
      await t.pumpWidget(_app(
        Center(
          child: Pressable(
            onTap: () {},
            child: const SizedBox(width: 100, height: 50),
          ),
        ),
        media: const MediaQueryData(disableAnimations: true),
      ));
      final gesture =
          await t.startGesture(t.getCenter(find.byType(SizedBox).last));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
    });
  });

  testWidgets('PetSection puts hairlines only between rows', (t) async {
    await t.pumpWidget(_app(const PetSection(
      title: 'Notifications',
      children: [
        PetRow(title: 'One'),
        PetRow(title: 'Two', subtitle: 'Second'),
        PetRow(title: 'Three'),
      ],
    )));
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('tab bottom padding clears the nav bar and the Add button',
      (t) async {
    late double withFab, withoutFab;
    await t.pumpWidget(_app(
      Builder(builder: (context) {
        withFab = Spacing.tabBottom(context);
        withoutFab = Spacing.tabBottom(context, fab: false);
        return const SizedBox();
      }),
      media: const MediaQueryData(padding: EdgeInsets.only(bottom: 100)),
    ));
    expect(withFab, 100 + Spacing.fabClearance);
    expect(withoutFab, 100 + Spacing.xl);
  });

  testWidgets('Motion.of collapses durations when reduced motion is on',
      (t) async {
    late Duration d;
    await t.pumpWidget(_app(
      Builder(builder: (context) {
        d = Motion.of(context, Motion.standard);
        return const SizedBox();
      }),
      media: const MediaQueryData(disableAnimations: true),
    ));
    expect(d, Duration.zero);
  });

  testWidgets('a tab opened on its own gets a page with a back button',
      (t) async {
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StandaloneTab(
                title: (l10n) => l10n.navBudget,
                child: const Text('budget body'),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('budget body'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
