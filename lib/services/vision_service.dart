import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../app_config.dart';
import '../models/detection_frame.dart';
import '../models/pose_landmarks.dart';
import '../util/yuv.dart';
import 'pose_judge.dart';

/// 本地视觉流水线（纯端上，无网络）。
///
/// 【为什么从「物体检测 + 图像打标」换成姿态检测】
/// ML Kit 目标检测的内置模型只有 5 个粗类（时尚商品/食品/家居/地点/植物），
/// **没有 person 类**。旧实现只能靠 Image Labeling 的全局 "Person" 标签去认人，
/// 再把这个全局标量硬分配给画面上每一个显著物体框，结果是：
///   · 手机、海报、花纹全部变成可命中的绿框（假阳性）
///   · 真人离远了（像素不足）反而漏检
///   · 兜底分支还会在屏幕正中造一个假框，等于「对准心开火必中」
/// 改成 BlazePose 33 关键点后就从根上解决了：
///   · 只有能解出人体骨架的区域才会出框 → 杂物天然被滤掉
///   · 框 = **可见**关键点的包络 + 外扩（见 PoseJudge），没有骨架就没有框
///   · 置信度是逐目标的姿态得分，不再是全局标签冒充人物判定
///
/// 【输入格式】相机配置的是 ImageFormatGroup.nv21，CameraX 给出单 plane 的 NV21，
/// toNv21() 走零拷贝路径直接喂给 InputImage，**不需要** YUV→ARGB 转换。
///
/// 【已知限制：单姿态】
/// ML Kit Pose 每次只返回**一个**姿态（画面里最显著的那个人）。见插件 Kotlin 实现
/// `if (pose.allPoseLandmarks.isNotEmpty()) array.add(...)` —— allPoseLandmarks 属于
/// 单个 Pose 对象。所以：
///   · numPoses 不可配置（PoseDetectorOptions 里根本没有这个参数）
///   · 6 人同框时只有 1 人被跟踪
///   · 永远只有 0 或 1 个 pose → PoseJudge 的「歧义」分支在当前实现下不可达
/// PoseJudge 仍按 List 设计，将来换原生 MediaPipe Tasks（numPoses > 1）时
/// 判定逻辑一行都不用改。
class VisionService {
  PoseDetector? _detector;
  bool _ready = false;

  /// 只打印一次的首帧诊断（确认坐标单位与姿态数量）
  bool _loggedFirstResult = false;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        // base：实时流用。accurate 是给静态图准备的，会明显拖慢帧率。
        model: PoseDetectionModel.base,
        // stream：跨帧跟踪，绿框更稳，不会每帧乱跳。single 会让每帧独立检测。
        mode: PoseDetectionMode.stream,
      ),
    );
    _ready = true;
  }

  /// 分析一帧。返回 null 表示这帧无法处理（格式不支持/检测器未就绪）。
  ///
  /// [sensorOrientation] 来自 CameraDescription.sensorOrientation。
  /// 因为 App 锁定竖屏，旋转补偿恒等于 sensorOrientation（后摄一般 90）。
  Future<DetectionFrame?> analyze(
    CameraImage image,
    int sensorOrientation,
  ) async {
    if (!_ready || _detector == null) return null;

    final nv21 = toNv21(image);
    if (nv21 == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    // ML Kit 的输出坐标是「把图旋正之后」的坐标系：
    // 旋转 90/270 时，宽高互换。
    final swapped = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final rawSize = Size(image.width.toDouble(), image.height.toDouble());
    final frameSize = swapped
        ? Size(rawSize.height, rawSize.width)
        : Size(rawSize.width, rawSize.height);

    final metadata = InputImageMetadata(
      size: rawSize,
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.width,
    );

    final poses = await _detector!.processImage(
      InputImage.fromBytes(bytes: nv21, metadata: metadata),
    );

    // ---- 插件输出 → 与插件解耦的 RawPose ----
    final raw = <RawPose>[];
    for (final pose in poses) {
      final landmarks = <PoseLandmarkPoint>[];
      for (final landmark in pose.landmarks.values) {
        // PoseLandmark.x / y 是**像素**坐标（插件 Kotlin 侧直接取
        // poseLandmark.position3D.x / .y），坐标系就是上面算出的直立帧。
        // PoseJudge 要的是 0~1 归一化坐标，所以在这里除以帧尺寸。
        // likelihood = ML Kit 的 inFrameLikelihood，即该点「在画面内」的置信度，
        // 正好对应这里「可见关键点」的定义。
        landmarks.add(
          PoseLandmarkPoint(
            x: landmark.x / frameSize.width,
            y: landmark.y / frameSize.height,
            confidence: landmark.likelihood,
          ),
        );
      }
      raw.add(RawPose(landmarks));
    }

    if (!_loggedFirstResult) {
      _loggedFirstResult = true;
      final first = raw.isEmpty ? null : raw.first.landmarks;
      final visible = first == null
          ? 0
          : first
              .where((p) => p.confidence >= Cfg.poseLandmarkMinLikelihood)
              .length;
      debugPrint('[Pose] 首帧 ${frameSize.width.toInt()}x'
          '${frameSize.height.toInt()} poses=${raw.length} '
          'landmarks=${first?.length ?? 0} visible=$visible');
    }

    // ---- 判定：过滤 / 包络 / 打分 / 锁定（纯逻辑模块，可离线单测）----
    final selection = PoseJudge.select(poses: raw, frameSize: frameSize);

    return DetectionFrame(
      frameSize: frameSize,
      boxes: selection.boxes,
      ambiguous: selection.ambiguous,
      at: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
    _ready = false;
    _loggedFirstResult = false;
  }
}
