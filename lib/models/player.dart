import '../app_config.dart';

/// 房间内一个玩家的快照。
/// 对应数据库结构：/rooms/{roomId}/players/{playerId}
///   name / hp / isDead / joinedAt / deathAt
class Player {
  const Player({
    required this.id,
    required this.name,
    required this.hp,
    required this.isDead,
    this.joinedAt = 0,
    this.deathAt,
  });

  final String id;
  final String name;
  final int hp;
  final bool isDead;

  /// 进房时间（客户端毫秒时间戳），用于确定房主先后顺序与排名
  final int joinedAt;

  /// 阵亡时间（客户端毫秒时间戳），用于算最终排名
  final int? deathAt;

  /// 存活 = 没被标记阵亡 且 血量 > 0
  bool get isAlive => !isDead && hp > 0;

  /// 从 Realtime Database 的原始值构造。容错优先：字段缺失/类型不对都不抛异常。
  static Player fromSnapshot(String id, Object? value) {
    final map = (value is Map) ? value : const <Object?, Object?>{};
    return Player(
      id: id,
      name: (map['name'] is String) ? map['name'] as String : '玩家',
      hp: (map['hp'] is num) ? (map['hp'] as num).toInt() : Cfg.maxHp,
      isDead: map['isDead'] == true,
      joinedAt: (map['joinedAt'] is num) ? (map['joinedAt'] as num).toInt() : 0,
      deathAt: (map['deathAt'] is num) ? (map['deathAt'] as num).toInt() : null,
    );
  }

  @override
  String toString() => 'Player($id, $name, hp=$hp, dead=$isDead)';
}
