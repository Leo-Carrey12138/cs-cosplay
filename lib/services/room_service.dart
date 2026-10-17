import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

import '../app_config.dart';
import '../models/feed_item.dart';
import '../models/player.dart';

/// 加入房间的结果
class JoinResult {
  const JoinResult.ok() : ok = true, reason = null;
  const JoinResult.failed(this.reason) : ok = false;

  final bool ok;
  final String? reason;
}

/// 扣血事务的结果
class DamageResult {
  const DamageResult({required this.committed, required this.hpAfter});

  final bool committed;
  final int hpAfter;
}

/// Realtime Database 封装。
class RoomService {
  RoomService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: 'https://cs-cosplay-default-rtdb.asia-southeast1.firebasedatabase.app/',
          );

  final FirebaseDatabase _db;

  DatabaseReference roomRef(String roomId) => _db.ref('rooms/$roomId');
  DatabaseReference playersRef(String roomId) => _db.ref('rooms/$roomId/players');
  DatabaseReference playerRef(String roomId, String playerId) =>
      _db.ref('rooms/$roomId/players/$playerId');
  DatabaseReference hpRef(String roomId, String playerId) =>
      _db.ref('rooms/$roomId/players/$playerId/hp');
  DatabaseReference hostRef(String roomId) => _db.ref('rooms/$roomId/hostId');
  DatabaseReference feedRef(String roomId) => _db.ref('rooms/$roomId/feed');

  // ------------------------------------------------------------------
  // 加入 / 离开
  // ------------------------------------------------------------------

  Future<JoinResult> join({
    required String roomId,
    required String playerId,
    required String name,
  }) async {
    try {
      final snapshot = await playersRef(roomId).get();
      final players = <String, Object?>{};
      final current = snapshot.value;
      if (current is Map) {
        current.forEach((key, value) {
          players['$key'] = (value is Map)
              ? Map<String, Object?>.from(value)
              : value;
        });
      }

      final alreadyIn = players.containsKey(playerId);
      if (!alreadyIn && players.length >= Cfg.maxPlayers) {
        return JoinResult.failed('房间已满（最多 ${Cfg.maxPlayers} 人）');
      }

      players[playerId] = <String, Object?>{
        'name': name,
        'hp': Cfg.maxHp,
        'isDead': false,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
        'deathAt': null,
      };

      await playersRef(roomId).set(players);
      await playerRef(roomId, playerId).onDisconnect().remove();
      await claimHostIfEmpty(roomId, playerId);

      return const JoinResult.ok();
    } catch (e) {
      return JoinResult.failed('加入失败：$e');
    }
  }

  Future<void> claimHostIfEmpty(String roomId, String playerId) async {
    try {
      final snapshot = await hostRef(roomId).get();
      final current = snapshot.value;
      if (current is String && current.isNotEmpty) return;
      await hostRef(roomId).set(playerId);
    } catch (_) {}
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
      final hostAlive =
          current is String && current.isNotEmpty && players.containsKey(current);
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
  // 监听
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

  // ------------------------------------------------------------------
  // 扣血 / 阵亡 / 重开
  // ------------------------------------------------------------------

  Future<DamageResult> applyDamage({
    required String roomId,
    required String targetId,
    int amount = Cfg.damagePerHit,
  }) async {
    try {
      final snapshot = await hpRef(roomId, targetId).get();
      final raw = snapshot.value;
      if (raw is! num) {
        return const DamageResult(committed: false, hpAfter: 0);
      }
      final current = raw.toInt();
      if (current <= 0) {
        return const DamageResult(committed: false, hpAfter: 0);
      }
      final newHp = math.max(0, current - amount);
      await hpRef(roomId, targetId).set(newHp);
      return DamageResult(committed: true, hpAfter: newHp);
    } catch (_) {
      return const DamageResult(committed: false, hpAfter: 0);
    }
  }

  Future<void> markDead(String roomId, String playerId, int deathAt) async {
    try {
      await playerRef(roomId, playerId).update(<String, Object?>{
        'isDead': true,
        'deathAt': deathAt,
      });
    } catch (_) {}
  }

  Future<void> resetGame(String roomId, Map<String, Player> players) async {
    if (players.isEmpty) return;
    final updates = <String, Object?>{};
    for (final player in players.values) {
      updates['${player.id}/hp'] = Cfg.maxHp;
      updates['${player.id}/isDead'] = false;
      updates['${player.id}/deathAt'] = null;
    }
    await playersRef(roomId).update(updates);
  }

  Future<void> pushFeed(String roomId, String text) async {
    try {
      await feedRef(roomId).push().set(<String, Object?>{
        'text': text,
        'ts': DateTime.now().millisecondsSinceEpoch,
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
