// BlazePose 33 关键点的「插件无关」中间表示。
//
// 存在的意义：把第三方检测插件的差异挡在这一层之外，上层判定逻辑
// （lib/services/pose_judge.dart）只依赖本文件，不依赖任何插件类型。
//
//   · ML Kit Pose   → PoseLandmark(x, y, z, likelihood)        → confidence = likelihood
//   · MediaPipe     → NormalizedLandmark(x, y, z, visibility)  → confidence = visibility
//
// 索引顺序遵循 BlazePose / MediaPipe 的 33 点标准：
//   0 鼻 / 11,12 左右肩 / 13,14 左右肘 / 15,16 左右腕
//   23,24 左右髋 / 25,26 左右膝 / 27,28 左右踝 / 31,32 左右脚尖

/// 一个姿态关键点。
class PoseLandmarkPoint {
  const PoseLandmarkPoint({
    required this.x,
    required this.y,
    required this.confidence,
  });

  /// 归一化坐标（0~1），原点左上角。
  ///
  /// 【约定】必须是「直立帧」方向：插件内部按 sensorOrientation 旋转补偿后
  /// 再归一化，与 DetectionFrame.frameSize 同一坐标系。若插件给的是未旋转
  /// 的原始方向，适配层必须先把 x/y 换位，否则绿框整体转 90°。
  final double x;
  final double y;

  /// 该点的置信度（0~1）。ML Kit 为 likelihood，MediaPipe 为 visibility。
  final double confidence;

  @override
  String toString() => 'Landmark(${x.toStringAsFixed(3)}, '
      '${y.toStringAsFixed(3)}, c=${confidence.toStringAsFixed(2)})';
}

/// 一个被检测到的姿态。
class RawPose {
  const RawPose(this.landmarks);

  final List<PoseLandmarkPoint> landmarks;

  @override
  String toString() => 'RawPose(${landmarks.length} landmarks)';
}

/// BlazePose 33 点索引常量（只列当前用得到/后续要用的）。
class BlazePoseIndex {
  BlazePoseIndex._();

  /// 标准点数。打分公式的分母用它，不能用 landmarks.length
  /// （插件偶尔会返回不完整的列表）。
  static const int landmarkCount = 33;

  static const int nose = 0;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
}
