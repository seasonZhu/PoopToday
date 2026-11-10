import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class RecordFeedback {
  OverlayEntry? _entry;
  Timer? _timer;

  void show(BuildContext context, {bool? didPoop, bool saved = false}) {
    dispose();
    final celebrating = didPoop == null;
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: saved
            ? _SavedEffect(didPoop: didPoop ?? true)
            : SafeArea(
                child: Align(
                  alignment: const Alignment(0, -.25),
                  child: _FeedbackToast(
                    celebrating: celebrating,
                    emoji: celebrating
                        ? '🎉'
                        : didPoop
                        ? '😄'
                        : '😢',
                  ),
                ),
              ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    _timer = Timer(
      Duration(
        milliseconds: saved
            ? 3000
            : celebrating
            ? 2200
            : 1200,
      ),
      dispose,
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

class _FeedbackToast extends StatefulWidget {
  const _FeedbackToast({required this.celebrating, required this.emoji});
  final bool celebrating;
  final String emoji;

  @override
  State<_FeedbackToast> createState() => _FeedbackToastState();
}

class _FeedbackToastState extends State<_FeedbackToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.celebrating ? 2200 : 1200),
  );

  @override
  void initState() {
    super.initState();
    controller.forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;
        final opacity = reduceMotion
            ? 1.0
            : (progress / .12).clamp(0.0, 1.0) *
                  ((1 - progress) / .18).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: reduceMotion
                ? 1
                : .85 +
                      .15 *
                          Curves.easeOutBack.transform(
                            (progress / .2).clamp(0.0, 1.0),
                          ),
            child: child,
          ),
        );
      },
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SizedBox(
          width: widget.celebrating ? 260 : 160,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: widget.celebrating ? 150 : 100,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: widget.celebrating && !reduceMotion
                        ? _Fireworks(controller)
                        : null,
                    child: Center(
                      child: Text(
                        widget.emoji,
                        style: const TextStyle(fontSize: 80),
                      ),
                    ),
                  ),
                ),
                if (widget.celebrating)
                  const Text('记录已保存，照顾自己真棒！', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedEffect extends StatefulWidget {
  const _SavedEffect({required this.didPoop});
  final bool didPoop;

  @override
  State<_SavedEffect> createState() => _SavedEffectState();
}

class _SavedEffectState extends State<_SavedEffect>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..forward();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: reduceMotion
            ? null
            : _SavedParticles(controller.value, widget.didPoop),
        child: Center(
          child: Opacity(
            opacity: reduceMotion
                ? 1
                : ((1 - controller.value) / .2).clamp(0.0, 1.0),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Text(
                  widget.didPoop ? '🎉 记录已保存，太棒啦！' : '😢 已记录，明天继续加油',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedParticles extends CustomPainter {
  const _SavedParticles(this.progress, this.didPoop);
  final double progress;
  final bool didPoop;

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Colors.orange,
      Colors.pink,
      Colors.teal,
      Colors.amber,
      Colors.purple,
    ];
    if (didPoop) {
      for (var burst = 0; burst < 12; burst++) {
        final local = (progress * 1.6 - burst * .055).clamp(0.0, 1.0);
        if (local == 0 || local == 1) continue;
        final center = Offset(
          size.width * (.12 + (burst * .37 % .76)),
          size.height * (.12 + (burst * .23 % .65)),
        );
        final radius =
            Curves.easeOut.transform(local) * size.shortestSide * .36;
        for (var ray = 0; ray < 28; ray++) {
          final angle = ray * math.pi / 14;
          final direction = Offset(math.cos(angle), math.sin(angle));
          final drift = Offset(0, local * local * 65);
          final paint = Paint()
            ..color = colors[(burst + ray) % colors.length].withValues(
              alpha: 1 - local,
            )
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            center + direction * radius * .8 + drift,
            center + direction * radius + drift,
            paint,
          );
        }
      }
    } else {
      for (var index = 0; index < 28; index++) {
        final local = (progress * 1.5 - (index % 7) * .07).clamp(0.0, 1.0);
        if (local == 0 || local == 1) continue;
        final origin = size.width * (.1 + (index * .317 % .8));
        final velocity = ((index % 5) - 2) * size.width * .18;
        final x = origin + velocity * local;
        final y =
            size.height -
            (size.height * (1.8 + index % 3 * .25)) * local +
            size.height * 2.2 * local * local;
        final text = TextPainter(
          text: TextSpan(
            text: index.isEven ? '😢' : '😭',
            style: TextStyle(
              fontSize: 34 + index % 4 * 10,
              color: Colors.white.withValues(
                alpha: ((1 - local) / .25).clamp(0.0, 1.0),
              ),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(((index % 3) - 1) * local * 2);
        text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
        canvas.restore();
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_SavedParticles oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.didPoop != didPoop;
}

class _Fireworks extends CustomPainter {
  _Fireworks(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Colors.orange,
      Colors.pink,
      Colors.teal,
      Colors.amber,
      Colors.purple,
    ];
    for (var burst = 0; burst < 3; burst++) {
      final progress = ((animation.value - burst * .12) / .76).clamp(0.0, 1.0);
      final radius = Curves.easeOut.transform(progress) * 76;
      final center = Offset(
        size.width * (.2 + burst * .3),
        burst == 1 ? 45 : 85,
      );
      final paint = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = colors[burst].withValues(alpha: 1 - progress);
      for (var ray = 0; ray < 16; ray++) {
        final angle = ray * math.pi / 8;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * radius * .72,
          center + direction * radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Fireworks oldDelegate) =>
      oldDelegate.animation != animation;
}
