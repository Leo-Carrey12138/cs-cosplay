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
