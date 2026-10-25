import '../app_config.dart';
import '../models/team.dart';

/// 一次伤害请求的权威判定结果。
///
/// 用明确的结果类型代替旧的 `committed: false`，避免把「队友免疫 / 无敌 /
/// 目标已死 / 网络失败」混成同一句提示。
enum CombatOutcome {
  /// 普通命中，只扣血
  applied,

  /// 本次伤害把敌人打到 0 血
  killed,

  /// 目标是队友，伤害被免疫
  friendlyBlocked,

  /// 目标处于复活保护
  invincibleBlocked,

  /// 目标不存在、已阵亡或已离开
  targetUnavailable,

  /// 不能攻击自己
  selfBlocked,

  /// 攻击者不存在或已阵亡
  attackerUnavailable,

  /// 网络 / 数据库失败
  failed,
}

/// 伤害判定的结构化结果。
class CombatDecision {
  const CombatDecision(
    this.outcome, {
    this.hpAfter = 0,
    this.killAwarded = false,
  });

  final CombatOutcome outcome;

  /// 结算后的目标血量（被拦截时为当前血量）
  final int hpAfter;

  /// 本次是否给攻击者 +1 击杀
  final bool killAwarded;

  /// 是否真的改写了数据（只有 applied / killed 是）
  bool get committed =>
      outcome == CombatOutcome.applied || outcome == CombatOutcome.killed;
}

/// 纯战斗规则：输入双方快照 + 服务器时间，输出唯一判定。
///
/// RoomService 的 RTDB 事务里重新读取双方数据后调用这里，UI 传入的
/// Player 快照不参与判定。
class CombatRules {
  CombatRules._();

  static CombatDecision evaluate({
    required bool attackerExists,
    required bool attackerDead,
    required Team? attackerTeam,
    required bool targetExists,
    required int targetHp,
    required bool targetDead,
    required Team? targetTeam,
    required int targetInvincibleUntil,
    required int serverNow,
    required bool isSelf,
    int amount = Cfg.damagePerHit,
  }) {
    if (!attackerExists || attackerDead) {
      return const CombatDecision(CombatOutcome.attackerUnavailable);
    }
    if (!targetExists) {
      return const CombatDecision(CombatOutcome.targetUnavailable);
    }
    if (isSelf) {
      return const CombatDecision(CombatOutcome.selfBlocked);
    }
    if (targetDead || targetHp <= 0) {
      return const CombatDecision(
        CombatOutcome.targetUnavailable,
        hpAfter: 0,
      );
    }
    // 队伍关系以数据库里的最新值为准；未选队的旧数据不算队友。
    if (attackerTeam != null &&
        targetTeam != null &&
        attackerTeam == targetTeam) {
      return CombatDecision(
        CombatOutcome.friendlyBlocked,
        hpAfter: targetHp,
      );
    }
    if (isInvincible(targetInvincibleUntil, serverNow)) {
      return CombatDecision(
        CombatOutcome.invincibleBlocked,
        hpAfter: targetHp,
      );
    }

    final hpAfter = targetHp - amount < 0 ? 0 : targetHp - amount;
    if (hpAfter == 0) {
      return const CombatDecision(
        CombatOutcome.killed,
        hpAfter: 0,
        killAwarded: true,
      );
    }
    return CombatDecision(CombatOutcome.applied, hpAfter: hpAfter);
  }

  /// 保护期是否仍然有效。
  ///
  /// 用严格大于：`invincibleUntil == serverNow` 时保护刚好结束，可以扣血。
  /// 超过 [Cfg.maxInvincibleSkewMs] 的未来时间戳视为时钟异常（见配置注释）。
  static bool isInvincible(int invincibleUntil, int serverNow) {
    if (invincibleUntil <= serverNow) return false;
    return invincibleUntil - serverNow <= Cfg.maxInvincibleSkewMs;
  }

  /// 房主重开时对单个玩家的重置（保留 name/team/joinedAt）。
  static Map<String, Object?> resetPlayer(Map<String, Object?> player) {
    final out = Map<String, Object?>.from(player);
    out['hp'] = Cfg.maxHp;
    out['isDead'] = false;
    out['deathAt'] = null;
    out['invincibleUntil'] = 0;
    out['kills'] = 0;
    return out;
  }
}

/// 复活事务的批次校验：旧 Timer 不能复活新的死亡批次。
class RespawnGuard {
  RespawnGuard._();

  /// 只有仍处于死亡状态，且 deathAt 与计划复活时完全一致才允许复活。
  static bool canRespawn({
    required bool isDead,
    required int? currentDeathAt,
    required int? expectedDeathAt,
  }) {
    if (!isDead) return false;
    return currentDeathAt == expectedDeathAt;
  }

  /// 距离复活还剩多少毫秒（用于本地倒计时，不写数据库）。
  static int remainingMs({
    required int? deathAt,
    required int serverNow,
    required int delayMs,
  }) {
    final base = deathAt ?? serverNow;
    final due = base + delayMs;
    return due > serverNow ? due - serverNow : 0;
  }
}
