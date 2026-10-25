import 'package:flutter/material.dart';

import '../models/team.dart';

/// 小队配色：ALPHA 琥珀/沙色（暖），BRAVO 蓝色（冷）。
class TeamStyle {
  TeamStyle._();

  static const Color alpha = Color(0xFFFFB300);
  static const Color bravo = Color(0xFF40C4FF);
  static const Color unknown = Color(0xFF9E9E9E);

  static Color colorOf(Team? team) {
    if (team == Team.alpha) return alpha;
    if (team == Team.bravo) return bravo;
    return unknown;
  }

  /// 卡片底色用的低透明度队色
  static Color tintOf(Team? team) => colorOf(team).withValues(alpha: 0.14);

  /// 队伍单字标识（A / B / ?）
  static String initialOf(Team? team) {
    if (team == Team.alpha) return 'A';
    if (team == Team.bravo) return 'B';
    return '?';
  }
}
