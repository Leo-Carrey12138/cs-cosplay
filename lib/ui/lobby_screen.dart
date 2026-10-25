import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../state/game_session.dart';
import 'game_screen.dart';
import 'team_style.dart';

/// 战术终端风配色（与战场保持一致）。
const Color _kLobbyBg = Color(0xFF0B0F12);
const Color _kLobbyAccent = Color(0xFF00E676);

/// 备战大厅：选队 / 自动分配 / 房主开始对战。
///
/// 房间 status 变为 playing 后，所有客户端由监听自动 pushReplacement 进战场；
/// 这样从战场离开时 pop 会直接回到 JoinScreen，而不是空掉的大厅。
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final GameSession _session;
  StreamSubscription<String>? _toastSub;

  bool _navigating = false;
  bool _starting = false;
  bool _leaving = false;
  bool _autoAssigning = false;

  @override
  void initState() {
    super.initState();
    _session = context.read<GameSession>();
    _session.addListener(_onSessionChanged);
    _toastSub = _session.onToast.listen(_showSnack);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionChanged());
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _toastSub?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // 正在离开时即使 status 刚好变成 playing，也不能把用户带进战场
    if (_leaving) return;
    if (_session.status != Cfg.roomStatusPlaying || !_session.joined) return;
    if (_navigating) return;

    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_session.joined) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xE6151B21),
        ),
      );
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _session.leave();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _chooseTeam(Team team) async {
    // GameSession 会先乐观更新，点击立即有视觉反馈；失败时自动回滚并 toast。
    await _session.selectTeam(team);
  }

  Future<void> _autoAssign() async {
    if (_autoAssigning) return;
    setState(() => _autoAssigning = true);
    await _session.autoAssignTeam();
    if (!mounted) return;
    setState(() => _autoAssigning = false);
  }

  Future<void> _start() async {
    if (_starting) return;
    if (!_session.allPlayersAssigned) {
      _showSnack('还有玩家未选择小队');
      return;
    }
    setState(() => _starting = true);
    await _session.startGame();
    if (!mounted) return;
    // 成功时 status 监听会负责跳转；失败则恢复按钮让房主重试
    setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameSession>();
    final alpha = session.teamPlayers(Team.alpha);
    final bravo = session.teamPlayers(Team.bravo);
    final unassigned =
        session.players.values.where((p) => p.team == null).length;
    final canStart = session.isHost &&
        session.players.isNotEmpty &&
        session.allPlayersAssigned;
    final imbalanced =
        alpha.isNotEmpty && bravo.isNotEmpty && alpha.length != bravo.length;

    return PopScope<void>(
      // 系统返回键也要先退出房间，避免留下幽灵玩家
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leave();
      },
      child: Scaffold(
        backgroundColor: _kLobbyBg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(session),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        '选择你的小队',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '每队最多 ${Cfg.teamCapacity} 人 · 进入战场后不能换队',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 14),
                      _TeamCard(
                        team: Team.alpha,
                        members: alpha,
                        myId: session.playerId,
                        hostId: session.hostId,
                        selected: session.myTeam == Team.alpha,
                        onTap: () => _chooseTeam(Team.alpha),
                      ),
                      const SizedBox(height: 12),
                      _TeamCard(
                        team: Team.bravo,
                        members: bravo,
                        myId: session.playerId,
                        hostId: session.hostId,
                        selected: session.myTeam == Team.bravo,
                        onTap: () => _chooseTeam(Team.bravo),
                      ),
                      const SizedBox(height: 14),
                      if (unassigned > 0)
                        _HintText(
                          icon: Icons.person_search,
                          color: const Color(0xFFFFC107),
                          text: '还有 $unassigned 名玩家未选择小队，'
                              '全部选好后房主才能开始',
                        )
                      else if (alpha.isEmpty || bravo.isEmpty)
                        const _HintText(
                          icon: Icons.balance,
                          color: Color(0xFF40C4FF),
                          text: '目前只有一队有人，仍可开始（方便单人调试）',
                        )
                      else if (imbalanced)
                        const _HintText(
                          icon: Icons.balance,
                          color: Color(0xFF40C4FF),
                          text: '两队人数不一致，仍可开始（方便单人调试）',
                        )
                      else if (session.players.isNotEmpty)
                        const _HintText(
                          icon: Icons.check_circle_outline,
                          color: _kLobbyAccent,
                          text: '所有玩家已就位',
                        ),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(session, canStart: canStart),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(GameSession session) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.meeting_room_outlined,
              size: 20, color: _kLobbyAccent),
          const SizedBox(width: 8),
          Text(
            '房间 ${session.roomId}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${session.players.length}/${Cfg.maxPlayers}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _leaving ? null : _leave,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              minimumSize: const Size(64, 48),
            ),
            icon: _leaving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout, size: 17),
            label: const Text('离开', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(GameSession session, {required bool canStart}) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E1418),
        border: Border(
          top: BorderSide(color: Color(0x3300E676)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _autoAssigning ? null : _autoAssign,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _autoAssigning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shuffle, size: 18),
              label: Text(
                _autoAssigning ? '正在分配…' : '自动分配',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  session.isHost && canStart && !_starting ? _start : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kLobbyAccent,
                foregroundColor: const Color(0xFF04150B),
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white38,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _starting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF04150B),
                      ),
                    )
                  : Icon(
                      session.isHost ? Icons.play_arrow : Icons.hourglass_top,
                      size: 21),
              label: Text(
                session.isHost ? (_starting ? '正在开始…' : '开始对战') : '等待房主开始',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.members,
    required this.myId,
    required this.hostId,
    required this.selected,
    required this.onTap,
  });

  final Team team;
  final List<Player> members;
  final String myId;
  final String hostId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = TeamStyle.colorOf(team);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? TeamStyle.tintOf(team) : const Color(0xCC10161B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? color : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.7)),
                      ),
                      child: Text(
                        TeamStyle.initialOf(team),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      team.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${members.length}/${Cfg.teamCapacity}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: selected
                          ? Icon(
                              Icons.check_circle,
                              key: const ValueKey<String>('selected'),
                              color: color,
                              size: 22,
                            )
                          : const Icon(
                              Icons.radio_button_unchecked,
                              key: ValueKey<String>('unselected'),
                              color: Colors.white38,
                              size: 22,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < Cfg.teamCapacity; i++)
                  i < members.length
                      ? _MemberRow(
                          player: members[i],
                          color: color,
                          isMe: members[i].id == myId,
                          isHost: members[i].id == hostId,
                        )
                      : const _EmptySlotRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.player,
    required this.color,
    required this.isMe,
    required this.isHost,
  });

  final Player player;
  final Color color;
  final bool isMe;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          Icon(Icons.person, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isHost) const _Tag(text: '房主', color: Color(0xFFFFC107)),
          if (isHost && isMe) const SizedBox(width: 4),
          if (isMe) const _Tag(text: '你', color: _kLobbyAccent),
        ],
      ),
    );
  }
}

class _EmptySlotRow extends StatelessWidget {
  const _EmptySlotRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: Row(
        children: <Widget>[
          Icon(Icons.person_outline, size: 15, color: Colors.white24),
          SizedBox(width: 7),
          Text(
            '等待玩家',
            style: TextStyle(fontSize: 12.5, color: Colors.white30),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
