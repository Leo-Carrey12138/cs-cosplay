import 'dart:math' as math;
import 'dart:ui';

import '../app_config.dart';
import '../models/detection_frame.dart';
import '../models/pose_landmarks.dart';

/// 一帧姿态判定的结果。
class PoseSelection {
  const PoseSelection({required this.boxes, required this.ambiguous});

  /// 可瞄准的框。锁定成功时长度为 1；无目标 / 不达标时为空。
  final List<TargetBox> boxes;

  /// 「命中准星的目标不止一个，且分数接近」——无法自动锁定。
  ///
  /// 【产品决策 #4】命中的是谁由玩家手动指认，因此本标志**不改变开火流程**，
  /// 只用于 UI 文案与配色（例如状态栏改「目标重叠·请手动指认」）。
  final bool ambiguous;

  bool get hasTarget => boxes.isNotEmpty;

  static const PoseSelection none =
      PoseSelection(boxes: <TargetBox>[], ambiguous: false);

  @override
  String toString() => 'PoseSelection(boxes=${boxes.length}, '
      'ambiguous=$ambiguous)';
}

/// 把 `List<RawPose>` 判定成「最多一个可瞄准目标」。
///
/// 纯函数、零插件依赖：vision_service 只负责把插件输出翻译成 [RawPose]，
/// 所有阈值/几何/打分都在这里，便于离线单测（test/pose_judge_test.dart）。
///
/// 处理顺序（与任务书 2.a~2.e 对应，偏差见下）：
///   a) 可见点数 < poseMinLandmarks，或 presence(可见点平均置信度) < posePresenceMin → 丢弃
///   b) 只用**可见点**求归一化包络，转成帧像素后四边各外扩 poseBoxPadding
///   c) score = 0.5*(1 - 框心到画面中心距离/对角线) + 0.3*presence + 0.2*(可见点数/33)
///   d) score < poseScoreMin → 丢弃
///   e) 命中相关集（框住准星的姿态）里取 top1；与 top2 分差 < poseAmbiguityMargin
///      → ambiguous = true
///
/// 【偏差 D1】候选在进入 e) 之前会过滤成「框包含准星」的姿态。
///   不加这一层的话，画面上任意两个人分数接近就会把整帧置为 ambiguous，
///   玩家对着空地开火也能弹出选人面板 —— 那就是 P0-A 那类「免费命中」回归。
///
/// 【偏差 D2】ambiguous 时仍然返回 top1 的框（而不是返回空列表）。
///   按方案 X「两种情况都弹 picker」，保留 top1 可以让绿框继续画在目标身上，
///   并且让 _fire() 的命中/射程/冷却逻辑一行都不用改。若将来要 strict 语义
///   （歧义时不出框），改这里的返回值即可。
class PoseJudge {
  const PoseJudge._();

  /// [crosshair] 是准星在**帧像素坐标**下的位置，null = 帧中心。
  /// 将来做准心 ROI 裁剪时直接传 ROI 中心，判定语义不变。
  static PoseSelection select({
    required List<RawPose> poses,
    required Size frameSize,
    Offset? crosshair,
  }) {
    if (poses.isEmpty) return PoseSelection.none;
    if (frameSize.width <= 0 || frameSize.height <= 0) return PoseSelection.none;

    final aim = crosshair ??
        Offset(frameSize.width / 2, frameSize.height / 2);
    final frameCenter =
        Offset(frameSize.width / 2, frameSize.height / 2);
    final diagonal = math.sqrt(
      frameSize.width * frameSize.width +
          frameSize.height * frameSize.height,
    );
    if (diagonal <= 0) return PoseSelection.none;

    final onAim = <_ScoredPose>[];

    for (final pose in poses) {
      // ---- a) 门槛：可见点数 / presence ----
      final visible = <PoseLandmarkPoint>[];
      for (final p in pose.landmarks) {
        if (p.confidence >= Cfg.poseLandmarkMinLikelihood) visible.add(p);
      }
      if (visible.length < Cfg.poseMinLandmarks) continue;

      // presence 只对**可见点**取平均：这样「点数」和「质量」是两个正交的闸门，
      // 不会出现「人只露一半 → 被 33 点平均稀释 → 明明 17 点可见还是被丢」的情况。
      //
      // 注意（已知问题 F1）：因为每个可见点的置信度都 >= poseLandmarkMinLikelihood，
      // 平均值必然 >= 它。当前默认值 posePresenceMin == poseLandmarkMinLikelihood == 0.5，
      // 所以这条闸门恒为真（vacuous）。要让它生效，posePresenceMin 必须**大于**
      // poseLandmarkMinLikelihood（建议 0.6），否则它只是一行装饰。
      var sum = 0.0;
      for (final p in visible) {
        sum += p.confidence;
      }
      final presence = sum / visible.length;
      if (presence < Cfg.posePresenceMin) continue;

      // ---- b) 只用可见点求包络，避免不可见点的 (0,0) 垃圾坐标把框拉到全屏 ----
      final envelope = _envelope(visible, frameSize);
      if (envelope == null) continue;
      final box = _pad(envelope, Cfg.poseBoxPadding, frameSize);

      // ---- c) 打分 ----
      final centerDistance = (box.center - frameCenter).distance / diagonal;
      final score = 0.5 * (1 - centerDistance.clamp(0.0, 1.0)) +
          0.3 * presence +
          0.2 * (visible.length / BlazePoseIndex.landmarkCount);

      // ---- d) 分数门槛 ----
      if (score < Cfg.poseScoreMin) continue;

      // 【偏差 D1】只有框住准星的姿态才算「命中相关」
      if (!box.contains(aim)) continue;

      onAim.add(_ScoredPose(box: box, score: score));
    }

    if (onAim.isEmpty) return PoseSelection.none;
    onAim.sort((a, b) => b.score.compareTo(a.score));

    final top = onAim.first;
    final box = TargetBox(
      rect: top.box,
      isPerson: true,
      confidence: top.score,
    );

    // ---- e) 唯一目标 ----
    if (onAim.length == 1) {
      return PoseSelection(boxes: <TargetBox>[box], ambiguous: false);
    }

    // ---- e) 分差判定 ----
    final gap = top.score - onAim[1].score;
    return PoseSelection(
      boxes: <TargetBox>[box],
      ambiguous: gap < Cfg.poseAmbiguityMargin,
    );
  }

  /// 可见点的归一化包络 → 帧像素矩形。
  static Rect? _envelope(List<PoseLandmarkPoint> points, Size frameSize) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (final p in points) {
      final x = p.x * frameSize.width;
      final y = p.y * frameSize.height;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return null;
    }
    // 退化成点/线的框没有瞄准意义，直接丢
    if (maxX - minX <= 0 || maxY - minY <= 0) return null;

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 四边各外扩 `ratio * 框宽/框高`，并夹到帧内。
  static Rect _pad(Rect rect, double ratio, Size frameSize) {
    final dx = rect.width * ratio;
    final dy = rect.height * ratio;
    return Rect.fromLTRB(
      (rect.left - dx).clamp(0.0, frameSize.width),
      (rect.top - dy).clamp(0.0, frameSize.height),
      (rect.right + dx).clamp(0.0, frameSize.width),
      (rect.bottom + dy).clamp(0.0, frameSize.height),
    );
  }
}

class _ScoredPose {
  const _ScoredPose({required this.box, required this.score});

  final Rect box;
  final double score;
}
