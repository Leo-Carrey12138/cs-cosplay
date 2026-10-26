import 'package:cs_cosplay/app_config.dart';
import 'package:cs_cosplay/models/feed_item.dart';
import 'package:cs_cosplay/models/player.dart';
import 'package:cs_cosplay/models/team.dart';
import 'package:cs_cosplay/ui/theme/csgo_theme.dart';
import 'package:cs_cosplay/ui/widgets/death_overlay.dart';
import 'package:cs_cosplay/ui/widgets/fire_button.dart';
import 'package:cs_cosplay/ui/widgets/kill_feed.dart';
import 'package:cs_cosplay/ui/widgets/player_hp_list.dart';
import 'package:cs_cosplay/ui/widgets/target_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCsgoTheme(),
      home: Scaffold(body: child),
    );

const List<Player> _players = <Player>[
  Player(id: 'a', name: 'Alpha', hp: 100, isDead: false, joinedAt: 1),
  Player(id: 'b', name: 'Bravo', hp: 40, isDead: false, joinedAt: 2),
  Player(id: 'c', name: 'Charlie', hp: 0, isDead: true, joinedAt: 3),
];

void main() {
  testWidgets('血条列表显示名字、血量和阵亡状态', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 80,
          child: PlayerHpList(
            players: _players,
            myId: 'a',
            serverNow: () => 1000,
          ),
        ),
      ),
    );

    expect(find.text('Alpha · 我'), findsOneWidget);
    expect(find.text('100 HP'), findsOneWidget);
    expect(find.text('40 HP'), findsOneWidget);
    expect(find.text('阵亡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('房间头显示房号并触发房主重开', (WidgetTester tester) async {
    var resets = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: RoomHeader(
            roomId: '1234',
            playerCount: 2,
            isHost: true,
            onReset: () => resets++,
            alphaScore: 3,
            bravoScore: 1,
          ),
        ),
      ),
    );

    expect(find.text('ROOM 1234 · 2/${Cfg.maxPlayers}'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('重置游戏'));
    expect(resets, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('房间头在窄屏下不溢出', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: RoomHeader(
            roomId: '1234',
            playerCount: 6,
            isHost: true,
            onReset: () {},
            alphaScore: 12,
            bravoScore: 9,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('战报最多显示最近 3 条', (WidgetTester tester) async {
    const List<FeedItem> items = <FeedItem>[
      FeedItem(id: '1', text: 'A 命中 B -20', ts: 4),
      FeedItem(id: '2', text: 'B 命中 C -20', ts: 3),
      FeedItem(id: '3', text: 'C 命中 A -20', ts: 2),
      FeedItem(id: '4', text: 'D 命中 E -20', ts: 1),
    ];

    await tester.pumpWidget(_host(const KillFeed(items: items)));

    expect(find.text('A 命中 B -20'), findsOneWidget);
    expect(find.text('B 命中 C -20'), findsOneWidget);
    expect(find.text('C 命中 A -20'), findsOneWidget);
    expect(find.text('D 命中 E -20'), findsNothing);
  });

  testWidgets('开火按钮就绪时可点，冷却时禁用', (WidgetTester tester) async {
    var taps = 0;

    await tester.pumpWidget(
      _host(
        Center(
          child: FireButton(
            onPressed: () => taps++,
            cooling: false,
            cooldownProgress: 0,
          ),
        ),
      ),
    );
    expect(find.text('开火'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(taps, 1);

    await tester.pumpWidget(
      _host(
        Center(
          child: FireButton(
            onPressed: () => taps++,
            cooling: true,
            cooldownProgress: 0.5,
          ),
        ),
      ),
    );
    expect(find.text('冷却'), findsOneWidget);
    expect(find.text('RELOAD'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(taps, 1);
  });

  testWidgets('阵亡页显示自动复活倒计时和复活保护并可离开房间',
      (WidgetTester tester) async {
    var left = 0;
    await tester.pumpWidget(
      _host(
        DeathOverlay(
          remainingMs: 3000,
          totalMs: 5000,
          onLeave: () => left++,
        ),
      ),
    );

    expect(find.text('你已阵亡'), findsOneWidget);
    expect(find.text('3 秒后重新部署'), findsOneWidget);
    expect(
      find.text('复活后满血，并获得 ${Cfg.respawnInvincible.inSeconds} 秒保护'),
      findsOneWidget,
    );

    await tester.tap(find.text('离开房间'));
    expect(left, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('血条列表保留队伍颜色、击杀数与复活保护状态',
      (WidgetTester tester) async {
    const int now = 2000;
    const List<Player> players = <Player>[
      Player(
        id: 'a',
        name: 'Alpha',
        hp: 100,
        isDead: false,
        joinedAt: 1,
        team: Team.alpha,
        kills: 3,
        invincibleUntil: 5000,
      ),
      Player(
        id: 'b',
        name: 'Bravo',
        hp: 50,
        isDead: false,
        joinedAt: 2,
        team: Team.bravo,
        kills: 1,
      ),
      Player(
        id: 'c',
        name: 'Charlie',
        hp: 0,
        isDead: true,
        joinedAt: 3,
        team: Team.alpha,
        deathAt: 1000,
      ),
    ];

    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 80,
          child: PlayerHpList(
            players: players,
            myId: 'a',
            serverNow: () => now,
          ),
        ),
      ),
    );

    expect(find.text('Alpha · 我'), findsOneWidget);
    expect(find.text('K 3'), findsOneWidget);
    expect(find.text('保护 3.0s'), findsOneWidget);
    expect(find.text('K 1'), findsOneWidget);
    // deathAt(1000) + 5000 - now(2000) = 4000ms → 显示 4s
    expect(find.text('重生 4s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('命中选人弹窗可以选择目标', (WidgetTester tester) async {
    Player? chosen;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCsgoTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  chosen = await showTargetPicker(
                    context,
                    candidates: _players
                        .where((Player p) => p.isAlive && p.id != 'a')
                        .toList(),
                    hitPercent: 4.2,
                    serverNowMs: 1000,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('命中！你打到了谁？'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    await tester.tap(find.text('Bravo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(chosen?.id, 'b');
  });

  testWidgets('命中选人弹窗保留队伍颜色、击杀数与复活保护状态',
      (WidgetTester tester) async {
    const List<Player> candidates = <Player>[
      Player(
        id: 'b',
        name: 'Bravo',
        hp: 50,
        isDead: false,
        team: Team.bravo,
        kills: 2,
        invincibleUntil: 5000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCsgoTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTargetPicker(
                  context,
                  candidates: candidates,
                  hitPercent: 3.5,
                  serverNowMs: 2000,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('B'), findsOneWidget);
    expect(find.textContaining('BRAVO'), findsOneWidget);
    expect(find.textContaining('2 击杀'), findsOneWidget);
    expect(find.text('50 HP'), findsOneWidget);
    expect(find.text('复活保护'), findsOneWidget);

    await tester.tap(find.text('算了 / 没打中'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('命中选人弹窗 5 秒无操作自动取消', (WidgetTester tester) async {
    Player? chosen;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCsgoTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  chosen = await showTargetPicker(
                    context,
                    candidates: <Player>[
                      const Player(
                        id: 'b',
                        name: 'Bravo',
                        hp: 100,
                        isDead: false,
                      ),
                    ],
                    hitPercent: 3.5,
                    serverNowMs: 1000,
                  );
                  completed = true;
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('命中！你打到了谁？'), findsOneWidget);

    await tester.pump(Cfg.pickerTimeout);
    await tester.pump(const Duration(milliseconds: 400));

    expect(completed, isTrue);
    expect(chosen, isNull);
    expect(find.text('命中！你打到了谁？'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
