import 'dart:ui';

import 'package:cs_cosplay/app_config.dart';
import 'package:cs_cosplay/models/detection_frame.dart';
import 'package:cs_cosplay/models/pose_landmarks.dart';
import 'package:cs_cosplay/services/pose_judge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用 1000×1000 的方形帧，几何断言好算。
const Size kFrame = Size(1000, 1000);

/// 归一化包络 (left,top)-(right,bottom) 内均匀撒 33 个关键点。
///
/// [visible] 之后的点被故意放在 (0,0) 且置信度极低 —— 真实插件对
/// 不可见关键点经常返回这种垃圾坐标，用来验证它们不会把包围盒拉到全屏。
RawPose buildPose({
  double left = 0.35,
  double top = 0.2,
  double right = 0.65,
  double bottom = 0.9,
  double confidence = 0.9,
  int visible = 33,
}) {
  final points = <PoseLandmarkPoint>[];
  for (var i = 0; i < BlazePoseIndex.landmarkCount; i++) {
    if (i < visible) {
      final fx = left + (right - left) * ((i % 6) / 5);
      final fy = top + (bottom - top) * ((i ~/ 6) / 5);
      points.add(
        PoseLandmarkPoint(x: fx, y: fy, confidence: confidence),
      );
    } else {
      points.add(
        const PoseLandmarkPoint(x: 0, y: 0, confidence: 0.05),
      );
    }
  }
  return RawPose(points);
}

void main() {
  group('DetectionFrame.ambiguous', () {
    test('默认 false，旧调用方不用改', () {
      final frame = DetectionFrame(
        frameSize: kFrame,
        boxes: const <TargetBox>[],
        personConfidence: 0,
        at: DateTime(2026),
      );
      expect(frame.ambiguous, isFalse);
    });
  });

  group('PoseJudge.select —— 基本判定', () {
    test('单个姿态命中准星 → 输出 1 个框，不歧义', () {
      final sel = PoseJudge.select(poses: [buildPose()], frameSize: kFrame);

      expect(sel.boxes.length, 1);
      expect(sel.ambiguous, isFalse);
      expect(sel.hasTarget, isTrue);

      final box = sel.boxes.single;
      expect(box.isPerson, isTrue);
      expect(box.confidence, greaterThanOrEqualTo(Cfg.poseScoreMin));
      expect(box.confidence, lessThanOrEqualTo(1.0));
    });

    test('包围盒 = 可见点包络 + 四边各外扩 8%', () {
      // 包络 x 350~650 (w=300) → dx=24 → 326~674
      // 包络 y 200~900 (h=700) → dy=56 → 144~956
      final sel = PoseJudge.select(poses: [buildPose()], frameSize: kFrame);
      final rect = sel.boxes.single.rect;

      expect(rect.left, closeTo(326, 0.01));
      expect(rect.top, closeTo(144, 0.01));
      expect(rect.right, closeTo(674, 0.01));
      expect(rect.bottom, closeTo(956, 0.01));
    });

    test('可见点不足 17 → 丢弃', () {
      final sel = PoseJudge.select(
        poses: [buildPose(visible: 10)],
        frameSize: kFrame,
      );
      expect(sel.boxes, isEmpty);
      expect(sel.ambiguous, isFalse);
      expect(sel.hasTarget, isFalse);
    });

    test('全部关键点低置信度 → 视为 0 个可见点 → 丢弃', () {
      final sel = PoseJudge.select(
        poses: [buildPose(confidence: 0.45)],
        frameSize: kFrame,
      );
      expect(sel.boxes, isEmpty);
    });

    test('退化成点的姿态 → 丢弃', () {
      final degenerate = RawPose(
        List<PoseLandmarkPoint>.generate(
          33,
          (_) => const PoseLandmarkPoint(x: 0.5, y: 0.5, confidence: 0.9),
        ),
      );
      final sel = PoseJudge.select(poses: [degenerate], frameSize: kFrame);
      expect(sel.boxes, isEmpty);
    });

    test('空输入 / 非法帧尺寸 → 空结果', () {
      expect(PoseJudge.select(poses: const [], frameSize: kFrame).boxes, isEmpty);
      expect(
        PoseJudge.select(
          poses: [buildPose()],
          frameSize: const Size(0, 0),
        ).boxes,
        isEmpty,
      );
    });
  });

  group('PoseJudge.select —— 不可见点的垃圾坐标', () {
    test('(0,0) 的不可见点不能把包围盒拉到全屏', () {
      // 17 点可见（刚好过线），其余 16 点在 (0,0)
      final sel = PoseJudge.select(
        poses: [buildPose(visible: 17)],
        frameSize: kFrame,
      );

      expect(sel.boxes.length, 1);
      // 若把 (0,0) 也纳入包络，left/top 会被拉到 0
      expect(sel.boxes.single.rect.left, greaterThan(300));
      expect(sel.boxes.single.rect.top, greaterThan(150));
    });
  });

  group('PoseJudge.select —— 准星约束（防「免费命中」）', () {
    test('准星处没有目标 → 空结果，且不置 ambiguous', () {
      final sel = PoseJudge.select(
        poses: [buildPose()],
        frameSize: kFrame,
        crosshair: const Offset(50, 50),
      );
      expect(sel.boxes, isEmpty);
      expect(sel.ambiguous, isFalse);
    });

    test('画面里另有姿态但没框住准星 → 不参与锁定、不触发歧义', () {
      // A 在准星上，B 在右下角，两者分数都很高
      final sel = PoseJudge.select(
        poses: [
          buildPose(),
          buildPose(left: 0.9, top: 0.9, right: 0.95, bottom: 0.95),
        ],
        frameSize: kFrame,
      );

      expect(sel.boxes.length, 1);
      expect(sel.ambiguous, isFalse);
      // 锁定的必须是准星上那个，而不是右下角那个
      expect(sel.boxes.single.rect.center.dx, closeTo(500, 1));
    });
  });

  group('PoseJudge.select —— 歧义判定', () {
    test('两个姿态分数几乎相同且都在准星上 → ambiguous，仍返回 top1 供画框', () {
      final sel = PoseJudge.select(
        poses: [
          buildPose(),
          buildPose(left: 0.34, top: 0.2, right: 0.64, bottom: 0.9),
        ],
        frameSize: kFrame,
      );

      expect(sel.ambiguous, isTrue);
      // 方案 X：歧义时也保留 top1，开火流程一行不用改
      expect(sel.boxes.length, 1);
      expect(sel.boxes.single.isPerson, isTrue);
    });

    test('分差 >= poseAmbiguityMargin → 只锁定 top1，不歧义', () {
      // 几何相同 → 距离项相同；presence 0.90 vs 0.55 → 分差 0.3*0.35 = 0.105
      final sel = PoseJudge.select(
        poses: [
          buildPose(confidence: 0.55),
          buildPose(confidence: 0.90),
        ],
        frameSize: kFrame,
      );

      expect(sel.ambiguous, isFalse);
      expect(sel.boxes.length, 1);
      // top1 必须是高 presence 那个
      final highScore = PoseJudge.select(
        poses: [buildPose(confidence: 0.90)],
        frameSize: kFrame,
      ).boxes.single.confidence;
      expect(sel.boxes.single.confidence, closeTo(highScore, 1e-9));
    });
  });

  group('打分公式', () {
    test('几何/presence 相同时，分差只由 presence 决定', () {
      final a = PoseJudge.select(
        poses: [buildPose(confidence: 0.90)],
        frameSize: kFrame,
      ).boxes.single.confidence;
      final b = PoseJudge.select(
        poses: [buildPose(confidence: 0.60)],
        frameSize: kFrame,
      ).boxes.single.confidence;

      expect(a - b, closeTo(0.3 * (0.90 - 0.60), 1e-9));
    });

    test(
      '【characterization】poseScoreMin 目前不是有效闸门：'
      '最弱但仍框住准星的合法姿态得分也远高于 0.35',
      () {
        // 33 点全可见、置信度刚好等于 posePresenceMin，框贴着左上角（距离项最小）
        final sel = PoseJudge.select(
          poses: [
            buildPose(
              left: 0,
              top: 0,
              right: 0.5,
              bottom: 0.5,
              confidence: Cfg.posePresenceMin,
            ),
          ],
          frameSize: kFrame,
        );

        expect(sel.hasTarget, isTrue);
        // 结论：只要框住准星，0.35 这条线永远不会触发 → 阈值需要重新标定
        expect(sel.boxes.single.confidence, greaterThan(Cfg.poseScoreMin));
        expect(sel.boxes.single.confidence, greaterThan(0.6));
      },
    );
  });
}
