import 'package:cs_cosplay/models/feed_item.dart';
import 'package:cs_cosplay/models/player.dart';
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
        const SizedBox(
          height: 80,
          child: PlayerHpList(players: _players, myId: 'a'),
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
          ),
        ),
      ),
    );

    expect(find.text('1234'), findsOneWidget);
    await tester.tap(find.text('重置游戏'));
    expect(resets, 1);
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

  testWidgets('阵亡页显示排名并可离开房间', (WidgetTester tester) async {
    var left = 0;
    await tester.pumpWidget(
      _host(
        DeathOverlay(
          rank: 2,
          totalPlayers: 6,
          aliveCount: 3,
          onLeave: () => left++,
        ),
      ),
    );

    expect(find.text('你已阵亡'), findsOneWidget);
    expect(find.text('第 2 名'), findsOneWidget);
    expect(find.textContaining('还有 3 人存活'), findsOneWidget);

    await tester.tap(find.text('离开房间'));
    expect(left, 1);
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
}
