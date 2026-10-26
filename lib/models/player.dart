import '../app_config.dart';
import 'team.dart';

/// 房间内一个玩家的快照。
/// 对应数据库结构：/rooms/{roomId}/players/{playerId}
///   name / hp / isDead / joinedAt / deathAt / team / kills / invincibleUntil
///
/// 旧数据没有 team/kills/invincibleUntil 时全部走安全默认值，不抛异常。
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.hp,
    required this.isDead,
    this.joinedAt = 0,
    this.deathAt,
    this.team,
    this.kills = 0,
    this.invincibleUntil,
  });

  final String id;
  final String name;
  final int hp;
  final bool isDead;

  /// 进房时间（客户端毫秒时间戳），用于确定房主先后顺序
  final int joinedAt;

  /// 阵亡时间（服务器基准毫秒时间戳），用于复活批次校验
  final int? deathAt;

  /// 所属小队；null = 还没选队
  final Team? team;

  /// 个人击杀数
  final int kills;

  /// 无敌截止时间（服务器基准毫秒时间戳）；null/0 = 不在保护中
  final int? invincibleUntil;

  /// 存活 = 没被标记阵亡 且 血量 > 0
  bool get isAlive => !isDead && hp > 0;

  /// 在服务器时间 [serverNowMs] 下是否处于复活保护。
  /// 远超正常保护窗口的时间戳视为时钟异常，不再显示/生效（同 CombatRules）。
  bool isInvincibleAt(int serverNowMs) {
    final until = invincibleUntil;
    if (until == null || until <= serverNowMs) return false;
    return until - serverNowMs <= Cfg.maxInvincibleSkewMs;
  }

  /// 只改队伍归属的副本（乐观更新 / 回滚用）
  Player withTeam(Team? value) => Player(
        id: id,
        name: name,
        hp: hp,
        isDead: isDead,
        joinedAt: joinedAt,
        deathAt: deathAt,
        team: value,
        kills: kills,
        invincibleUntil: invincibleUntil,
      );

  /// 从 Realtime Database 的原始值构造。容错优先：字段缺失/类型不对都不抛异常。
  static Player fromSnapshot(String id, Object? value) {
    final map = (value is Map) ? value : const <Object?, Object?>{};
    final rawKills = map['kills'];
    final kills = (rawKills is num) ? rawKills.toInt() : 0;
    return Player(
      id: id,
      name: (map['name'] is String) ? map['name'] as String : '玩家',
      hp: (map['hp'] is num) ? (map['hp'] as num).toInt() : Cfg.maxHp,
      isDead: map['isDead'] == true,
      joinedAt: (map['joinedAt'] is num) ? (map['joinedAt'] as num).toInt() : 0,
      deathAt: (map['deathAt'] is num) ? (map['deathAt'] as num).toInt() : null,
      team: Team.fromKey(map['team']),
      kills: kills < 0 ? 0 : kills,
      invincibleUntil: (map['invincibleUntil'] is num)
          ? (map['invincibleUntil'] as num).toInt()
          : null,
    );
  }

  @override
  String toString() =>
      'Player($id, $name, team=${team?.key}, hp=$hp, dead=$isDead, '
      'kills=$kills, invincibleUntil=$invincibleUntil)';
}
