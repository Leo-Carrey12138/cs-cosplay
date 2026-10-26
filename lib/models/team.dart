/// 对战小队。数据库里存小写字符串：alpha / bravo；未选队时为 null。
enum Team {
  alpha,
  bravo;

  /// 写入 Realtime Database 的值
  String get key => name;

  /// UI 展示名
  String get label => this == Team.alpha ? 'ALPHA' : 'BRAVO';

  /// 解析数据库里的值，非法/缺失一律视为未选队
  static Team? fromKey(Object? value) {
    if (value == Team.alpha.key) return Team.alpha;
    if (value == Team.bravo.key) return Team.bravo;
    return null;
  }
}
