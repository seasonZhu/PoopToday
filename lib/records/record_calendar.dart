import 'package:flutter/material.dart';

import '../business.dart';

class RecordCalendar extends StatefulWidget {
  const RecordCalendar({
    super.key,
    required this.selected,
    required this.today,
    required this.counts,
    this.onSelected,
    this.initialMonth,
    this.onMonthChanged,
  });
  final DateTime? initialMonth;
  final ValueChanged<DateTime>? onMonthChanged;
  final DateTime selected;
  final DateTime today;
  final Map<String, int> counts;
  final ValueChanged<DateTime>? onSelected;
  @override
  State<RecordCalendar> createState() => _RecordCalendarState();
}

class _RecordCalendarState extends State<RecordCalendar> {
  late DateTime month =
      widget.initialMonth ??
      DateTime(widget.selected.year, widget.selected.month);
  void changeMonth(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    widget.onMonthChanged?.call(month);
  }

  @override
  Widget build(BuildContext context) {
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: month.year == 1 && month.month == 1
                  ? null
                  : () => changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${month.year}年${month.month}月',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed:
                  DateTime(month.year, month.month + 1).isAfter(widget.today)
                  ? null
                  : () => changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: Text(day))),
          ],
        ),
        GridView.count(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          crossAxisCount: 7,
          mainAxisExtent: 42,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var index = 0; index < offset + days; index++)
              if (index < offset)
                const SizedBox()
              else
                Builder(
                  builder: (context) {
                    final date = DateTime(
                      month.year,
                      month.month,
                      index - offset + 1,
                    );
                    final count = widget.counts[Business.formatDate(date)];
                    return TextButton(
                      onPressed: date.isAfter(widget.today)
                          ? null
                          : () => widget.onSelected != null
                                ? widget.onSelected!(date)
                                : Navigator.pop(context, date),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontWeight:
                                  Business.formatDate(date) ==
                                      Business.formatDate(widget.today)
                                  ? FontWeight.w800
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            count == null
                                ? ''
                                : count == 0
                                ? '❌'
                                : '✅',
                            style: const TextStyle(fontSize: 12, height: 1.2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
        if (widget.onSelected == null)
          FilledButton.tonal(
            onPressed: () => widget.onSelected != null
                ? widget.onSelected!(widget.today)
                : Navigator.pop(context, widget.today),
            child: const Text('返回今天'),
          ),
      ],
    );
  }
}
