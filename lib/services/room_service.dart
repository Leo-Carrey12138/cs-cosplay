import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

import '../app_config.dart';
import '../models/feed_item.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'combat_rules.dart';
import 'team_rules.dart';

/// 加入房间的结果
class JoinResult {
  const JoinResult.ok(this.status)
      : ok = true,
        reason = null;
  const JoinResult.failed(this.reason)
      : ok = false,
        status = null;

  final bool ok;
  final String? reason;

  /// 加入成功时房间的当前状态（lobby / playing）
  final String? status;
}

/// 选队 / 自动分配的结果
class TeamChangeResult {
  const TeamChangeResult.ok(this.team)
      : ok = true,
        reason = null;
  const TeamChangeResult.failed(this.reason)
      : ok = false,
        team = null;

  final bool ok;
  final Team? team;
  final String? reason;
}

/// 复活事务的结果
class RespawnResult {
  const RespawnResult.ok()
      : ok = true,
        reason = null,
        batchMismatch = false;
  const RespawnResult.failed(this.reason)
      : ok = false,
        batchMismatch = false;

  /// 不再处于该死亡批次（已被重置 / 已复活 / 已重新死亡），不应重试
  const RespawnResult.batchMismatch(this.reason)
      : ok = false,
        batchMismatch = true;

  final bool ok;
  final String? reason;
  final bool batchMismatch;
}

/// Realtime Database 封装。
///
/// 所有会互相影响的数据（人数、队伍、扣血、击杀、复活）都走同一棵
/// `rooms/{roomId}` 上的事务，避免「先扣血、后单独 increment」这类竞态。
class RoomService {
  RoomService({FirebaseDatabase? database})
      : _db = database ??
            FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL:
                  'https://cs-cosplay-default-rtdb.asia-southeast1.firebasedatabase.app/',
            ) {
    // 不同手机的本地时钟可能不一致。用 Firebase 提供的偏移估算服务器时间，
    // deathAt / invincibleUntil / 伤害判定统一用这个基准。
    try {
      _offsetSub = _db.ref('.info/serverTimeOffset').onValue.listen(
        (event) {
          final value = event.snapshot.value;
          if (value is num) _serverTimeOffsetMs = value.toInt();
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // 离线 / 初始化早期拿不到 offset 时回退到本机时间（见 serverNowMs）。
    }
  }

  final FirebaseDatabase _db;

  StreamSubscription<DatabaseEvent>? _offsetSub;
  int _serverTimeOffsetMs = 0;

  /// 估算的服务器当前毫秒时间。
  ///
  /// offset 尚未取到时为 0（退化为本机时间）；配合 CombatRules 里
  /// [Cfg.maxInvincibleSkewMs] 的上限，不会因为拿不到 offset 永久无敌。
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

  Future<void> dispose() async {
    await _offsetSub?.cancel();
    _offsetSub = null;
  }

  DatabaseReference roomRef(String roomId) => _db.ref('rooms/$roomId');
  DatabaseReference playersRef(String roomId) =>
      _db.ref('rooms/$roomId/players');
  DatabaseReference playerRef(String roomId, String playerId) =>
      _db.ref('rooms/$roomId/players/$playerId');
  DatabaseReference hostRef(String roomId) => _db.ref('rooms/$roomId/hostId');
  DatabaseReference feedRef(String roomId) => _db.ref('rooms/$roomId/feed');

  // ------------------------------------------------------------------
  // 原始值解析（事务里所有字段都可能缺失 / 类型不对）
  // ------------------------------------------------------------------

  static Map<String, Object?> _mapOf(Object? value) {
    final out = <String, Object?>{};
    if (value is Map) {
      value.forEach((key, val) => out['$key'] = val);
    }
    return out;
  }

  static Map<String, Object?> _playersOf(Map<String, Object?> room) {
    final out = <String, Object?>{};
    final raw = room['players'];
    if (raw is Map) {
      raw.forEach((key, value) {
        out['$key'] = value is Map ? _mapOf(value) : value;
      });
    }
    return out;
  }

  static int _intOf(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  static int? _nullableIntOf(Object? value) =>
      value is num ? value.toInt() : null;

  static String _statusOf(Map<String, Object?> room) =>
      room['status'] == Cfg.roomStatusPlaying
          ? Cfg.roomStatusPlaying
          : Cfg.roomStatusLobby;

  static bool _isDead(Map<String, Object?> player) =>
      player['isDead'] == true || _intOf(player['hp'], Cfg.maxHp) <= 0;

  static int _countTeam(
    Map<String, Object?> players,
    Team team, {
    String? excludeId,
  }) {
    var count = 0;
    players.forEach((id, raw) {
      if (id == excludeId || raw is! Map) return;
      if (Team.fromKey(raw['team']) == team) count++;
    });
    return count;
  }

  // ------------------------------------------------------------------
  // 加入 / 离开
  // ------------------------------------------------------------------

  Future<JoinResult> join({
    required String roomId,
    required String playerId,
    required String name,
  }) async {
    String? failure;
    String status = Cfg.roomStatusLobby;
    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        final room = _mapOf(raw);
        var currentStatus = _statusOf(room);
        final players = _playersOf(room);

        if (currentStatus == Cfg.roomStatusPlaying && players.isNotEmpty) {
          failure = '该房间正在对战中';
          return Transaction.abort();
        }

        // 房间已空（正常离开或掉线被 onDisconnect 清空）→ 自动回到 lobby，
        // 清掉上一局战报，让这个 4 位房间号可以继续复用。
        if (players.isEmpty) {
          currentStatus = Cfg.roomStatusLobby;
          room.remove('feed');
        }
        status = currentStatus;

        if (!players.containsKey(playerId) &&
            players.length >= Cfg.maxPlayers) {
          failure = '房间已满（最多 ${Cfg.maxPlayers} 人）';
          return Transaction.abort();
        }

        players[playerId] = <String, Object?>{
          'name': name,
          'hp': Cfg.maxHp,
          'isDead': false,
          'joinedAt': DateTime.now().millisecondsSinceEpoch,
          'deathAt': null,
          'team': null,
          'kills': 0,
          'invincibleUntil': 0,
        };

        // 房间不存在 / 旧房间没有 status → 统一落到 lobby
        room['status'] = currentStatus;
        room['players'] = players;

        // 房主在同一个事务里认领，避免两个客户端同时抢
        final host = room['hostId'];
        if (host is! String || host.isEmpty || !players.containsKey(host)) {
          room['hostId'] = playerId;
        }
        return Transaction.success(room);
      });

      if (!result.committed) {
        return JoinResult.failed(failure ?? '加入失败');
      }

      try {
        await playerRef(roomId, playerId).onDisconnect().remove();
      } catch (_) {}
      return JoinResult.ok(status);
    } catch (e) {
      return JoinResult.failed('加入失败：$e');
    }
  }

  Future<void> ensureHostFallback(
    String roomId,
    String myPlayerId,
    Map<String, Player> players,
  ) async {
    if (players.isEmpty) return;
    try {
      final snapshot = await hostRef(roomId).get();
      final current = snapshot.value;
      final hostAlive = current is String &&
          current.isNotEmpty &&
          players.containsKey(current);
      if (hostAlive) return;

      final ordered = players.values.toList()
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      if (ordered.first.id != myPlayerId) return;
      await hostRef(roomId).set(myPlayerId);
    } catch (_) {}
  }

  Future<void> leave(String roomId, String playerId) async {
    try {
      await playerRef(roomId, playerId).onDisconnect().remove();
    } catch (_) {}
    try {
      await playerRef(roomId, playerId).remove();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // 小队
  // ------------------------------------------------------------------

  /// 选择 / 切换小队。人数上限在事务内用数据库里的最新值判断。
  Future<TeamChangeResult> selectTeam({
    required String roomId,
    required String playerId,
    required Team team,
  }) async {
    String? failure;
    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        final room = _mapOf(raw);
        if (_statusOf(room) == Cfg.roomStatusPlaying) {
          failure = '对局已开始，不能换队';
          return Transaction.abort();
        }

        final players = _playersOf(room);
        final rawMe = players[playerId];
        if (rawMe is! Map) {
          failure = '你已不在房间';
          return Transaction.abort();
        }
        final me = _mapOf(rawMe);
        if (Team.fromKey(me['team']) == team) {
          return Transaction.success(room);
        }

        final others = _countTeam(players, team, excludeId: playerId);
        if (!TeamRules.hasRoom(others)) {
          failure = '该小队已满';
          return Transaction.abort();
        }

        me['team'] = team.key;
        players[playerId] = me;
        room['players'] = players;
        return Transaction.success(room);
      });

      if (result.committed) return TeamChangeResult.ok(team);
      return TeamChangeResult.failed(failure ?? '加入小队失败');
    } catch (e) {
      return TeamChangeResult.failed('加入小队失败：$e');
    }
  }

  /// 自动分配到人数较少的一队（相同则 ALPHA）。
  Future<TeamChangeResult> autoAssignTeam({
    required String roomId,
    required String playerId,
  }) async {
    String? failure;
    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        final room = _mapOf(raw);
        if (_statusOf(room) == Cfg.roomStatusPlaying) {
          failure = '对局已开始，不能换队';
          return Transaction.abort();
        }

        final players = _playersOf(room);
        final rawMe = players[playerId];
        if (rawMe is! Map) {
          failure = '你已不在房间';
          return Transaction.abort();
        }

        final alpha = _countTeam(players, Team.alpha, excludeId: playerId);
        final bravo = _countTeam(players, Team.bravo, excludeId: playerId);
        var picked = TeamRules.autoPick(alphaCount: alpha, bravoCount: bravo);
        if (!TeamRules.hasRoom(picked == Team.alpha ? alpha : bravo)) {
          picked = picked == Team.alpha ? Team.bravo : Team.alpha;
          if (!TeamRules.hasRoom(picked == Team.alpha ? alpha : bravo)) {
            failure = '两队都已满员';
            return Transaction.abort();
          }
        }

        final me = _mapOf(rawMe);
        me['team'] = picked.key;
        players[playerId] = me;
        room['players'] = players;
        return Transaction.success(room);
      });

      if (result.committed) {
        final raw = result.snapshot.value;
        final room = _mapOf(raw);
        final me = _mapOf(_playersOf(room)[playerId]);
        final picked = Team.fromKey(me['team']);
        return TeamChangeResult.ok(picked ?? Team.alpha);
      }
      return TeamChangeResult.failed(failure ?? '自动分配失败');
    } catch (e) {
      return TeamChangeResult.failed('自动分配失败：$e');
    }
  }

  // ------------------------------------------------------------------
  // 对局状态
  // ------------------------------------------------------------------

  /// 房主开始对战：所有玩家必须已选队，且每队不超员。
  /// 成功返回 null，失败返回给用户看的原因。
  Future<String?> startGame({
    required String roomId,
    required String hostId,
  }) async {
    String? failure;
    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        final room = _mapOf(raw);
        if (room['hostId'] != hostId) {
          failure = '只有房主能开始对战';
          return Transaction.abort();
        }
        if (_statusOf(room) == Cfg.roomStatusPlaying) {
          failure = '对局已经开始';
          return Transaction.abort();
        }

        final players = _playersOf(room);
        if (players.isEmpty) {
          failure = '房间里没有玩家';
          return Transaction.abort();
        }

        var alpha = 0;
        var bravo = 0;
        for (final rawPlayer in players.values) {
          if (rawPlayer is! Map) {
            failure = '还有玩家未选择小队';
            return Transaction.abort();
          }
          final team = Team.fromKey(rawPlayer['team']);
          if (team == null) {
            failure = '还有玩家未选择小队';
            return Transaction.abort();
          }
          if (team == Team.alpha) {
            alpha++;
          } else {
            bravo++;
          }
        }
        if (alpha > Cfg.teamCapacity || bravo > Cfg.teamCapacity) {
          failure = '小队人数超出上限';
          return Transaction.abort();
        }

        room['status'] = Cfg.roomStatusPlaying;
        return Transaction.success(room);
      });

      return result.committed ? null : (failure ?? '开始对战失败');
    } catch (e) {
      return '开始对战失败：$e';
    }
  }

  /// 房主重开一局：保留队伍，满血复活，击杀清零，清空上一局战报。
  Future<String?> resetGame({
    required String roomId,
    required String hostId,
  }) async {
    String? failure;
    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        final room = _mapOf(raw);
        if (room['hostId'] != hostId) {
          failure = '只有房主能重开';
          return Transaction.abort();
        }

        final players = _playersOf(room);
        if (players.isEmpty) {
          failure = '房间里没有玩家';
          return Transaction.abort();
        }

        for (final id in players.keys.toList()) {
          final rawPlayer = players[id];
          if (rawPlayer is! Map) continue;
          players[id] = CombatRules.resetPlayer(_mapOf(rawPlayer));
        }

        room['players'] = players;
        room.remove('feed');
        return Transaction.success(room);
      });

      return result.committed ? null : (failure ?? '重置失败');
    } catch (e) {
      return '重置失败：$e';
    }
  }

  // ------------------------------------------------------------------
  // 伤害 / 复活
  // ------------------------------------------------------------------

  /// 确认命中：在同一个事务里完成「目标扣血/阵亡 + 攻击者 kills+1」。
  ///
  /// 队伍关系、目标存活状态、无敌时间都重新以数据库为准，不信任 UI 快照。
  Future<CombatDecision> applyCombatDamage({
    required String roomId,
    required String attackerId,
    required String targetId,
    int amount = Cfg.damagePerHit,
  }) async {
    if (attackerId == targetId) {
      return const CombatDecision(CombatOutcome.selfBlocked);
    }

    final serverNow = serverNowMs;
    var decision = const CombatDecision(CombatOutcome.failed);

    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        final room = _mapOf(raw);
        if (_statusOf(room) != Cfg.roomStatusPlaying) {
          decision = const CombatDecision(CombatOutcome.targetUnavailable);
          return Transaction.abort();
        }

        final players = _playersOf(room);
        final rawAttacker = players[attackerId];
        final rawTarget = players[targetId];
        final attackerExists = rawAttacker is Map;
        final targetExists = rawTarget is Map;
        final attacker =
            attackerExists ? _mapOf(rawAttacker) : const <String, Object?>{};
        final target =
            targetExists ? _mapOf(rawTarget) : const <String, Object?>{};

        final evaluated = CombatRules.evaluate(
          attackerExists: attackerExists,
          attackerDead: attackerExists && _isDead(attacker),
          attackerTeam: Team.fromKey(attacker['team']),
          targetExists: targetExists,
          targetHp: _intOf(target['hp'], Cfg.maxHp),
          targetDead: targetExists && _isDead(target),
          targetTeam: Team.fromKey(target['team']),
          targetInvincibleUntil: _intOf(target['invincibleUntil'], 0),
          serverNow: serverNow,
          isSelf: attackerId == targetId,
          amount: amount,
        );
        decision = evaluated;
        if (!evaluated.committed) return Transaction.abort();

        final targetOut = Map<String, Object?>.from(target);
        targetOut['hp'] = evaluated.hpAfter;
        if (evaluated.killAwarded) {
          targetOut['isDead'] = true;
          targetOut['deathAt'] = serverNow;
        }
        players[targetId] = targetOut;

        if (evaluated.killAwarded) {
          final attackerOut = Map<String, Object?>.from(attacker);
          final currentKills = _intOf(attackerOut['kills'], 0);
          attackerOut['kills'] = currentKills < 0 ? 1 : currentKills + 1;
          players[attackerId] = attackerOut;
        }

        room['players'] = players;
        return Transaction.success(room);
      });

      if (!result.committed) {
        // 本地跑过但最终没提交（网络/并发失败），不能当成扣血成功。
        return decision.committed
            ? const CombatDecision(CombatOutcome.failed)
            : decision;
      }
      return decision;
    } catch (_) {
      return const CombatDecision(CombatOutcome.failed);
    }
  }

  /// 阵亡玩家自己的客户端发起复活。事务内校验死亡批次，旧 Timer 不会覆盖新状态。
  Future<RespawnResult> respawn({
    required String roomId,
    required String playerId,
    required int? expectedDeathAt,
  }) async {
    final now = serverNowMs;
    String? failure;
    var mismatch = false;

    try {
      final result = await roomRef(roomId).runTransaction((raw) {
        failure = null;
        mismatch = false;
        final room = _mapOf(raw);
        final players = _playersOf(room);
        final rawMe = players[playerId];
        if (rawMe is! Map) {
          failure = '玩家已离开房间';
          mismatch = true;
          return Transaction.abort();
        }

        final me = _mapOf(rawMe);
        final currentDeathAt = _nullableIntOf(me['deathAt']);
        if (!RespawnGuard.canRespawn(
          isDead: _isDead(me),
          currentDeathAt: currentDeathAt,
          expectedDeathAt: expectedDeathAt,
        )) {
          failure = '复活批次已失效';
          mismatch = true;
          return Transaction.abort();
        }

        me['hp'] = Cfg.maxHp;
        me['isDead'] = false;
        me['deathAt'] = null;
        me['invincibleUntil'] = now + Cfg.respawnInvincible.inMilliseconds;
        players[playerId] = me;
        room['players'] = players;
        return Transaction.success(room);
      });

      if (result.committed) return const RespawnResult.ok();
      return mismatch
          ? RespawnResult.batchMismatch(failure)
          : RespawnResult.failed(failure ?? '复活失败');
    } catch (e) {
      return RespawnResult.failed('复活失败：$e');
    }
  }

  // ------------------------------------------------------------------
  // 监听 / 战报
  // ------------------------------------------------------------------

  Stream<Map<String, Player>> watchPlayers(String roomId) {
    return playersRef(roomId).onValue.map((event) {
      final out = <String, Player>{};
      final value = event.snapshot.value;
      if (value is Map) {
        value.forEach((key, val) {
          out['$key'] = Player.fromSnapshot('$key', val);
        });
      }
      return out;
    });
  }

  /// 房间状态；旧数据没有 status 时视为 lobby。
  Stream<String> watchStatus(String roomId) {
    return _db.ref('rooms/$roomId/status').onValue.map((event) {
      final value = event.snapshot.value;
      return value == Cfg.roomStatusPlaying
          ? Cfg.roomStatusPlaying
          : Cfg.roomStatusLobby;
    });
  }

  Stream<List<FeedItem>> watchFeed(String roomId) {
    return feedRef(roomId).orderByKey().limitToLast(3).onValue.map((event) {
      final items = <FeedItem>[];
      final value = event.snapshot.value;
      if (value is Map) {
        value.forEach((key, val) {
          final item = FeedItem.fromSnapshot('$key', val);
          if (item != null) items.add(item);
        });
      }
      items.sort((a, b) => b.ts.compareTo(a.ts));
      return items;
    });
  }

  Future<void> pushFeed(String roomId, String text) async {
    try {
      await feedRef(roomId).push().set(<String, Object?>{
        'text': text,
        'ts': serverNowMs,
      });
    } catch (_) {}
  }

  Future<String?> fetchHostId(String roomId) async {
    try {
      final snapshot = await hostRef(roomId).get();
      final value = snapshot.value;
      return (value is String) ? value : null;
    } catch (_) {
      return null;
    }
  }
}
