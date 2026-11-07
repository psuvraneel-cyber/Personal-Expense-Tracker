import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/l10n/app_language.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.current.value = const Locale('en');
  });

  tearDown(() {
    AppLanguage.current.value = const Locale('en');
  });

  testWidgets('English and Hindi locale changes rebuild localized content',
      (tester) async {
    await tester.pumpWidget(_LocaleProbeApp());
    expect(find.text('Detected Transactions'), findsOneWidget);

    await AppLanguage.set('hi');
    await tester.pumpAndSettle();
    expect(find.text('पहचाने गए लेन-देन'), findsOneWidget);
    expect(find.text('22 सितंबर 2026'), findsOneWidget);

    await AppLanguage.set('en');
    await tester.pumpAndSettle();
    expect(find.text('Detected Transactions'), findsOneWidget);
  });

  testWidgets('locale changes survive an active dialog and navigation',
      (tester) async {
    await tester.pumpWidget(_LocaleProbeApp());
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsOneWidget);

    await AppLanguage.set('hi');
    await tester.pumpAndSettle();
    expect(find.text('संवाद'), findsOneWidget);

    await tester.tap(find.text('बंद करें'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('हिंदी स्क्रीन'));
    await tester.pumpAndSettle();
    expect(find.text('पहचाने गए लेन-देन'), findsOneWidget);
    expect(find.text('22 सितंबर 2026'), findsOneWidget);
  });
}

class _LocaleProbeApp extends StatelessWidget {
  _LocaleProbeApp();

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLanguage.current,
      builder: (context, locale, _) => MaterialApp(
        locale: locale,
        navigatorKey: _navigatorKey,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const _ProbeScreen(),
        routes: {'/hindi': (_) => const _ProbeScreen()},
      ),
    );
  }
}

class _ProbeScreen extends StatelessWidget {
  const _ProbeScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMMd(locale).format(DateTime(2026, 9, 22));
    final hindi = locale.startsWith('hi');
    return Scaffold(
      body: Column(
        children: [
          Text(l10n.detectedTransactionsTitle),
          Text(date),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  Localizations.localeOf(context).languageCode == 'hi'
                      ? 'संवाद'
                      : 'Dialog',
                ),
                content: Text(
                  Localizations.localeOf(context).languageCode == 'hi'
                      ? 'हिंदी स्क्रीन'
                      : 'English screen',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'hi'
                          ? 'बंद करें'
                          : 'Close',
                    ),
                  ),
                ],
              ),
            ),
            child: const Text('Open dialog'),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/hindi'),
            child: Text(hindi ? 'हिंदी स्क्रीन' : 'English screen'),
          ),
        ],
      ),
    );
  }
}
