import '../app_config.dart';
import '../models/team.dart';

/// 小队分配的纯规则（不依赖 Firebase，便于单测）。
class TeamRules {
  TeamRules._();

  /// 自动分配：加入当前人数较少的一队；人数相同选 ALPHA。
  ///
  /// [alphaCount] / [bravoCount] 是**除自己以外**的队员数。
  static Team autoPick({required int alphaCount, required int bravoCount}) {
    return alphaCount <= bravoCount ? Team.alpha : Team.bravo;
  }

  /// 该队是否还能再进人。
  static bool hasRoom(int currentCount) => currentCount < Cfg.teamCapacity;
}
