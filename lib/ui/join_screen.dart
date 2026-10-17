import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/game_session.dart';
import 'game_screen.dart';

/// 进入页：昵称 + 4 位房间号 → 加入（房间不存在会自动创建）
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final TextEditingController _nameCtrl = TextEditingController(
    text: '玩家${math.Random().nextInt(900) + 100}',
  );
  final TextEditingController _roomCtrl = TextEditingController(
    text: (math.Random().nextInt(9000) + 1000).toString(),
  );
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final room = _roomCtrl.text.trim();

    if (name.isEmpty) {
      _showError('请输入昵称');
      return;
    }
    if (room.length != 4 || int.tryParse(room) == null) {
      _showError('房间号必须是 4 位数字');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final session = context.read<GameSession>();
    final ok = await session.join(room: room, name: name);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      // 用 push 而不是 pushReplacement：这样战场上点"离开房间"能 pop 回本页。
      // 如果用 pushReplacement，GameScreen 就是栈底，pop 之后就只剩黑屏了。
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );
    } else {
      _showError(session.errorMessage ?? '加入失败，检查网络与 Firebase 配置');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(Icons.center_focus_strong,
                    size: 72, color: Color(0xFF00E676)),
                const SizedBox(height: 12),
                const Text(
                  '真人 CS · 局域网无外设对战',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '摄像头 + 本地 AI 识别 + 实时房间 · 单房最多 ${Cfg.maxPlayers} 人',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 10,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    counterText: '',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _roomCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _join(),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    labelText: '房间号（4 位数字）',
                    counterText: '',
                    prefixIcon: const Icon(Icons.meeting_room_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '随机房号',
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: () => setState(() {
                        _roomCtrl.text =
                            (math.Random().nextInt(9000) + 1000).toString();
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _join,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _submitting ? '正在进入房间…' : '加入战斗',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const _RulesCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('玩法：用摄像头对准对手，准星落在绿色人形框内 → 开火 → 选择你打到的人。',
              style: style),
          Text('· 每次命中 -${Cfg.damagePerHit} HP，冷却 1 秒', style: style),
          Text('· 目标太小（< 屏幕 3%）判定为超出射程', style: style),
          Text('· 血量由服务端事务扣减，本地改不了分', style: style),
        ],
      ),
    );
  }
}
