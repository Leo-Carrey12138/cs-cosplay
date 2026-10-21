import 'dart:ui';

import '../app_config.dart';

/// 一个检测框。坐标是「直立帧坐标系」（已考虑手机旋转，原点左上角，单位=像素）。
class TargetBox {
  const TargetBox({
    required this.rect,
    required this.isPerson,
    required this.confidence,
    this.label,
  });

  final Rect rect;

  /// 是否可当作「人」来瞄准（绿框）
  final bool isPerson;

  /// 置信度。融合模式下 = Image Labeling 的 Person 置信度
  final double confidence;

  /// 模型给出的原始标签（基础模型下大概率是 Fashion goods / Home goods 之类，仅供参考）
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
    required this.personConfidence,
    required this.at,
    this.ambiguous = false,
  });

  /// 直立帧尺寸（像素）。UI 用它 + 屏幕尺寸算出缩放映射。
  final Size frameSize;

  final List<TargetBox> boxes;

  /// Image Labeling 给出的 "Person" 最高置信度
  final double personConfidence;

  final DateTime at;

  /// 命中准星的目标不止一个且分数接近 → 无法自动锁定，需要玩家手动指认。
  ///
  /// 【产品决策 #4】命中的是谁由玩家手动指认，所以本标志不改变开火流程，
  /// 只用于 UI 文案/配色（见 PoseJudge）。默认 false，旧调用方无需改动。
  final bool ambiguous;

  /// 画面里是否确实有人
  bool get personPresent => personConfidence >= Cfg.personConfidence;

  /// 可瞄准的框（绿框）
  List<TargetBox> get targetBoxes =>
      boxes.where((b) => b.isPerson).toList(growable: false);

  @override
  String toString() =>
      'DetectionFrame(${frameSize.width.toInt()}x${frameSize.height.toInt()}, '
      'boxes=${boxes.length}, person=${personConfidence.toStringAsFixed(2)})';
}

/// 开火判定结果（供 UI 决定提示什么）。
enum ShotVerdict {
  /// 没打中任何人
  miss,

  /// 打中了人，但框太小 → 超出射程
  outOfRange,

  /// 有效命中，需要弹出「击中谁」
  hit,
}

class ShotOutcome {
  const ShotOutcome(this.verdict, {this.screenAreaRatio = 0, this.box});

  final ShotVerdict verdict;

  /// person 框面积 / 屏幕总面积（0~1），用于距离估算
  final double screenAreaRatio;

  final TargetBox? box;

  /// 百分比形式，方便直接显示
  double get percent => screenAreaRatio * 100;
}
