/// 全局可调参数。想改手感/门槛，只动这一个文件即可。
class Cfg {
  Cfg._();

  // ---------------- 房间规则 ----------------
  /// 单房间人数上限（题目要求 6）
  static const int maxPlayers = 6;

  /// 满血值
  static const int maxHp = 100;

  /// 每次确认命中扣多少血
  static const int damagePerHit = 20;

  // ---------------- 本地 AI ----------------
  /// 抽帧间隔：300ms 一帧（≈3.3 FPS）。ML Kit 单帧推理 ~80-150ms，
  /// 这个间隔足以瞄准又不至于把 UI 卡死。
  static const Duration detectInterval = Duration(milliseconds: 200);

  /// Image Labeling 判定「画面里有真人」的置信度阈值
  static const double personConfidence = 0.4;

  /// 是否启用「Image Labeling + Object Detection」融合。
  /// ML Kit 目标检测【基础模型】的粗分类只有 5 类（时尚商品/食品/家居用品/地点/植物），
  /// 根本没有 person 标签，所以必须靠 Image Labeling 的 "Person" 来判定人物。
  /// 将来换成自带 person 标签的 COCO 自定义模型时，可置 false 只用模型标签。
  static const bool fusePersonLabel = true;

  // ---------------- 姿态检测（MediaPipe / BlazePose 33 点）----------------
  //
  // 说明：以上 ML Kit 常量（personConfidence / fusePersonLabel / detectInterval）
  // 目前仍被 lib/services/vision_service.dart 使用，等 vision_service 换成
  // Pose 之后再统一删除，避免留下编译不过的中间状态。

  /// 同时跟踪的最大姿态数。（2 = 够瞄准，又不至于吃掉 50ms 预算）
  static const int poseNumPoses = 2;

  /// 姿态「存在感」下限：该姿态**可见关键点**置信度的均值低于此值 → 丢弃整条姿态。
  static const double posePresenceMin = 0.5;

  /// 单个关键点算「可见」的置信度门槛。它同时决定：
  ///   ① 可见点计数（poseMinLandmarks 的分子）
  ///   ② 包围盒只取样哪些点（不可见点的 (0,0) 垃圾坐标必须排除）
  static const double poseLandmarkMinLikelihood = 0.5;

  /// 至少这么多关键点可见才承认这条姿态。
  static const int poseMinLandmarks = 17;

  /// 关键点包络框外扩比例（按框宽/高的比例，四边各外扩一次）。
  static const double poseBoxPadding = 0.08;

  /// 姿态综合得分下限，低于此值视为「不值得瞄准」。
  static const double poseScoreMin = 0.35;

  /// top1 与 top2 得分差小于此值 → 判定「歧义」，交由玩家手动指认。
  static const double poseAmbiguityMargin = 0.08;

  /// 开火时检测结果的最大陈旧时间；超过则就地重跑一次识别，
  /// 消灭「准星已经移开、旧框还在」的竞态。
  static const int fireStaleMs = 80;

  // ---------------- 命中判定 ----------------
  /// person 框占屏幕总面积低于该比例 = 超出射程（不弹选人框）
  static const double minTargetAreaRatio = 0.005; 

  // ---------------- 节奏 ----------------
  /// 开火冷却
  static const Duration fireCooldown = Duration(seconds: 1);

  /// 「击中谁」弹窗 5 秒无操作自动取消
  static const Duration pickerTimeout = Duration(seconds: 5);

  // ---------------- 受击表现 ----------------
  /// 长震动时长
  static const Duration damageVibration = Duration(milliseconds: 500);

  /// 红光闪烁总时长（内部闪 2 次）
  static const Duration redFlashDuration = Duration(milliseconds: 1000);

  /// 「你被击中了！」停留时长
  static const Duration damageBannerDuration = Duration(milliseconds: 1200);
}
