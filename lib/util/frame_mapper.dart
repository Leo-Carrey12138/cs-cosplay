import 'dart:math' as math;
import 'dart:ui';

/// 坐标映射：把 ML Kit 的「直立帧坐标」映射到「相机预览区的控件坐标」。
///
/// 关键点：预览是用 BoxFit.**contain** 完整显示整幅画面的（多出来的地方留黑边），
/// 这里用**完全相同的缩放规则**，所以绿框和十字准星必然严格对齐，
/// 不管手机是 16:9、20:9 还是更极端的长宽比。
///
///   scale  = min(view.w / frame.w, view.h / frame.h)   // contain
///   offset = (view - frame * scale) / 2                // 居中 → 就是黑边宽度
///
/// 两个必须守住的约定：
///   1) viewSize 必须是「相机预览区」的尺寸（不含上下 HUD 面板），不是整块屏幕。
///      否则 offsetY 会少算/多算一段，绿框整体上移或下移。
///   2) 必须用 min（contain）。用 max（cover）会让 scale 变大、offset 变成负值，
///      绿框会放大并被推到画面外，和看到的画面对不上。
class FrameMapper {
  FrameMapper({required this.frameSize, required this.viewSize});

  /// 直立帧尺寸（= DetectionFrame.frameSize）
  final Size frameSize;

  /// 相机预览区尺寸（= 承载预览的那个 Stack 的尺寸，不含 HUD 面板）
  final Size viewSize;

  bool get isValid =>
      frameSize.width > 0 &&
      frameSize.height > 0 &&
      viewSize.width > 0 &&
      viewSize.height > 0;

  /// contain 缩放系数：取两个方向的较小值，保证整幅画面都能塞进预览区。
  double get scale {
    if (!isValid) return 1;
    return math.min(
      viewSize.width / frameSize.width,
      viewSize.height / frameSize.height,
    );
  }

  /// contain 之后画面在水平/垂直方向的偏移（>= 0，就是两侧黑边的宽度）。
  ///
  /// 垂直方向的黑边就是 "上下留黑边" 的那条边；水平方向同理。
  /// 数学上两个方向用同一个公式，所以无论黑边出现在上下还是左右都自动正确。
  double get offsetX => (viewSize.width - frameSize.width * scale) / 2;
  double get offsetY => (viewSize.height - frameSize.height * scale) / 2;

  /// 画面在预览区里实际占据的矩形（= 黑边之内那块真正有画面的区域）。
  /// 画荧光绿描边时用它，保证描边和画面边缘严丝合缝。
  Rect get imageRect => Rect.fromLTWH(
        offsetX,
        offsetY,
        frameSize.width * scale,
        frameSize.height * scale,
      );

  Offset toView(Offset p) =>
      Offset(offsetX + p.dx * scale, offsetY + p.dy * scale);

  Offset toFrame(Offset p) =>
      Offset((p.dx - offsetX) / scale, (p.dy - offsetY) / scale);

  Rect rectToView(Rect r) => Rect.fromLTWH(
        offsetX + r.left * scale,
        offsetY + r.top * scale,
        r.width * scale,
        r.height * scale,
      );

  Rect rectToFrame(Rect r) => Rect.fromLTWH(
        (r.left - offsetX) / scale,
        (r.top - offsetY) / scale,
        r.width / scale,
        r.height / scale,
      );

  /// 预览区正中心的坐标（十字准星所在点）。
  /// contain 时画面居中，所以这里同时也是画面正中。
  Offset get viewCenter => Offset(viewSize.width / 2, viewSize.height / 2);

  /// 计算「帧坐标下的框」占**预览区面积**的百分比（0~1）。
  /// contain 不会裁掉画面，intersect 主要是防越界，结果仍是
  /// 「person 框面积 / 预览区总面积」。
  double visibleAreaRatio(Rect frameRect) {
    if (!isValid) return 0;
    final viewRect = rectToView(frameRect);
    final visible = viewRect.intersect(Offset.zero & viewSize);
    if (visible.isEmpty) return 0;
    final total = viewSize.width * viewSize.height;
    if (total <= 0) return 0;
    return (visible.width * visible.height) / total;
  }
}
