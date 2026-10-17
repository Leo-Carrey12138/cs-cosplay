import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../app_config.dart';
import '../models/detection_frame.dart';
import '../util/yuv.dart';

/// 本地视觉流水线（纯端上，无网络）。
///
/// 【为什么是两模型融合】
/// ML Kit 目标检测【基础模型】的粗分类只有 5 类：
/// 时尚商品 / 食品 / 家居用品 / 地点 / 植物 —— **没有 person**。
/// （见 https://developers.google.com/ml-kit/vision/object-detection/android）
/// 所以：
///   1. Object Detection  → 给出「画面中显著物体」的包围框（人物通常就是最显著物体）
///   2. Image Labeling    → 给出 "Person" 标签的置信度，用来确认「画面里确实有人」
///   3. 两者融合：命中「画面里有人」时，把落在准星上的那个显著物体框当作 person 框
///
/// 将来若换成自带 person 标签的 COCO 自定义模型（LocalObjectDetectorOptions），
/// 代码会自动优先使用模型自身的 person 标签，无需改动上层逻辑。
class VisionService {
  ObjectDetector? _objectDetector;
  ImageLabeler? _labeler;
  bool _ready = false;

  /// 只要这些标签出现，就认为画面里有人
  static const Set<String> _personLabels = {
    'person',
    'people',
    'human',
    'man',
    'woman',
    'boy',
    'girl',
    'child',
    'selfie',
    'portrait',
  };

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        // 单帧模式：能拿到完整包围框 + 分类标签。
        // （stream 模式虽然支持 trackingId，但不支持分类，拿不到标签，所以不用。）
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
    _labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.4),
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
    if (!_ready || _objectDetector == null || _labeler == null) return null;

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

    // 两个检测器各拿一份 InputImage，避免复用同一份字节缓冲带来的隐患。
    final objectInput = InputImage.fromBytes(bytes: nv21, metadata: metadata);
    final labelInput = InputImage.fromBytes(bytes: nv21, metadata: metadata);

    final objects = await _objectDetector!.processImage(objectInput);
    final labels = await _labeler!.processImage(labelInput);

    // ---- 1) 画面里有没有人 ----
    var personConfidence = 0.0;
    for (final label in labels) {
      if (_personLabels.contains(label.label.toLowerCase())) {
        personConfidence = math.max(personConfidence, label.confidence);
      }
    }
    final personPresent = personConfidence >= Cfg.personConfidence;

    // ---- 2) 组装包围框 ----
    final boxes = <TargetBox>[];
    for (final object in objects) {
      final r = object.boundingBox;
      if (r.width <= 1 || r.height <= 1) continue;

      // 夹到帧内
      final rect = Rect.fromLTRB(
        r.left.clamp(0.0, frameSize.width).toDouble(),
        r.top.clamp(0.0, frameSize.height).toDouble(),
        r.right.clamp(0.0, frameSize.width).toDouble(),
        r.bottom.clamp(0.0, frameSize.height).toDouble(),
      );
      if (rect.width <= 1 || rect.height <= 1) continue;

      // 模型自己说是 person 吗？（基础模型永远不会，自定义 COCO 模型会）
      String? modelLabel;
      var modelSaysPerson = false;
      var modelConfidence = 0.0;
      for (final label in object.labels) {
        modelLabel ??= label.text;
        if (_personLabels.contains(label.text.toLowerCase())) {
          modelSaysPerson = true;
          modelConfidence = math.max(modelConfidence, label.confidence);
        }
      }

      // 融合：模型有 person 标签 → 用它；否则相信 Image Labeling 的全局判定。
      // 注意：这里刻意「宽松」——基础模型会把穿衣服的人误标成 Fashion goods，
      // 所以不能要求 label 为空才认人。宁多画绿框（供瞄准参考），也不能漏人。
      final isPerson = modelSaysPerson || (Cfg.fusePersonLabel && personPresent);

      boxes.add(
        TargetBox(
          rect: rect,
          isPerson: isPerson,
          confidence: modelSaysPerson ? modelConfidence : personConfidence,
          label: modelLabel,
        ),
      );
    }

    // 兜底：画面里确实有人，但目标检测一个显著物体都没给（例如人占满全屏、
    // 或模型跑在低端机上没出框）。此时给一个「准星大小」的默认框，
    // 保证游戏还能打，而不是完全失效。
    if (boxes.isEmpty && personPresent) {
      final side = math.min(frameSize.width, frameSize.height) * 0.45;
      boxes.add(
        TargetBox(
          rect: Rect.fromCenter(
            center: Offset(frameSize.width / 2, frameSize.height / 2),
            width: side,
            height: side * 1.4,
          ),
          isPerson: true,
          confidence: personConfidence,
          label: 'Person(global)',
        ),
      );
    }

    return DetectionFrame(
      frameSize: frameSize,
      boxes: boxes,
      personConfidence: personConfidence,
      at: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    await _objectDetector?.close();
    await _labeler?.close();
    _objectDetector = null;
    _labeler = null;
    _ready = false;
  }
}
