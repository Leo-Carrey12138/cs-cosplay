import 'package:cs_cosplay/app_config.dart';
import 'package:cs_cosplay/models/player.dart';
import 'package:cs_cosplay/models/team.dart';
import 'package:cs_cosplay/services/team_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeamRules.autoPick', () {
    test('加入人数较少的一队', () {
      expect(
        TeamRules.autoPick(alphaCount: 2, bravoCount: 1),
        Team.bravo,
      );
      expect(
        TeamRules.autoPick(alphaCount: 1, bravoCount: 2),
        Team.alpha,
      );
    });

    test('人数相同时选择 ALPHA', () {
      expect(TeamRules.autoPick(alphaCount: 0, bravoCount: 0), Team.alpha);
      expect(TeamRules.autoPick(alphaCount: 2, bravoCount: 2), Team.alpha);
    });
  });

  group('TeamRules.hasRoom', () {
    test('队伍未满 3 人可以加入', () {
      expect(TeamRules.hasRoom(0), isTrue);
      expect(TeamRules.hasRoom(2), isTrue);
    });

    test('队伍满 3 人后拒绝继续加入', () {
      expect(TeamRules.hasRoom(Cfg.teamCapacity), isFalse);
      expect(TeamRules.hasRoom(Cfg.teamCapacity + 1), isFalse);
    });
  });

  group('Player.fromSnapshot 向后兼容', () {
    test('缺少 team / kills / invincibleUntil 时使用安全默认值', () {
      final player = Player.fromSnapshot('p1', <String, Object?>{
        'name': '旧玩家',
        'hp': 40,
        'isDead': false,
      });

      expect(player.team, isNull);
      expect(player.kills, 0);
      expect(player.invincibleUntil, isNull);
      expect(player.hp, 40);
      expect(player.isDead, isFalse);
    });

    test('完全缺失字段也不报错', () {
      final player = Player.fromSnapshot('p2', null);

      expect(player.name, '玩家');
      expect(player.hp, Cfg.maxHp);
      expect(player.isAlive, isTrue);
      expect(player.team, isNull);
      expect(player.kills, 0);
      expect(player.invincibleUntil, isNull);
    });

    test('正确解析 team / kills / invincibleUntil', () {
      final player = Player.fromSnapshot('p3', <String, Object?>{
        'name': '新玩家',
        'team': 'bravo',
        'kills': 3,
        'invincibleUntil': 123456,
        'hp': 100,
        'isDead': false,
      });

      expect(player.team, Team.bravo);
      expect(player.kills, 3);
      expect(player.invincibleUntil, 123456);
      expect(player.isInvincibleAt(123400), isTrue);
      expect(player.isInvincibleAt(123456), isFalse);
    });

    test('非法队伍值和负数击杀被安全处理', () {
      final player = Player.fromSnapshot('p4', <String, Object?>{
        'team': 'charlie',
        'kills': -5,
      });

      expect(player.team, isNull);
      expect(player.kills, 0);
    });

    test('异常超前的无敌时间戳不会造成永久保护', () {
      final player = Player.fromSnapshot('p5', <String, Object?>{
        'hp': 100,
        'invincibleUntil': 1000000 + Cfg.maxInvincibleSkewMs + 1,
      });

      expect(player.isInvincibleAt(1000000), isFalse);
    });
  });
}
