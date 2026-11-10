import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../business.dart';

class HomeStatistics extends StatefulWidget {
  const HomeStatistics({
    super.key,
    required this.business,
    required this.month,
    required this.selected,
    this.overview = false,
  });
  final Business business;
  final DateTime month;
  final DateTime selected;
  final bool overview;
  @override
  State<HomeStatistics> createState() => _HomeStatisticsState();
}

class _HomeStatisticsState extends State<HomeStatistics> {
  bool weekly = true;
  late DateTime week = monday(DateTime.parse(widget.business.today));
  late DateTime statisticsMonth = DateTime.parse(widget.business.today);
  DateTime monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  void movePeriod(int delta) => setState(() {
    if (weekly) {
      week = DateTime(week.year, week.month, week.day + delta * 7);
    } else {
      statisticsMonth = DateTime(
        statisticsMonth.year,
        statisticsMonth.month + delta,
      );
    }
  });

  Future<void> selectPeriod(DateTime start) async {
    final today = DateTime.parse(widget.business.today);
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(1),
      lastDate: today,
      helpText: weekly ? '选择统计周内的任意日期' : '选择统计月份内的任意日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (weekly) {
        week = monday(picked);
      } else {
        statisticsMonth = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final month = widget.overview ? widget.month : statisticsMonth;
    final start = widget.overview || !weekly
        ? DateTime(month.year, month.month)
        : week;
    final end = !widget.overview && weekly
        ? DateTime(week.year, week.month, week.day + 6)
        : DateTime(month.year, month.month + 1, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.overview) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('周')),
              ButtonSegment(value: false, label: Text('月')),
            ],
            selected: {weekly},
            onSelectionChanged: (value) =>
                setState(() => weekly = value.single),
          ),
          Row(
            children: [
              IconButton(
                tooltip: '上一期',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => movePeriod(-1),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => selectPeriod(start),
                  child: Text(
                    weekly
                        ? '${Business.formatDate(start)} ～ ${Business.formatDate(end)}'
                        : '${start.year}年${start.month}月',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一期',
                icon: const Icon(Icons.chevron_right),
                onPressed: end.isBefore(DateTime.parse(widget.business.today))
                    ? () => movePeriod(1)
                    : null,
              ),
            ],
          ),
          TextButton(
            onPressed: () => setState(() {
              final today = DateTime.parse(widget.business.today);
              week = monday(today);
              statisticsMonth = today;
            }),
            child: Text(weekly ? '回到本周' : '回到本月'),
          ),
        ],
        FutureBuilder<PeriodStatistics>(
          key: ValueKey('$start-$end'),
          future: widget.business.statistics(start, end),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('统计读取失败');
            final data = snapshot.data;
            if (data == null) return const Text('正在读取统计…');
            if (widget.overview) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    for (final item in [
                      ('排便次数', '${data.total}'),
                      ('已排便', '${data.recordedDays}天'),
                      ('未排便', '${data.confirmedDays}天'),
                      ('待填写', '${data.unfilledDays}天'),
                    ])
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              item.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                distribution('排便通畅度分布', data.ease, data.total),
                distribution('排便量分布', data.amount, data.total),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget distribution(String title, Map<String, int> values, int total) {
    final entries = values.entries.where((e) => e.value > 0).toList();
    const colors = [
      Color(0xFF496B32),
      Color(0xFF8EA96B),
      Color(0xFFD3AC64),
      Color(0xFF739C98),
      Color(0xFFB98B91),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (total == 0)
            const Text('暂无排便记录')
          else ...[
            Center(
              child: SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(
                  painter: DistributionPainter(
                    entries.map((e) => e.value).toList(),
                    colors,
                  ),
                  child: Center(child: Text('$total 次')),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: colors[i % colors.length],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${title == '排便量分布' && entries[i].key != '旧版未分类' ? '💩 × ${entries[i].key}' : const {'困难': '😣', '一般': '😐', '顺畅': '😊'}[entries[i].key] ?? entries[i].key}  ${entries[i].value}次 · ${(entries[i].value / total * 100).toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class DistributionPainter extends CustomPainter {
  DistributionPainter(this.values, this.colors);
  final List<int> values;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) return;
    var start = -math.pi / 2;
    final rect = Offset.zero & size;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect.deflate(14),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DistributionPainter oldDelegate) => true;
}
