import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poop_today/records/record_calendar.dart';

void main() {
  testWidgets('首次加载与切换月份后均按月初星期排列日期', (tester) async {
    final today = DateTime(2026, 11, 13);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordCalendar(
            selected: today,
            today: today,
            initialMonth: today,
            counts: const {},
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final fridayX = tester.getCenter(find.text('五')).dx;
    expect(tester.getCenter(find.text('13')).dx, closeTo(fridayX, 1));
    final initialPosition = tester.getCenter(find.text('13'));
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('13')), initialPosition);
  });

  testWidgets('逐月推演首次加载、全部日期排列及跨年往返切换', (tester) async {
    final months = [
      for (var index = 0; index < 50; index++) DateTime(2026, 11 + index),
      DateTime(2100, 2),
    ];
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final coveredWeekdays = <int>{};
    final coveredLengths = <int>{};

    for (final month in months) {
      final days = DateTime(month.year, month.month + 1, 0).day;
      coveredWeekdays.add(month.weekday);
      coveredLengths.add(days);
      for (final initialDay in [1, 13, days]) {
        for (final explicitMonth in [true, false]) {
          final today = DateTime(month.year, month.month, initialDay, 15, 30);
          DateTime? changedMonth;
          DateTime? selectedDate;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RecordCalendar(
                  key: UniqueKey(),
                  selected: today,
                  today: today,
                  initialMonth: explicitMonth ? today : null,
                  counts: const {},
                  onSelected: (date) => selectedDate = date,
                  onMonthChanged: (date) => changedMonth = date,
                ),
              ),
            ),
          );

          void verifyMonth() {
            expect(find.text('${month.year}年${month.month}月'), findsOneWidget);
            final grid = tester.widget<GridView>(find.byType(GridView));
            expect(
              grid.childrenDelegate.estimatedChildCount,
              month.weekday - 1 + days,
            );
            final firstY = tester.getCenter(find.text('1')).dy;
            for (var day = 1; day <= days; day++) {
              final date = DateTime(month.year, month.month, day);
              final position = tester.getCenter(find.text('$day'));
              expect(
                position.dx,
                closeTo(
                  tester.getCenter(find.text(weekdays[date.weekday - 1])).dx,
                  1,
                ),
                reason: '$date 的星期列',
              );
              expect(
                position.dy,
                closeTo(firstY + ((month.weekday - 1 + day - 1) ~/ 7) * 42, 1),
                reason: '$date 的日期行',
              );
              final button = tester.widget<TextButton>(
                find.ancestor(
                  of: find.text('$day'),
                  matching: find.byType(TextButton),
                ),
              );
              expect(button.onPressed != null, day <= initialDay);
            }
          }

          verifyMonth();
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.chevron_right),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.text('$initialDay'));
          expect(selectedDate, DateTime(month.year, month.month, initialDay));
          await tester.tap(find.byTooltip('上个月'));
          await tester.pumpAndSettle();
          expect(changedMonth, DateTime(month.year, month.month - 1));
          await tester.tap(find.byTooltip('下个月'));
          await tester.pumpAndSettle();
          expect(changedMonth, month);
          verifyMonth();
          expect(tester.takeException(), isNull);
        }
      }
    }
    expect(coveredWeekdays, {1, 2, 3, 4, 5, 6, 7});
    expect(coveredLengths, {28, 29, 30, 31});
  });
}
