import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'business.dart';
import 'reminders.dart';
import 'records/record_page.dart';

class PoopTodayApp extends StatelessWidget {
  const PoopTodayApp({
    super.key,
    required this.business,
    this.reminders,
    this.navigatorKey,
  });
  final Business business;
  final ReminderService? reminders;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    title: '拉💩了冒',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF7D916A),
      scaffoldBackgroundColor: const Color(0xFFFFFCF5),
      useMaterial3: true,
    ),
    home: RecordPage(business: business, reminders: reminders),
  );
}
