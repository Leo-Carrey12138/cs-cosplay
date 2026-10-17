import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../models/feed_item.dart';
import '../models/player.dart';
import '../services/room_service.dart';

/// 一局对战的所有共享状态。UI 只读它，写操作都走这里。
class GameSession extends ChangeNotifier {
  GameSession({RoomService? service}) : _service = service ?? RoomService();

  final RoomService _service;

  // ---------------- 房间身份 ----------------
  String roomId = '';
  String playerId = '';
  String nickname = '';
  String hostId = '';

  // ---------------- 房间数据 ----------------
  Map<String, Player> players = <String, Player>{};
  List<FeedItem> feed = <FeedItem>[];

  // ---------------- 本机状态 ----------------
  int myHp = Cfg.maxHp;
  bool iAmDead = false;
  int? myRank;

  bool loading = false;
  String? errorMessage;

  // ---------------- 一次性事件（给 UI 播动画/音效用） ----------------
  final StreamController<int> _damageCtrl = StreamController<int>.broadcast();
  final StreamController<String> _toastCtrl = StreamController<String>.broadcast();

  /// 自己掉血（参数 = 掉了多少点）
  Stream<int> get onDamaged => _damageCtrl.stream;

  /// 需要弹一下的短提示
  Stream<String> get onToast => _toastCtrl.stream;

  StreamSubscription<Map<String, Player>>? _playersSub;
  StreamSubscription<List<FeedItem>>? _feedSub;

  bool _primed = false;
  bool _checkingHost = false;
  bool _disposed = false;

  // ---------------- 派生状态 ----------------
  bool get isHost => hostId.isNotEmpty && hostId == playerId;
  Player? get me => players[playerId];
  bool get joined => roomId.isNotEmpty && playerId.isNotEmpty;

  /// 除自己以外的存活玩家，最多 5 个（选人弹窗用）
  List<Player> get aliveTargets => players.values
      .where((p) => p.id != playerId && p.isAlive)
      .toList()
    ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

  /// 血条列表排序：活着的在前（血量高的在前），阵亡的沉底
  List<Player> get sortedPlayers {
    final list = players.values.toList()
      ..sort((a, b) {
        if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
        if (a.isAlive && b.isAlive) return b.hp.compareTo(a.hp);
        return (a.deathAt ?? 0).compareTo(b.deathAt ?? 0);
      });
    return list;
  }

  // ------------------------------------------------------------------
  // 加入 / 离开
  // ------------------------------------------------------------------

  Future<bool> join({required String room, required String name}) async {
    loading = true;
    errorMessage = null;
    _safeNotify();

    // 每个客户端一个随机 playerId（无需账号体系）
    final id = 'p_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '_${math.Random().nextInt(0xFFFF).toRadixString(36)}';

    final result = await _service.join(roomId: room, playerId: id, name: name);
    if (!result.ok) {
      loading = false;
      errorMessage = result.reason ?? '加入失败';
      _safeNotify();
      return false;
    }

    roomId = room;
    playerId = id;
    nickname = name;
    myHp = Cfg.maxHp;
    iAmDead = false;
    myRank = null;
    _primed = false;

    hostId = (await _service.fetchHostId(room)) ?? '';
    _playersSub = _service.watchPlayers(room).listen(_onPlayersSnapshot, onError: (Object e) {
      debugPrint('players 监听异常: $e');
    });
    _feedSub = _service.watchFeed(room).listen((items) {
      feed = items;
      _safeNotify();
    }, onError: (Object e) {
      debugPrint('feed 监听异常: $e');
    });

    loading = false;
    _safeNotify();
    return true;
  }

  Future<void> leave() async {
    await _playersSub?.cancel();
    await _feedSub?.cancel();
    _playersSub = null;
    _feedSub = null;
    if (roomId.isNotEmpty && playerId.isNotEmpty) {
      await _service.leave(roomId, playerId);
    }
    players = <String, Player>{};
    feed = <FeedItem>[];
    roomId = '';
    playerId = '';
    hostId = '';
    myHp = Cfg.maxHp;
    iAmDead = false;
    myRank = null;
    _safeNotify();
  }

  // ------------------------------------------------------------------
  // 核心：血量变化处理（受击表现 + 阵亡 + 排名）
  // ------------------------------------------------------------------

  void _onPlayersSnapshot(Map<String, Player> next) {
    final prevHp = myHp;
    final mine = next[playerId];

    if (mine != null) {
      final drop = prevHp - mine.hp;

      // 掉血 → 通知 UI 播震动/红光/音效
      // _primed 用来跳过"刚进房的第一帧"，避免把初始值当掉血
      if (_primed && drop > 0 && prevHp > 0) {
        _damageCtrl.add(drop);
      }

      if (mine.hp <= 0) {
        if (!iAmDead) {
          // hp ≤ 0 → 由自己写入 isDead = true（题目要求）
          iAmDead = true;
          myRank = _computeRank(next);
          final deathAt = DateTime.now().millisecondsSinceEpoch;
          unawaited(_service.markDead(roomId, playerId, deathAt));
        }
      } else {
        // 血量回满（房主重开）→ 清空阵亡状态
        if (iAmDead) {
          iAmDead = false;
          myRank = null;
        }
      }
      myHp = mine.hp;
    }

    players = next;
    _primed = true;
    _safeNotify();

    // 房主掉线兜底（带防抖，避免每次快照都去读一次数据库）
    if (!_checkingHost && next.isNotEmpty) {
      final currentHost = hostId;
      final hostMissing = currentHost.isEmpty || !next.containsKey(currentHost);
      if (hostMissing) {
        _checkingHost = true;
        unawaited(
          _service.ensureHostFallback(roomId, playerId, next).then((_) async {
            final updated = await _service.fetchHostId(roomId);
            if (updated != null && updated != hostId) {
              hostId = updated;
              _safeNotify();
            }
          }).whenComplete(() {
            _checkingHost = false;
          }),
        );
      }
    }
  }

  /// 排名规则：
  ///   · 还活着的人排在你前面
  ///   · 比你早阵亡的人排在你前面
  ///   · 所以 名次 = 活人 + 比我早死的人 + 1
  int _computeRank(Map<String, Player> all) {
    final myDeathAt = DateTime.now().millisecondsSinceEpoch;
    var alive = 0;
    var deadEarlier = 0;
    for (final p in all.values) {
      if (p.id == playerId) continue;
      if (p.isAlive) {
        alive++;
      } else if ((p.deathAt ?? 0) < myDeathAt) {
        deadEarlier++;
      }
    }
    return alive + deadEarlier + 1;
  }

  // ------------------------------------------------------------------
  // 开火 → 扣血
  // ------------------------------------------------------------------

  /// 确认击中某个玩家。返回扣血后的 HP；返回 null 表示事务没落地。
  Future<int?> confirmHit(String targetId) async {
    final targetName = players[targetId]?.name ?? '对手';
    final result = await _service.applyDamage(roomId: roomId, targetId: targetId);
    if (!result.committed) {
      _toastCtrl.add('目标已经阵亡或掉线');
      return null;
    }
    await _service.pushFeed(roomId, '$nickname 命中 $targetName  -${Cfg.damagePerHit}');
    return result.hpAfter;
  }

  // ------------------------------------------------------------------
  // 房主：重开一局
  // ------------------------------------------------------------------

  Future<void> resetGame() async {
    if (!isHost) {
      _toastCtrl.add('只有房主能重开');
      return;
    }
    await _service.resetGame(roomId, players);
    await _service.pushFeed(roomId, '房主重开了一局');
    myRank = null;
  }

  void toast(String message) {
    if (!_disposed) _toastCtrl.add(message);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playersSub?.cancel();
    _feedSub?.cancel();
    _damageCtrl.close();
    _toastCtrl.close();
    super.dispose();
  }
}
