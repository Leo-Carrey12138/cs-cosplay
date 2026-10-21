import 'dart:ui';

/// 一个检测框。坐标是「直立帧坐标系」（已考虑手机旋转，原点左上角，单位=像素）。
class TargetBox {
  const TargetBox({
    required this.rect,
    required this.isPerson,
    required this.confidence,
    this.label,
  });

  final Rect rect;

  /// 是否可当作「人」来瞄准（绿框）。
  ///
  /// 姿态检测方案下，只有「解出了人体骨架」才会产生框，所以这里恒为 true；
  /// 保留该字段是为了让叠加层/判定层不用区分检测器来源。
  final bool isPerson;

  /// 置信度（0~1）。姿态方案下 = PoseJudge 的综合姿态得分
  /// （0.5*居中程度 + 0.3*可见点平均置信度 + 0.2*可见点占比）。
  final double confidence;

  /// 附加标签，仅用于叠加层显示；姿态方案下为 null。
  final String? label;

  @override
  String toString() =>
         'TargetBox(l=${rect.left.toStringAsFixed(1)}, t=${rect.top.toStringAsFixed(1)}, w=${rect.width.toStringAsFixed(1)}, h=${rect.height.toStringAsFixed(1)}, person=$isPerson, conf=${confidence.toStringAsFixed(2)}, label=$label)';
}

/// 一帧本地推理结果。
class DetectionFrame {
  const DetectionFrame({
    required this.frameSize,
    required this.boxes,
    required this.at,
    this.ambiguous = false,
  });

  /// 直立帧尺寸（像素）。UI 用它 + 屏幕尺寸算出缩放映射。
  final Size frameSize;

  /// 本帧的可瞄准目标框（0 或 1 个：ML Kit Pose 单姿态，见 VisionService 注释）。
  final List<TargetBox> boxes;

  final DateTime at;

  /// 命中准星的目标不止一个且分数接近 → 无法自动锁定，需要玩家手动指认。
  ///
  /// 【产品决策 #4】命中的是谁由玩家手动指认，所以本标志不改变开火流程，
  /// 只用于 UI 文案/配色（见 PoseJudge）。
  ///
  /// 【注意】当前接入的 ML Kit Pose 每帧最多返回 1 个姿态，
  /// 因此该标志在现网实现下恒为 false，要等换多姿态检测器才会生效。
  final bool ambiguous;

  bool get hasTarget => boxes.isNotEmpty;

  /// 锁定目标的姿态得分；无目标时为 0。
  double get targetConfidence =>
      boxes.isEmpty ? 0 : boxes.first.confidence;

  /// 可瞄准的框（绿框）
  List<TargetBox> get targetBoxes =>
      boxes.where((b) => b.isPerson).toList(growable: false);

  @override
  String toString() =>
      'DetectionFrame(${frameSize.width.toInt()}x${frameSize.height.toInt()}, '
      'boxes=${boxes.length}, ambiguous=$ambiguous)';
}
