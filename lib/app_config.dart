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
  /// 抽帧间隔：200ms 一帧（≈5 FPS）。ML Kit Pose（base 模型）单帧推理约
  /// 30~80ms，200ms 是「够瞄准又不把 UI 拖住」的保守取值。
  /// 真正的节拍还会被 vision_service 的忙等门限制，见 game_screen._onCameraFrame。
  static const Duration detectInterval = Duration(milliseconds: 200);

  // ---------------- 姿态检测（BlazePose 33 关键点，google_mlkit_pose_detection）----------------
  //
  // 【重要限制】当前插件走的是 ML Kit Pose，每帧只返回**一个**姿态
  // （画面里最显著的那个人），PoseDetectorOptions 里没有 numPoses 这种参数。
  // 所以「同时跟踪 2/6 个人」这个能力在当前实现下**不存在**。
  // 要多人必须换原生 MediaPipe Tasks（numPoses 可配）——那时 PoseJudge 不用改。
  //
  // 以下常量里，只有 poseMinLandmarks 是当前真正起作用的闸门；
  // posePresenceMin 与 poseScoreMin 的实际效果见各自注释。

  /// 姿态「存在感」下限：该姿态**可见关键点**置信度的均值低于此值 → 丢弃整条姿态。
  ///
  /// 【注意 F1】可见点的定义就是 confidence >= poseLandmarkMinLikelihood，
  /// 所以这个均值必然 >= poseLandmarkMinLikelihood。两个值当前都是 0.5，
  /// 这条闸门因此**恒为真、不起作用**。要让它生效，必须取 > 0.5（建议 0.6）。
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
  ///
  /// 【注意 F2】只要框住准星（画面中心），距离项就有下限 ≈0.40，
  /// 再加上 0.3*presence 与 0.2*可见点占比，最弱的合法姿态得分也 ≈0.65。
  /// 也就是说 0.35 这条线**实际不可达**（见 test/pose_judge_test.dart 里的
  /// characterization 用例）。等真机拿到距离数据后再重新标定，别凭感觉调。
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
