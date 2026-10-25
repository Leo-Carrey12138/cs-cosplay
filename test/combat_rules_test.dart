import 'package:cs_cosplay/app_config.dart';
import 'package:cs_cosplay/models/team.dart';
import 'package:cs_cosplay/services/combat_rules.dart';
import 'package:flutter_test/flutter_test.dart';

CombatDecision evaluate({
  bool attackerExists = true,
  bool attackerDead = false,
  Team? attackerTeam = Team.alpha,
  bool targetExists = true,
  bool targetDead = false,
  int targetHp = Cfg.maxHp,
  Team? targetTeam = Team.bravo,
  int invincibleUntil = 0,
  int serverNow = 1000000,
  bool isSelf = false,
  int amount = Cfg.damagePerHit,
}) {
  return CombatRules.evaluate(
    attackerExists: attackerExists,
    attackerDead: attackerDead,
    attackerTeam: attackerTeam,
    targetExists: targetExists,
    targetHp: targetHp,
    targetDead: targetDead,
    targetTeam: targetTeam,
    targetInvincibleUntil: invincibleUntil,
    serverNow: serverNow,
    isSelf: isSelf,
    amount: amount,
  );
}

void main() {
  group('CombatRules.evaluate', () {
    test('敌方普通命中：只扣血，不产生击杀', () {
      final decision = evaluate(targetHp: Cfg.maxHp);

      expect(decision.outcome, CombatOutcome.applied);
      expect(decision.hpAfter, Cfg.maxHp - Cfg.damagePerHit);
      expect(decision.killAwarded, isFalse);
      expect(decision.committed, isTrue);
    });

    test('敌方致命命中：目标阵亡，攻击者 +1 击杀', () {
      final decision = evaluate(targetHp: Cfg.damagePerHit);

      expect(decision.outcome, CombatOutcome.killed);
      expect(decision.hpAfter, 0);
      expect(decision.killAwarded, isTrue);
    });

    test('同一次死亡事件重复伤害：不会再次计分', () {
      final first = evaluate(targetHp: Cfg.damagePerHit);
      var kills = 0;
      if (first.killAwarded) kills++;

      // 第二次请求时目标已经是 hp=0 / isDead=true 的状态
      final second = evaluate(
        targetHp: first.hpAfter,
        targetDead: true,
      );
      if (second.killAwarded) kills++;

      expect(second.outcome, CombatOutcome.targetUnavailable);
      expect(second.killAwarded, isFalse);
      expect(kills, 1);
    });

    test('100 HP 在 25 伤害下四枪击倒：前三枪存活，第四枪计分', () {
      var hp = Cfg.maxHp;
      for (var i = 0; i < 3; i++) {
        final hit = evaluate(targetHp: hp);
        expect(hit.outcome, CombatOutcome.applied);
        expect(hit.killAwarded, isFalse);
        hp = hit.hpAfter;
      }
      expect(hp, Cfg.maxHp - Cfg.damagePerHit * 3);

      final finalHit = evaluate(targetHp: hp);
      expect(finalHit.outcome, CombatOutcome.killed);
      expect(finalHit.hpAfter, 0);
      expect(finalHit.killAwarded, isTrue);
    });

    test('同队目标：血量与击杀都不变', () {
      final decision = evaluate(
        attackerTeam: Team.alpha,
        targetTeam: Team.alpha,
        targetHp: 60,
      );

      expect(decision.outcome, CombatOutcome.friendlyBlocked);
      expect(decision.hpAfter, 60);
      expect(decision.killAwarded, isFalse);
      expect(decision.committed, isFalse);
    });

    test('自己攻击自己：被拒绝', () {
      final decision = evaluate(isSelf: true);

      expect(decision.outcome, CombatOutcome.selfBlocked);
      expect(decision.killAwarded, isFalse);
    });

    test('invincibleUntil 大于 serverNow：伤害被拦截', () {
      const now = 1000000;
      final decision = evaluate(
        serverNow: now,
        invincibleUntil: now + 1500,
        targetHp: 80,
      );

      expect(decision.outcome, CombatOutcome.invincibleBlocked);
      expect(decision.hpAfter, 80);
      expect(decision.killAwarded, isFalse);
    });

    test('保护期刚好结束（until == now）：可以正常扣血', () {
      const now = 1000000;
      final decision = evaluate(
        serverNow: now,
        invincibleUntil: now,
        targetHp: 80,
      );

      expect(decision.outcome, CombatOutcome.applied);
      expect(decision.hpAfter, 80 - Cfg.damagePerHit);
    });

    test('已阵亡目标：不能再次扣血或计分', () {
      final decision = evaluate(targetDead: true, targetHp: 0);

      expect(decision.outcome, CombatOutcome.targetUnavailable);
      expect(decision.killAwarded, isFalse);
    });

    test('已阵亡攻击者：不能造成伤害', () {
      final decision = evaluate(attackerDead: true);

      expect(decision.outcome, CombatOutcome.attackerUnavailable);
      expect(decision.killAwarded, isFalse);
    });

    test('目标/攻击者不存在：拒绝', () {
      expect(
        evaluate(targetExists: false).outcome,
        CombatOutcome.targetUnavailable,
      );
      expect(
        evaluate(attackerExists: false).outcome,
        CombatOutcome.attackerUnavailable,
      );
    });

    test('时间戳远超正常保护窗口：视为时钟异常，不永久无敌', () {
      final decision = evaluate(
        serverNow: 1000000,
        invincibleUntil: 1000000 + Cfg.maxInvincibleSkewMs + 1,
      );

      expect(decision.outcome, CombatOutcome.applied);
    });
  });

  group('CombatRules.resetPlayer', () {
    test('重开后击杀清零、队伍保留、保护/死亡状态清空', () {
      final before = <String, Object?>{
        'name': '阿明',
        'team': 'alpha',
        'hp': 10,
        'isDead': true,
        'deathAt': 12345,
        'invincibleUntil': 99999,
        'kills': 4,
        'joinedAt': 777,
      };

      final after = CombatRules.resetPlayer(before);

      expect(after['name'], '阿明');
      expect(after['team'], 'alpha');
      expect(after['joinedAt'], 777);
      expect(after['hp'], Cfg.maxHp);
      expect(after['isDead'], isFalse);
      expect(after['deathAt'], isNull);
      expect(after['invincibleUntil'], 0);
      expect(after['kills'], 0);
      // 不修改传入的原始 map
      expect(before['kills'], 4);
    });
  });

  group('RespawnGuard', () {
    test('同一次死亡批次可以复活', () {
      expect(
        RespawnGuard.canRespawn(
          isDead: true,
          currentDeathAt: 1000,
          expectedDeathAt: 1000,
        ),
        isTrue,
      );
    });

    test('旧复活任务不能复活新的死亡批次', () {
      expect(
        RespawnGuard.canRespawn(
          isDead: true,
          currentDeathAt: 2000,
          expectedDeathAt: 1000,
        ),
        isFalse,
      );
    });

    test('已经复活（isDead=false）时旧任务写入被拒绝', () {
      expect(
        RespawnGuard.canRespawn(
          isDead: false,
          currentDeathAt: 1000,
          expectedDeathAt: 1000,
        ),
        isFalse,
      );
    });

    test('旧数据的 deathAt 为 null 时按 null 批次匹配', () {
      expect(
        RespawnGuard.canRespawn(
          isDead: true,
          currentDeathAt: null,
          expectedDeathAt: null,
        ),
        isTrue,
      );
    });

    test('倒计时按 deathAt + delay 计算，过期后为 0', () {
      expect(
        RespawnGuard.remainingMs(
          deathAt: 1000,
          serverNow: 3000,
          delayMs: 5000,
        ),
        3000,
      );
      expect(
        RespawnGuard.remainingMs(
          deathAt: 1000,
          serverNow: 7000,
          delayMs: 5000,
        ),
        0,
      );
    });
  });
}
