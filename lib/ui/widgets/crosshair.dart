import 'package:flutter/material.dart';

import '../theme/csgo_theme.dart';

/// 屏幕正中央的十字准星（纯绘制，不吃点击事件）。
///
/// 默认沙黄色，中心 2px 红点标出实际判定点。
class Crosshair extends StatelessWidget {
  const Crosshair({
    super.key,
    this.color = CsColors.accent,
    this.gap = 14,
    this.arm = 16,
    this.strokeWidth = 2.2,
  });

  final Color color;
  final double gap;
  final double arm;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CrosshairPainter(
          color: color,
          gap: gap,
          arm: arm,
          strokeWidth: strokeWidth,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.color,
    required this.gap,
    required this.arm,
    required this.strokeWidth,
  });

  final Color color;
  final double gap;
  final double arm;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 很轻的描边光晕，保证准星在复杂背景上也能看清
    final glow = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 3
      ..strokeCap = StrokeCap.round;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // 上下左右四条短线，中间留空（不挡视线）
    final lines = <List<Offset>>[
      [
        Offset(center.dx, center.dy - gap - arm),
        Offset(center.dx, center.dy - gap)
      ],
      [
        Offset(center.dx, center.dy + gap),
        Offset(center.dx, center.dy + gap + arm)
      ],
      [
        Offset(center.dx - gap - arm, center.dy),
        Offset(center.dx - gap, center.dy)
      ],
      [
        Offset(center.dx + gap, center.dy),
        Offset(center.dx + gap + arm, center.dy)
      ],
    ];
    for (final line in lines) {
      canvas.drawLine(line[0], line[1], glow);
      canvas.drawLine(line[0], line[1], paint);
    }

    // 中心 1.8px 红点：判定点就是它
    canvas.drawCircle(
      center,
      1.8,
      Paint()..color = CsColors.danger,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) =>
      old.color != color ||
      old.gap != gap ||
      old.arm != arm ||
      old.strokeWidth != strokeWidth;
}
