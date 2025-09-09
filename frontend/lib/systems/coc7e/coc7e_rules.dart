import '../core/rules_engine.dart';
import '../core/dice.dart';

class Coc7eRules implements TrpgRules {
  @override
  String get systemId => 'coc7e';

  // 초기값(평균 50), skills는 빈 맵으로 시작
  @override
  Map<String, dynamic> initialData() => {
    '근력': 50,
    '건강': 50,
    '크기': 50,
    '민첩': 50,
    '외모': 50,
    '지능': 50,
    '교육': 50,
    '정신력': 50, // POW
    '행운': 50,
    'skills': {},
  };

  int _asInt(dynamic v, {int orElse = 0}) {
    if (v is int) return v;
    if (v is double) return v.floor();
    if (v is String) return int.tryParse(v) ?? orElse;
    return orElse;
  }

  int _clamp100(int v) => v.clamp(1, 99);

  // 이동력(MOV) 계산: CoC 7판 기본 규칙 (나이 보정 제외)
  int _calcMov(int str, int dex, int siz) {
    if (str > siz && dex > siz) return 9;
    if (str >= siz || dex >= siz) return 8;
    return 7;
  }

  // 대미지 보너스/빌드: CoC 7판 표를 간단 매핑 (STR+SIZ)
  Map<String, dynamic> _calcDbBuild(int str, int siz) {
    final sum = str + siz;
    if (sum <= 64) return {'DB': '-2', 'Build': -2};
    if (sum <= 84) return {'DB': '-1', 'Build': -1};
    if (sum <= 124) return {'DB': '0', 'Build': 0};
    if (sum <= 164) return {'DB': '+1d4', 'Build': 1};
    if (sum <= 204) return {'DB': '+1d6', 'Build': 2};
    return {'DB': '+2d6', 'Build': 3};
  }

  @override
  Map<String, dynamic> derive(Map<String, dynamic> d) {
    // 기존 데이터 구조가 평면(한국어 키)라고 가정하되, 혹시 nested가 들어와도 케어
    final src = {...d};

    final str = _asInt(src['근력']);
    final con = _asInt(src['건강']);
    final siz = _asInt(src['크기']);
    final dex = _asInt(src['민첩']);
    final pow = _asInt(src['정신력']); // POW

    final maxHp = ((con + siz) / 10).floor();
    final maxMp = (pow / 5).floor();
    final san = pow; // 7판 기준: 초기 SAN = POW
    final mov = _calcMov(str, dex, siz);
    final dbb = _calcDbBuild(str, siz);

    return {
      ...d, // 기존 필드 유지
      'maxHp': maxHp,
      'maxMp': maxMp,
      'SAN': san,
      'MOV': mov,
      ...dbb, // DB, Build
    };
  }

  @override
  List<ValidationIssue> validate(Map<String, dynamic> d) {
    final issues = <ValidationIssue>[];

    // 필수 능력치 숫자 검증 (1~99 권장)
    for (final k in const [
      '근력',
      '건강',
      '크기',
      '민첩',
      '외모',
      '지능',
      '교육',
      '정신력',
      '행운',
    ]) {
      final v = d[k];
      final n = _asInt(v, orElse: -9999);
      if (n == -9999) {
        issues.add(ValidationIssue(k, '숫자를 입력하세요.'));
      } else if (n < 1 || n > 99) {
        issues.add(ValidationIssue(k, '값은 1~99 사이를 권장합니다.'));
      }
    }

    // 파생값 일치 검사 (있으면 비교)
    final calc = derive(d);
    if (d.containsKey('maxHp') && _asInt(d['maxHp']) != calc['maxHp']) {
      issues.add(ValidationIssue('maxHp', '계산된 HP와 일치하지 않습니다.'));
    }
    if (d.containsKey('maxMp') && _asInt(d['maxMp']) != calc['maxMp']) {
      issues.add(ValidationIssue('maxMp', '계산된 MP와 일치하지 않습니다.'));
    }
    if (d.containsKey('SAN') && _asInt(d['SAN']) != calc['SAN']) {
      issues.add(ValidationIssue('SAN', '계산된 SAN과 일치하지 않습니다.'));
    }

    return issues;
  }

  RollResult _d100Vs(int target, {String label = 'd100'}) {
    final t = _clamp100(target);
    final r = Dice.roll('d100');
    final success = r.total <= t;
    String level;
    if (r.total <= (t / 5).floor())
      level = 'Extreme';
    else if (r.total <= (t / 2).floor())
      level = 'Hard';
    else
      level = success ? 'Regular' : 'Fail';
    return RollResult(
      detail: '$label: ${r.total} vs $t → $level',
      total: r.total,
      success: success,
    );
  }

  @override
  RollResult rollCheck(String kind, Map<String, dynamic> ctx) {
    // kind: 'skill'|'check'|'stat'|'sanity'|'luck'|'idea'
    switch (kind) {
      case 'skill':
      case 'check':
        {
          final target = _asInt(ctx['target'], orElse: 50);
          return _d100Vs(target, label: 'd100');
        }
      case 'stat':
        {
          // ctx.statName: '근력'|'민첩' ... 와 같은 한국어 키
          final statName = (ctx['statName']?.toString()) ?? '';
          final src =
              ctx['source'] is Map<String, dynamic>
                  ? ctx['source'] as Map<String, dynamic>
                  : ctx;
          final target = _asInt(src[statName], orElse: 50);
          return _d100Vs(target, label: statName);
        }
      case 'sanity':
        {
          // ctx.current: 현재 SAN (없으면 POW 기반 추정)
          final current = _asInt(
            ctx['current'],
            orElse: _asInt(ctx['SAN'], orElse: _asInt(ctx['정신력'], orElse: 50)),
          );
          return _d100Vs(current, label: 'SAN');
        }
      case 'luck':
        {
          final luck = _asInt(
            ctx['luck'],
            orElse: _asInt(ctx['행운'], orElse: 50),
          );
          return _d100Vs(luck, label: '행운');
        }
      case 'idea':
        {
          // Idea = INT 판정
          final intVal = _asInt(
            ctx['지능'],
            orElse: _asInt(ctx['INT'], orElse: 50),
          );
          return _d100Vs(intVal, label: '지능');
        }
      default:
        // 기본은 스킬 판정과 동일하게 처리
        final target = _asInt(ctx['target'], orElse: 50);
        return _d100Vs(target, label: 'd100');
    }
  }
}
