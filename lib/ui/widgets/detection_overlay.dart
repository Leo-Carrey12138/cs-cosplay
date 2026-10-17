import 'package:flutter/material.dart';

import '../../models/detection_frame.dart';
import '../../util/frame_mapper.dart';

/// 把本地检测结果实时叠在相机画面上：
///   绿色框 = 可瞄准的人（供玩家参考）
///   白色半透明框 = 其它显著物体
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({super.key, required this.frame});

  final DetectionFrame? frame;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: DetectionBoxPainter(frame: frame),
        size: Size.infinite,
      ),
    );
  }
}

class DetectionBoxPainter extends CustomPainter {
  DetectionBoxPainter({required this.frame});

  final DetectionFrame? frame;

  static const Color _personColor = Color(0xFF00E676);
  static const Color _objectColor = Color(0x55FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null) return;

    final mapper = FrameMapper(frameSize: f.frameSize, viewSize: size);
    if (!mapper.isValid) return;

    for (final box in f.boxes) {
      final rect = mapper.rectToView(box.rect);
      // 被 cover 裁出屏幕的部分不画
      final visible = rect.intersect(Offset.zero & size);
      if (visible.isEmpty) continue;

      final color = box.isPerson ? _personColor : _objectColor;

      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = box.isPerson ? 3 : 1.5
          ..color = color,
      );

      if (box.isPerson) {
        _drawCorners(canvas, rect, color);
        _drawLabel(
          canvas,
          rect,
          'PERSON ${(box.confidence * 100).toStringAsFixed(0)}%',
          color,
        );
      } else if (box.label != null) {
        _drawLabel(canvas, rect, box.label!, _objectColor);
      }
    }
  }

  /// 四角加粗的"狙击框"效果
  void _drawCorners(Canvas canvas, Rect rect, Color color) {
    final len = (rect.shortestSide * 0.22).clamp(8.0, 26.0).toDouble();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.square;

    // 左上
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, len), paint);
    // 右上
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, len), paint);
    // 左下
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(0, -len), paint);
    // 右下
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -len), paint);
  }

  void _drawLabel(Canvas canvas, Rect rect, String text, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          backgroundColor: const Color(0xAA000000),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);

    var top = rect.top - painter.height - 2;
    if (top < 0) top = rect.top + 2;
    painter.paint(canvas, Offset(rect.left + 2, top));
  }

  @override
  bool shouldRepaint(covariant DetectionBoxPainter old) => old.frame != frame;
}
