import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../models/feed_item.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../services/combat_rules.dart';
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

  /// lobby / playing
  String status = Cfg.roomStatusLobby;

  // ---------------- 房间数据 ----------------
  Map<String, Player> players = <String, Player>{};
  List<FeedItem> feed = <FeedItem>[];

  // ---------------- 本机状态 ----------------
  int myHp = Cfg.maxHp;
  bool iAmDead = false;

  bool loading = false;
  String? errorMessage;

  // ---------------- 复活 / 无敌（本地倒计时，不写数据库） ----------------
  /// 距离自动复活还剩多少毫秒
  final ValueNotifier<int> respawnRemainingMs = ValueNotifier<int>(0);

  /// 复活保护还剩多少毫秒
  final ValueNotifier<int> invincibleRemainingMs = ValueNotifier<int>(0);

  Timer? _countdownTicker;
  int? _deadBatchDeathAt;
  int _respawnAtServerMs = 0;
  int _invincibleUntilMs = 0;
  bool _respawning = false;
  int _respawnRetryAtMs = 0;

  // ---------------- 一次性事件（给 UI 播动画/音效用） ----------------
  final StreamController<int> _damageCtrl = StreamController<int>.broadcast();
  final StreamController<String> _toastCtrl =
      StreamController<String>.broadcast();

  /// 自己掉血（参数 = 掉了多少点）
  Stream<int> get onDamaged => _damageCtrl.stream;

  /// 需要弹一下的短提示
  Stream<String> get onToast => _toastCtrl.stream;

  StreamSubscription<Map<String, Player>>? _playersSub;
  StreamSubscription<List<FeedItem>>? _feedSub;
  StreamSubscription<String>? _statusSub;

  bool _primed = false;
  bool _checkingHost = false;
  bool _disposed = false;
  bool _leftRoom = false;

  /// 每次加入 / 离开自增，用来丢弃上一间房排队中的监听回调
  int _roomGeneration = 0;

  // ---------------- 派生状态 ----------------
  bool get isHost => hostId.isNotEmpty && hostId == playerId;
  Player? get me => players[playerId];
  Team? get myTeam => me?.team;
  bool get joined => roomId.isNotEmpty && playerId.isNotEmpty;
  bool get iAmInvincible => invincibleRemainingMs.value > 0;

  /// 估算的服务器当前时间
  int get serverNowMs => _service.serverNowMs;

  /// 所有玩家都已选队（房主开始对战的前提）
  bool get allPlayersAssigned =>
      players.isNotEmpty && players.values.every((p) => p.team != null);

  /// 某队总击杀
  int teamKills(Team team) => players.values
      .where((p) => p.team == team)
      .fold<int>(0, (sum, p) => sum + p.kills);

  int get alphaScore => teamKills(Team.alpha);
  int get bravoScore => teamKills(Team.bravo);

  /// 某队成员（按进房先后）
  List<Player> teamPlayers(Team team) {
    final list = players.values.where((p) => p.team == team).toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return list;
  }

  /// 除自己以外的存活敌人。UI 用它过滤目标列表；
  /// 真正的队友判定在 RoomService 事务里重新读取数据库完成。
  List<Player> get aliveEnemies {
    final mine = myTeam;
    final list = players.values
        .where((p) =>
            p.id != playerId && p.isAlive && (mine == null || p.team != mine))
        .toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return list;
  }

  /// 血条列表排序：按队伍分组，队内存活在前（血量高的在前），阵亡沉底
  List<Player> get sortedPlayers {
    int teamRank(Team? team) {
      if (team == Team.alpha) return 0;
      if (team == Team.bravo) return 1;
      return 2;
    }

    final list = players.values.toList()
      ..sort((a, b) {
        final teamOrder = teamRank(a.team).compareTo(teamRank(b.team));
        if (teamOrder != 0) return teamOrder;
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
    // 防御：上一间房的监听 / onDisconnect 还没清理就再次加入
    if (joined || _playersSub != null) {
      await leave();
    }

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
    status = result.status ?? Cfg.roomStatusLobby;
    myHp = Cfg.maxHp;
    iAmDead = false;
    _primed = false;
    _leftRoom = false;
    _clearLocalCombatState();

    hostId = (await _service.fetchHostId(room)) ?? '';

    final generation = ++_roomGeneration;
    _playersSub = _service.watchPlayers(room).listen((next) {
      if (generation != _roomGeneration) return;
      _onPlayersSnapshot(next);
    }, onError: (Object e) {
      debugPrint('players 监听异常: $e');
    });
    _feedSub = _service.watchFeed(room).listen((items) {
      if (generation != _roomGeneration) return;
      feed = items;
      _safeNotify();
    }, onError: (Object e) {
      debugPrint('feed 监听异常: $e');
    });
    _statusSub = _service.watchStatus(room).listen((next) {
      if (generation != _roomGeneration) return;
      if (next != status) {
        status = next;
        _safeNotify();
      }
    }, onError: (Object e) {
      debugPrint('status 监听异常: $e');
    });

    loading = false;
    _safeNotify();
    return true;
  }

  Future<void> leave() async {
    _leftRoom = true;
    _roomGeneration++;
    await _playersSub?.cancel();
    await _feedSub?.cancel();
    await _statusSub?.cancel();
    _playersSub = null;
    _feedSub = null;
    _statusSub = null;

    _clearLocalCombatState();

    if (roomId.isNotEmpty && playerId.isNotEmpty) {
      await _service.leave(roomId, playerId);
    }
    players = <String, Player>{};
    feed = <FeedItem>[];
    roomId = '';
    playerId = '';
    hostId = '';
    status = Cfg.roomStatusLobby;
    myHp = Cfg.maxHp;
    iAmDead = false;
    _safeNotify();
  }

  // ------------------------------------------------------------------
  // 小队 / 开始对战（备战大厅）
  // ------------------------------------------------------------------

  /// 选队：先本地乐观更新给即时反馈，数据库失败时回滚。
  Future<bool> selectTeam(Team team) async {
    final prev = players[playerId];
    if (prev == null) {
      toast('你已不在房间');
      return false;
    }
    if (prev.team == team) return true;

    players = Map<String, Player>.from(players)
      ..[playerId] = prev.withTeam(team);
    _safeNotify();

    final result = await _service.selectTeam(
      roomId: roomId,
      playerId: playerId,
      team: team,
    );
    if (!result.ok) {
      // 只有还在展示乐观值时回滚，避免覆盖已经到达的新快照
      if (players[playerId]?.team == team) {
        players = Map<String, Player>.from(players)..[playerId] = prev;
        _safeNotify();
      }
      toast(result.reason ?? '加入小队失败');
      return false;
    }
    return true;
  }

  Future<bool> autoAssignTeam() async {
    final result = await _service.autoAssignTeam(
      roomId: roomId,
      playerId: playerId,
    );
    if (!result.ok) {
      toast(result.reason ?? '自动分配失败');
      return false;
    }
    final picked = result.team;
    final mine = players[playerId];
    if (picked != null && mine != null) {
      players = Map<String, Player>.from(players)
        ..[playerId] = mine.withTeam(picked);
      _safeNotify();
    }
    return true;
  }

  Future<bool> startGame() async {
    if (!isHost) {
      toast('只有房主能开始对战');
      return false;
    }
    final error = await _service.startGame(roomId: roomId, hostId: playerId);
    if (error != null) {
      toast(error);
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------------
  // 核心：玩家快照 → 本地阵亡 / 复活 / 护盾状态
  // ------------------------------------------------------------------

  void _onPlayersSnapshot(Map<String, Player> next) {
    final prevHp = myHp;
    final wasDead = iAmDead;
    final mine = next[playerId];

    if (mine != null) {
      final drop = prevHp - mine.hp;

      // 掉血 → 通知 UI 播震动/红光/音效
      // _primed 用来跳过"刚进房的第一帧"，避免把初始值当掉血
      if (_primed && drop > 0 && prevHp > 0) {
        _damageCtrl.add(drop);
      }

      myHp = mine.hp;
      final deadNow = !mine.isAlive;

      if (deadNow) {
        iAmDead = true;
        // deathAt 变了 = 新的死亡批次，旧 Timer 必须作废
        if (!wasDead || _deadBatchDeathAt != mine.deathAt) {
          _startDeathBatch(mine.deathAt);
        }
      } else {
        iAmDead = false;
        _deadBatchDeathAt = null;
        _respawnAtServerMs = 0;
        _respawning = false;
        _respawnRetryAtMs = 0;
        if (respawnRemainingMs.value != 0) {
          respawnRemainingMs.value = 0;
        }
      }

      // 时间戳远超正常保护窗口时视为时钟异常，不显示护盾、也不让它
      // 永远占着本地 ticker（与 CombatRules / Player.isInvincibleAt 一致）。
      final rawUntil = mine.invincibleUntil ?? 0;
      _invincibleUntilMs =
          rawUntil > serverNowMs + Cfg.maxInvincibleSkewMs ? 0 : rawUntil;
      _syncCountdownTicker();
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

  void _startDeathBatch(int? deathAt) {
    // 批次校验仍用数据库里的原始 deathAt（旧 Timer 必须精确匹配），
    // 但倒计时起点对「明显超前的异常时间戳」做兜底，避免复活被无限推迟。
    _deadBatchDeathAt = deathAt;
    final now = serverNowMs;
    final base = (deathAt == null || deathAt > now + Cfg.maxInvincibleSkewMs)
        ? now
        : deathAt;
    _respawnAtServerMs = base + Cfg.respawnDelay.inMilliseconds;
    _respawning = false;
    _respawnRetryAtMs = 0;
    _syncCountdownTicker();
  }

  void _syncCountdownTicker() {
    if (_disposed) return;
    final now = serverNowMs;
    final needsTick = iAmDead || _invincibleUntilMs > now;

    if (!needsTick) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
      if (respawnRemainingMs.value != 0) respawnRemainingMs.value = 0;
      if (invincibleRemainingMs.value != 0) invincibleRemainingMs.value = 0;
      return;
    }

    _updateCountdownValues();
    _countdownTicker ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _onCountdownTick(),
    );
  }

  void _updateCountdownValues() {
    final now = serverNowMs;

    if (iAmDead) {
      final remaining = _respawnAtServerMs > now ? _respawnAtServerMs - now : 0;
      if (respawnRemainingMs.value != remaining) {
        respawnRemainingMs.value = remaining;
      }
    }

    final shield = _invincibleUntilMs > now ? _invincibleUntilMs - now : 0;
    if (invincibleRemainingMs.value != shield) {
      invincibleRemainingMs.value = shield;
    }
  }

  void _onCountdownTick() {
    if (_disposed) return;
    _updateCountdownValues();

    if (iAmDead &&
        respawnRemainingMs.value <= 0 &&
        !_respawning &&
        serverNowMs >= _respawnRetryAtMs) {
      unawaited(_attemptRespawn());
    }

    if (!iAmDead && _invincibleUntilMs <= serverNowMs) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
      if (invincibleRemainingMs.value != 0) {
        invincibleRemainingMs.value = 0;
      }
    }
  }

  Future<void> _attemptRespawn() async {
    if (_disposed || _respawning || !iAmDead || _leftRoom) return;
    final room = roomId;
    final pid = playerId;
    if (room.isEmpty || pid.isEmpty) return;

    final expected = _deadBatchDeathAt;
    _respawning = true;

    final result = await _service.respawn(
      roomId: room,
      playerId: pid,
      expectedDeathAt: expected,
    );
    _respawning = false;
    if (_disposed) return;

    // 已离开 / 已换房：事务若在删除之后才落地，再删一次，避免幽灵玩家
    if (_leftRoom || room != roomId || pid != playerId) {
      if (_leftRoom || pid != playerId) {
        unawaited(_service.leave(room, pid));
      }
      return;
    }

    if (!result.ok) {
      // 批次失效（被重置 / 已复活 / 又死了一次）交给快照校正；
      // 网络失败则 1 秒后再试，避免每 100ms 打一次数据库。
      _respawnRetryAtMs = serverNowMs + (result.batchMismatch ? 2000 : 1000);
    } else {
      // 等快照回来期间不要重复提交
      _respawnRetryAtMs = serverNowMs + 2000;
    }
  }

  // ------------------------------------------------------------------
  // 开火 → 权威伤害事务
  // ------------------------------------------------------------------

  /// 确认击中某个玩家。返回结构化结果，由 UI 决定提示方式。
  Future<CombatDecision> confirmHit(String targetId) async {
    final targetName = players[targetId]?.name ?? '对手';
    final result = await _service.applyCombatDamage(
      roomId: roomId,
      attackerId: playerId,
      targetId: targetId,
    );

    if (result.outcome == CombatOutcome.applied) {
      unawaited(_service.pushFeed(
        roomId,
        '$nickname 命中 $targetName -${Cfg.damagePerHit}',
      ));
    } else if (result.outcome == CombatOutcome.killed) {
      unawaited(_service.pushFeed(roomId, '$nickname 击倒了 $targetName'));
    }
    return result;
  }

  // ------------------------------------------------------------------
  // 房主：重开一局
  // ------------------------------------------------------------------

  Future<bool> resetGame() async {
    if (!isHost) {
      toast('只有房主能重开');
      return false;
    }

    final error = await _service.resetGame(roomId: roomId, hostId: playerId);
    if (error != null) {
      toast(error);
      return false;
    }

    // 本地立即清理倒计时/护盾/阵亡状态，数据库快照随后对齐
    _clearLocalCombatState();
    iAmDead = false;
    myHp = Cfg.maxHp;

    // 重开后战报已由 resetGame 事务清空，这里不再追加任何提示，
    // 避免 UI 显示“已清空战报”却马上又出现一条旧模式文案。
    return true;
  }

  void _clearLocalCombatState() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _deadBatchDeathAt = null;
    _respawnAtServerMs = 0;
    _invincibleUntilMs = 0;
    _respawning = false;
    _respawnRetryAtMs = 0;
    if (respawnRemainingMs.value != 0) respawnRemainingMs.value = 0;
    if (invincibleRemainingMs.value != 0) invincibleRemainingMs.value = 0;
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
    _statusSub?.cancel();
    _countdownTicker?.cancel();
    unawaited(_service.dispose());
    respawnRemainingMs.dispose();
    invincibleRemainingMs.dispose();
    _damageCtrl.close();
    _toastCtrl.close();
    super.dispose();
  }
}
