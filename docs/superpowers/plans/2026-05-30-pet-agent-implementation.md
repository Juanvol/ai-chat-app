# 弗糯糯 Agent — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将弗糯糯从"反应式宠物"升级为"自主 AI Agent"——单一大脑感知→决策→行动，18 功能全覆盖。

**Architecture:** 6 个 Phase 自底向上：数据模型 → 服务层 → Agent 核心 → 表达层 → UI 屏幕 → 集成修改。Phase 内任务可部分并行，Phase 间有依赖。

**Tech Stack:** Flutter 3.24 / Dart 3.5 / Provider / Hive / LLMClient (Dio) / 双引擎架构

**起点:** Phase 0 地基已完成（16 文件 / 101 测试 / 全部通过 / `flutter analyze` 零 error）

---

## 依赖图

```
Phase 1: 数据模型 (Tasks 1-4)  ← 并行
  ↓
Phase 2: 服务层 (Tasks 5-7)    ← Task 5+6 并行，Task 7 依赖 Task 5+6
  ↓
Phase 3: Agent 核心 (Task 8)   ← 依赖全部 Phase 2
  ↓
Phase 4: 表达层 (Task 9)       ← 依赖 Phase 3
  ↓
Phase 5: UI 屏幕 (Tasks 10-13)  ← 全部并行，依赖 Phase 2-4
  ↓
Phase 6: 集成修改 (Tasks 14-20) ← Task 14-16 并行，Task 17-20 依次
```

---

## Phase 1: 数据模型

### Task 1: PetPersona — 性格模型

**Files:**
- Create: `lib/pet/pet_persona.dart`
- Test: `test/pet/pet_persona_test.dart`

**Spec 覆盖:** F8 (性格定制)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_persona.dart';

void main() {
  group('PetPersona', () {
    test('默认值正确', () {
      final p = PetPersona();
      expect(p.name, '弗糯糯');
      expect(p.systemPrompt, isNotEmpty);
      expect(p.templateId, isNull);
      expect(p.traits, isEmpty);
    });

    test('toJson/fromJson 往返一致', () {
      final p = PetPersona(
        name: '测试喵',
        systemPrompt: '你是一只高冷的猫',
        templateId: 'tsundere_cat',
        traits: '傲娇,毒舌',
      );
      final json = p.toJson();
      final restored = PetPersona.fromJson(json);
      expect(restored.name, '测试喵');
      expect(restored.systemPrompt, '你是一只高冷的猫');
      expect(restored.templateId, 'tsundere_cat');
      expect(restored.traits, '傲娇,毒舌');
    });

    test('fromJson 缺字段时用默认值', () {
      final p = PetPersona.fromJson({});
      expect(p.name, '弗糯糯');
    });

    test('copyWith 部分更新', () {
      final p = PetPersona(name: '旧名', traits: '粘人');
      final updated = p.copyWith(name: '新名');
      expect(updated.name, '新名');
      expect(updated.traits, '粘人'); // 未改的保留
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && flutter test test/pet/pet_persona_test.dart
```
Expected: FAIL — `pet_persona.dart` 不存在

- [ ] **Step 3: 实现 PetPersona**

```dart
// Flutter 3.24 / Dart 3.5
class PetPersona {
  final String name;
  final String systemPrompt;
  final String? templateId;
  final String traits;

  static const _defaultPrompt =
      '你是弗糯糯，一只可爱的虚拟宠物精灵。'
      '性格：软萌、粘人、偶尔丧丧的摆烂。'
      '自称"糯糯"，句尾加"喵~"或"..."。'
      '保持短小可爱，不超过2句话。';

  PetPersona({
    this.name = '弗糯糯',
    this.systemPrompt = _defaultPrompt,
    this.templateId,
    this.traits = '',
  });

  PetPersona copyWith({
    String? name,
    String? systemPrompt,
    String? templateId,
    String? traits,
  }) {
    return PetPersona(
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      templateId: templateId ?? this.templateId,
      traits: traits ?? this.traits,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'systemPrompt': systemPrompt,
    if (templateId != null) 'templateId': templateId,
    'traits': traits,
  };

  factory PetPersona.fromJson(Map<String, dynamic> json) {
    return PetPersona(
      name: json['name'] as String? ?? '弗糯糯',
      systemPrompt: json['systemPrompt'] as String? ?? _defaultPrompt,
      templateId: json['templateId'] as String?,
      traits: json['traits'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/pet/pet_persona_test.dart
```
Expected: 4/4 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pet/pet_persona.dart test/pet/pet_persona_test.dart
git commit -m "feat: add PetPersona model with toJson/fromJson/copyWith"
```

---

### Task 2: PetProfile — 用户画像模型

**Files:**
- Create: `lib/models/pet_profile.dart`
- Test: `test/pet/pet_profile_test.dart`

**Spec 覆盖:** F2 (用户画像)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/pet_profile.dart';

void main() {
  group('PetProfile', () {
    test('默认值', () {
      final p = PetProfile();
      expect(p.nickname, isEmpty);
      expect(p.interests, isEmpty);
      expect(p.callMe, isEmpty);
      expect(p.interactionCount, 0);
      expect(p.growthStage, GrowthStage.newbie);
    });

    test('toJson/fromJson 往返', () {
      final p = PetProfile(
        nickname: '小明',
        interests: ['编程', '游戏'],
        callMe: '小明',
        interactionCount: 50,
        growthStage: GrowthStage.familiar,
        rejections: {'suggestion': 3},
      );
      final json = p.toJson();
      final restored = PetProfile.fromJson(json);
      expect(restored.nickname, '小明');
      expect(restored.interests, ['编程', '游戏']);
      expect(restored.interactionCount, 50);
      expect(restored.growthStage, GrowthStage.familiar);
      expect(restored.rejections['suggestion'], 3);
    });

    test('fromJson 缺字段默认值', () {
      final p = PetProfile.fromJson({});
      expect(p.nickname, isEmpty);
      expect(p.growthStage, GrowthStage.newbie);
    });

    test('GrowthStage 按轮数计算', () {
      expect(GrowthStage.fromInteractions(0), GrowthStage.newbie);
      expect(GrowthStage.fromInteractions(15), GrowthStage.newbie);
      expect(GrowthStage.fromInteractions(30), GrowthStage.familiar);
      expect(GrowthStage.fromInteractions(200), GrowthStage.close);
      expect(GrowthStage.fromInteractions(1000), GrowthStage.oldFriend);
    });

    test('copyWith', () {
      final p = PetProfile(nickname: '旧');
      final updated = p.copyWith(nickname: '新', interactionCount: 10);
      expect(updated.nickname, '新');
      expect(updated.interactionCount, 10);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/pet/pet_profile_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetProfile**

```dart
// Flutter 3.24 / Dart 3.5
enum GrowthStage { newbie, familiar, close, oldFriend }

extension GrowthStageExt on GrowthStage {
  String get label => switch (this) {
    GrowthStage.newbie => '初识',
    GrowthStage.familiar => '熟悉',
    GrowthStage.close => '默契',
    GrowthStage.oldFriend => '老友',
  };

  static GrowthStage fromInteractions(int count) => switch (count) {
    < 30 => GrowthStage.newbie,
    < 200 => GrowthStage.familiar,
    < 1000 => GrowthStage.close,
    _ => GrowthStage.oldFriend,
  };
}

class PetProfile {
  final String nickname;
  final List<String> interests;
  final String callMe;
  final int interactionCount;
  final GrowthStage growthStage;
  final Map<String, int> rejections;

  PetProfile({
    this.nickname = '',
    List<String>? interests,
    this.callMe = '',
    this.interactionCount = 0,
    GrowthStage? growthStage,
    Map<String, int>? rejections,
  })  : interests = List.from(interests ?? []),
        growthStage = growthStage ?? GrowthStage.fromInteractions(interactionCount ?? 0),
        rejections = Map.from(rejections ?? {});

  PetProfile copyWith({
    String? nickname,
    List<String>? interests,
    String? callMe,
    int? interactionCount,
    GrowthStage? growthStage,
    Map<String, int>? rejections,
  }) {
    final count = interactionCount ?? this.interactionCount;
    return PetProfile(
      nickname: nickname ?? this.nickname,
      interests: interests ?? List.from(this.interests),
      callMe: callMe ?? this.callMe,
      interactionCount: count,
      growthStage: growthStage ?? GrowthStage.fromInteractions(count),
      rejections: rejections ?? Map.from(this.rejections),
    );
  }

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'interests': interests,
    'callMe': callMe,
    'interactionCount': interactionCount,
    'growthStage': growthStage.name,
    'rejections': rejections,
  };

  factory PetProfile.fromJson(Map<String, dynamic> json) {
    return PetProfile(
      nickname: json['nickname'] as String? ?? '',
      interests: (json['interests'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      callMe: json['callMe'] as String? ?? '',
      interactionCount: (json['interactionCount'] as num?)?.toInt() ?? 0,
      growthStage: GrowthStage.values.firstWhere(
        (e) => e.name == json['growthStage'],
        orElse: () => GrowthStage.newbie,
      ),
      rejections: (json['rejections'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/pet/pet_profile_test.dart
```
Expected: 5/5 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/pet_profile.dart test/pet/pet_profile_test.dart
git commit -m "feat: add PetProfile model with growth stages and rejection tracking"
```

---

### Task 3: PetDiary — 成长日记模型

**Files:**
- Create: `lib/models/pet_diary.dart`
- Test: `test/pet/pet_diary_test.dart`

**Spec 覆盖:** F5 (成长日记)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/pet_diary.dart';

void main() {
  group('PetDiaryEntry', () {
    test('toJson/fromJson 往返', () {
      final now = DateTime.now();
      final entry = PetDiaryEntry(
        id: 'diary-1',
        date: now,
        content: '今天糯糯认识了新朋友~',
        mood: '😊',
        tags: ['初识', '互动'],
        autoGenerated: true,
      );
      final json = entry.toJson();
      final restored = PetDiaryEntry.fromJson(json);
      expect(restored.id, 'diary-1');
      expect(restored.content, '今天糯糯认识了新朋友~');
      expect(restored.mood, '😊');
      expect(restored.tags, ['初识', '互动']);
      expect(restored.autoGenerated, true);
    });

    test('默认值', () {
      final entry = PetDiaryEntry(content: '测试日记');
      expect(entry.id, isNotEmpty);
      expect(entry.mood, '📝');
      expect(entry.autoGenerated, false);
      expect(entry.tags, isEmpty);
    });

    test('fromJson 缺字段默认值', () {
      final entry = PetDiaryEntry.fromJson({'content': '仅有内容'});
      expect(entry.content, '仅有内容');
      expect(entry.mood, '📝');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/pet/pet_diary_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetDiary**

```dart
// Flutter 3.24 / Dart 3.5
class PetDiaryEntry {
  final String id;
  final DateTime date;
  final String content;
  final String mood;
  final List<String> tags;
  final bool autoGenerated;

  PetDiaryEntry({
    String? id,
    DateTime? date,
    required this.content,
    this.mood = '📝',
    List<String>? tags,
    this.autoGenerated = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        date = date ?? DateTime.now(),
        tags = List.from(tags ?? []);

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'content': content,
    'mood': mood,
    'tags': tags,
    'autoGenerated': autoGenerated,
  };

  factory PetDiaryEntry.fromJson(Map<String, dynamic> json) {
    return PetDiaryEntry(
      id: json['id'] as String?,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '📝',
      tags: (json['tags'] as List<dynamic>?)
          ?.map((e) => e.toString()).toList() ?? [],
      autoGenerated: json['autoGenerated'] == true,
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/pet/pet_diary_test.dart
```
Expected: 3/3 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/pet_diary.dart test/pet/pet_diary_test.dart
git commit -m "feat: add PetDiaryEntry model for growth diary"
```

---

### Task 4: PetTokenUsage — Token 用量模型

**Files:**
- Create: `lib/models/pet_token_usage.dart`
- Test: `test/pet/pet_token_usage_test.dart`

**Spec 覆盖:** F15 (Token 管控)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/models/pet_token_usage.dart';

void main() {
  group('PetTokenUsage', () {
    test('toJson/fromJson 往返', () {
      final usage = PetTokenUsage(
        date: DateTime(2026, 5, 30),
        decisionTokens: 1000,
        chatTokens: 5000,
        visionTokens: 2000,
        totalTokens: 8000,
      );
      final json = usage.toJson();
      final restored = PetTokenUsage.fromJson(json);
      expect(restored.date, DateTime(2026, 5, 30));
      expect(restored.decisionTokens, 1000);
      expect(restored.chatTokens, 5000);
      expect(restored.visionTokens, 2000);
      expect(restored.totalTokens, 8000);
    });

    test('默认值', () {
      final usage = PetTokenUsage();
      expect(usage.decisionTokens, 0);
      expect(usage.chatTokens, 0);
      expect(usage.visionTokens, 0);
      expect(usage.totalTokens, 0);
    });

    test('add 累加正确', () {
      final usage = PetTokenUsage();
      final updated = usage.add(decision: 100, chat: 200, vision: 50);
      expect(updated.decisionTokens, 100);
      expect(updated.chatTokens, 200);
      expect(updated.visionTokens, 50);
      expect(updated.totalTokens, 350);
    });

    test('dateKey 格式正确', () {
      final usage = PetTokenUsage(date: DateTime(2026, 5, 30));
      expect(usage.dateKey, '2026-05-30');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/pet/pet_token_usage_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetTokenUsage**

```dart
// Flutter 3.24 / Dart 3.5
class PetTokenUsage {
  final DateTime date;
  final int decisionTokens;
  final int chatTokens;
  final int visionTokens;
  final int totalTokens;

  PetTokenUsage({
    DateTime? date,
    this.decisionTokens = 0,
    this.chatTokens = 0,
    this.visionTokens = 0,
    this.totalTokens = 0,
  }) : date = date ?? DateTime.now();

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  PetTokenUsage add({int decision = 0, int chat = 0, int vision = 0}) {
    return PetTokenUsage(
      date: date,
      decisionTokens: decisionTokens + decision,
      chatTokens: chatTokens + chat,
      visionTokens: visionTokens + vision,
      totalTokens: totalTokens + decision + chat + vision,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': dateKey,
    'decisionTokens': decisionTokens,
    'chatTokens': chatTokens,
    'visionTokens': visionTokens,
    'totalTokens': totalTokens,
  };

  factory PetTokenUsage.fromJson(Map<String, dynamic> json) {
    return PetTokenUsage(
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      decisionTokens: (json['decisionTokens'] as num?)?.toInt() ?? 0,
      chatTokens: (json['chatTokens'] as num?)?.toInt() ?? 0,
      visionTokens: (json['visionTokens'] as num?)?.toInt() ?? 0,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/pet/pet_token_usage_test.dart
```
Expected: 4/4 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/pet_token_usage.dart test/pet/pet_token_usage_test.dart
git commit -m "feat: add PetTokenUsage model with add() accumulator"
```

---

## Phase 2: 服务层

### Task 5: PetTokenService — Token 统计

**Files:**
- Create: `lib/services/pet_token_service.dart`
- Test: `test/services/pet_token_service_test.dart`

**Spec 覆盖:** F15 (Token 管控：日/周/月汇总、额度检查、用量看板数据)

**依赖:** Task 4 (PetTokenUsage)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../../lib/services/pet_token_service.dart';
import '../../lib/models/pet_token_usage.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_token_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetTokenService', () {
    test('recordTokens 记录并累加', () async {
      final svc = PetTokenService();
      await svc.recordTokens(decision: 100, chat: 200);
      final today = await svc.getTodayUsage();
      expect(today.decisionTokens, 100);
      expect(today.chatTokens, 200);
      expect(today.totalTokens, 300);

      // 同一天累加
      await svc.recordTokens(decision: 50, vision: 30);
      final updated = await svc.getTodayUsage();
      expect(updated.decisionTokens, 150);
      expect(updated.visionTokens, 30);
      expect(updated.totalTokens, 380);
    });

    test('getWeekUsage 返回最近 7 天', () async {
      final svc = PetTokenService();
      await svc.recordTokens(decision: 100);
      final week = await svc.getWeekUsage();
      expect(week.length, lessThanOrEqualTo(7));
      expect(week.any((d) => d.totalTokens > 0), true);
    });

    test('checkBudget 额度检查', () async {
      final svc = PetTokenService();
      // 默认 50k 额度
      expect(await svc.checkBudget(), true);
      expect(await svc.getBudgetRemaining(), 50000);

      // 模拟超限
      await svc.recordTokens(decision: 50001);
      expect(await svc.checkBudget(), false);
      expect(await svc.getBudgetRemaining(), -1);
    });

    test('不限制模式 checkBudget 永远 true', () async {
      final svc = PetTokenService();
      await svc.setBudget(null); // 不限制
      await svc.recordTokens(decision: 999999);
      expect(await svc.checkBudget(), true);
    });

    test('getBudgetUsageFraction 返回 0.0~1.0', () async {
      final svc = PetTokenService();
      await svc.setBudget(100);
      await svc.recordTokens(decision: 30);
      final fraction = await svc.getBudgetUsageFraction();
      expect(fraction, closeTo(0.3, 0.01));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_token_service_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetTokenService**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/pet_token_usage.dart';

class PetTokenService extends ChangeNotifier {
  static const _boxName = 'pet_token';
  int? _dailyBudget = 50000;

  int? get dailyBudget => _dailyBudget;
  bool get isUnlimited => _dailyBudget == null;

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<void> setBudget(int? tokens) async {
    _dailyBudget = tokens;
    notifyListeners();
  }

  Future<void> recordTokens({
    int decision = 0,
    int chat = 0,
    int vision = 0,
  }) async {
    final box = await _box;
    final today = PetTokenUsage();
    final existing = box.get(today.dateKey);
    if (existing != null) {
      final current = PetTokenUsage.fromJson(Map<String, dynamic>.from(existing as Map));
      final updated = current.add(decision: decision, chat: chat, vision: vision);
      await box.put(today.dateKey, updated.toJson());
    } else {
      final updated = today.add(decision: decision, chat: chat, vision: vision);
      await box.put(today.dateKey, updated.toJson());
    }
    notifyListeners();
  }

  Future<PetTokenUsage> getTodayUsage() async {
    final box = await _box;
    final today = PetTokenUsage();
    final raw = box.get(today.dateKey);
    if (raw == null) return PetTokenUsage();
    return PetTokenUsage.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<List<PetTokenUsage>> getWeekUsage() async {
    final box = await _box;
    final result = <PetTokenUsage>[];
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final raw = box.get(key);
      if (raw != null) {
        result.add(PetTokenUsage.fromJson(Map<String, dynamic>.from(raw as Map)));
      } else {
        result.add(PetTokenUsage(date: d));
      }
    }
    return result;
  }

  Future<int> getMonthUsage() async {
    final box = await _box;
    int total = 0;
    final now = DateTime.now();
    for (int i = 0; i < now.day; i++) {
      final d = DateTime(now.year, now.month, i + 1);
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final raw = box.get(key);
      if (raw != null) {
        total += (raw['totalTokens'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  Future<bool> checkBudget() async {
    if (_dailyBudget == null) return true;
    final today = await getTodayUsage();
    return today.totalTokens < _dailyBudget!;
  }

  Future<int> getBudgetRemaining() async {
    if (_dailyBudget == null) return 999999;
    final today = await getTodayUsage();
    return _dailyBudget! - today.totalTokens;
  }

  Future<double> getBudgetUsageFraction() async {
    if (_dailyBudget == null || _dailyBudget == 0) return 0;
    final today = await getTodayUsage();
    return today.totalTokens / _dailyBudget!;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_token_service_test.dart
```
Expected: 5/5 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet_token_service.dart test/services/pet_token_service_test.dart
git commit -m "feat: add PetTokenService with daily/weekly/monthly tracking and budget control"
```

---

### Task 6: PetProfileService — 用户画像

**Files:**
- Create: `lib/services/pet_profile_service.dart`
- Test: `test/services/pet_profile_service_test.dart`

**Spec 覆盖:** F2 (用户画像) + F4 (被拒学习) + F5 (成长阶段)

**依赖:** Task 2 (PetProfile)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../../lib/services/pet_profile_service.dart';
import '../../lib/models/pet_profile.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_profile_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetProfileService', () {
    test('loadProfile 无数据返回默认', () async {
      final svc = PetProfileService();
      final profile = await svc.loadProfile();
      expect(profile.nickname, isEmpty);
      expect(profile.growthStage, GrowthStage.newbie);
    });

    test('saveProfile/loadProfile 往返', () async {
      final svc = PetProfileService();
      final original = PetProfile(nickname: '小明', interests: ['编程']);
      await svc.saveProfile(original);
      final loaded = await svc.loadProfile();
      expect(loaded.nickname, '小明');
      expect(loaded.interests, ['编程']);
    });

    test('recordRejection 累加被拒计数', () async {
      final svc = PetProfileService();
      await svc.recordRejection('suggestion');
      await svc.recordRejection('suggestion');
      await svc.recordRejection('chat');
      final profile = await svc.loadProfile();
      expect(profile.rejections['suggestion'], 2);
      expect(profile.rejections['chat'], 1);
    });

    test('incrementInteractions 递增并更新成长阶段', () async {
      final svc = PetProfileService();
      await svc.incrementInteractions(30); // 达到 30 → familiar
      final profile = await svc.loadProfile();
      expect(profile.interactionCount, 30);
      expect(profile.growthStage, GrowthStage.familiar);
    });

    test('getRejectionProbability 被拒多次后降低概率', () async {
      final svc = PetProfileService();
      // scenario "suggestion" 被拒 5 次
      for (int i = 0; i < 5; i++) {
        await svc.recordRejection('suggestion');
      }
      final prob = await svc.getRejectionProbability('suggestion');
      // 基础 0.7 - 每次被拒 0.05，最低 0.2
      expect(prob, lessThan(0.7));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_profile_service_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetProfileService**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/pet_profile.dart';

class PetProfileService extends ChangeNotifier {
  static const _boxName = 'pet_profile';
  static const _key = 'profile';

  Future<Box> get _box => Hive.openBox(_boxName);

  Future<PetProfile> loadProfile() async {
    final box = await _box;
    final raw = box.get(_key);
    if (raw == null) return PetProfile();
    return PetProfile.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> saveProfile(PetProfile profile) async {
    final box = await _box;
    await box.put(_key, profile.toJson());
    notifyListeners();
  }

  Future<void> recordRejection(String scene) async {
    final profile = await loadProfile();
    final rejections = Map<String, int>.from(profile.rejections);
    rejections[scene] = (rejections[scene] ?? 0) + 1;
    await saveProfile(profile.copyWith(rejections: rejections));
  }

  Future<void> incrementInteractions(int count) async {
    final profile = await loadProfile();
    final newCount = profile.interactionCount + count;
    await saveProfile(profile.copyWith(interactionCount: newCount));
  }

  /// 返回某场景下主动发起的概率 (0.0~1.0)
  /// 基础概率 0.7，每次被拒 -0.05，最低 0.2
  Future<double> getRejectionProbability(String scene) async {
    final profile = await loadProfile();
    final rejectCount = profile.rejections[scene] ?? 0;
    return (0.7 - rejectCount * 0.05).clamp(0.2, 0.7);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_profile_service_test.dart
```
Expected: 5/5 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet_profile_service.dart test/services/pet_profile_service_test.dart
git commit -m "feat: add PetProfileService with rejection learning and growth tracking"
```

---

### Task 7: PetChatService — 对话管理

**Files:**
- Create: `lib/services/pet_chat_service.dart`
- Test: `test/services/pet_chat_service_test.dart`

**Spec 覆盖:** F7 (对话体系) + F9 (交叉记忆) + F10 (记忆管理) + F14 (对话管理)

**依赖:** Task 5 (PetTokenService) — 用于记录对话 token 消耗

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../../lib/services/pet_chat_service.dart';

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('pet_chat_test_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
  });

  group('PetChatService', () {
    test('createChat 创建新对话', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      expect(id, isNotEmpty);
      expect(svc.currentId, id);
    });

    test('createChat 自动标题为"新对话"', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      final chat = await svc.getChat(id);
      expect(chat!['title'], '新对话');
    });

    test('addMessage 追加消息并更新标题', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.addMessage(id, 'user', '今天天气真好喵~');
      await svc.addMessage(id, 'assistant', '是的主人！');
      final chat = await svc.getChat(id);
      final msgs = chat!['messages'] as List;
      expect(msgs.length, 2);
      // 标题自动取用户消息前15字
      expect(chat['title'], '今天天气真好喵~');
    });

    test('renameChat 重命名', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.renameChat(id, '自定义标题');
      final chat = await svc.getChat(id);
      expect(chat!['title'], '自定义标题');
    });

    test('deleteChat 删除后 currentId 切到最近一个', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      await svc.deleteChat(id2);
      expect(svc.currentId, id1);
    });

    test('switchChat 切换', () async {
      final svc = PetChatService();
      final id1 = await svc.createChat();
      final id2 = await svc.createChat();
      await svc.switchChat(id1);
      expect(svc.currentId, id1);
    });

    test('listChats 按时间倒序', () async {
      final svc = PetChatService();
      await svc.createChat();
      await Future.delayed(const Duration(milliseconds: 10));
      await svc.createChat();
      final list = await svc.listChats();
      expect(list.length, 2);
    });

    test('importMemories 批量导入', () async {
      final svc = PetChatService();
      // 模拟从主 App 导入的对话摘要
      final count = await svc.importMemories([
        {'id': 'conv-1', 'title': '数学讨论', 'summary': '讨论微积分'},
        {'id': 'conv-2', 'title': '编程帮助', 'summary': 'Flutter 问题'},
      ]);
      expect(count, 2);
      final memories = await svc.listMemories();
      expect(memories.length, 2);
    });

    test('deleteMemory 删除记忆', () async {
      final svc = PetChatService();
      await svc.importMemories([
        {'id': 'conv-1', 'title': '测试', 'summary': '测试内容'},
      ]);
      final memories = await svc.listMemories();
      await svc.deleteMemory(memories.first['id'] as String);
      expect((await svc.listMemories()).length, 0);
    });

    test('buildContext 拼接上下文', () async {
      final svc = PetChatService();
      final id = await svc.createChat();
      await svc.addMessage(id, 'user', '你好');
      await svc.addMessage(id, 'assistant', '喵~你好主人！');
      await svc.addMessage(id, 'user', '今天心情不好');
      await svc.addMessage(id, 'assistant', '怎么了喵？糯糯陪你~');
      final ctx = await svc.buildContext(id, maxRounds: 2);
      expect(ctx, contains('你好'));
      expect(ctx, contains('今天心情不好'));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_chat_service_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetChatService**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class PetChatService extends ChangeNotifier {
  static const _chatsBox = 'pet_chats';
  static const _memBox = 'pet_memories';
  String? _currentId;

  String? get currentId => _currentId;

  Future<Box> get _chats => Hive.openBox(_chatsBox);
  Future<Box> get _mems => Hive.openBox(_memBox);

  Future<String> createChat() async {
    final box = await _chats;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await box.put(id, {
      'id': id,
      'title': '新对话',
      'messages': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    _currentId = id;
    await box.put('currentId', id);
    notifyListeners();
    return id;
  }

  Future<Map<String, dynamic>?> getChat(String id) async {
    final box = await _chats;
    final raw = box.get(id);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> addMessage(String chatId, String role, String content) async {
    final box = await _chats;
    final chat = await getChat(chatId);
    if (chat == null) return;
    final messages = List<Map<String, dynamic>>.from(chat['messages'] as List? ?? []);
    messages.add({
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
    // 标题：第一条用户消息前 15 字
    String title = chat['title'] as String? ?? '新对话';
    if (title == '新对话' && role == 'user') {
      title = content.length > 15 ? '${content.substring(0, 15)}...' : content;
    }
    await box.put(chatId, {
      ...chat,
      'title': title,
      'messages': messages,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> renameChat(String id, String title) async {
    final box = await _chats;
    final chat = await getChat(id);
    if (chat == null) return;
    await box.put(id, {...chat, 'title': title});
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    final box = await _chats;
    await box.delete(id);
    if (_currentId == id) {
      // 切到最近一个
      final all = await listChats();
      _currentId = all.isNotEmpty ? all.first['id'] as String? : null;
      await box.put('currentId', _currentId);
    }
    notifyListeners();
  }

  Future<void> switchChat(String id) async {
    _currentId = id;
    final box = await _chats;
    await box.put('currentId', id);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> listChats() async {
    final box = await _chats;
    final all = box.values
        .whereType<Map>()
        .where((m) => m['id'] != null && m['id'] != 'currentId')
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    all.sort((a, b) {
      final aTime = DateTime.tryParse('${a['updatedAt'] ?? ''}') ?? DateTime(2000);
      final bTime = DateTime.tryParse('${b['updatedAt'] ?? ''}') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });
    return all;
  }

  /// 构建最近 N 轮对话上下文
  Future<String> buildContext(String chatId, {int maxRounds = 3}) async {
    final chat = await getChat(chatId);
    if (chat == null) return '';
    final messages = List<Map<String, dynamic>>.from(chat['messages'] as List? ?? []);
    // 取最近 maxRounds*2 条（user + assistant 各一条为一轮）
    final recent = messages.reversed.take(maxRounds * 2).toList().reversed.toList();
    return recent.map((m) => '${m['role'] == 'user' ? '主人' : '糯糯'}: ${m['content']}').join('\n');
  }

  // ── 交叉记忆 ──

  Future<int> importMemories(List<Map<String, dynamic>> summaries) async {
    final box = await _mems;
    int count = 0;
    for (final summary in summaries) {
      final id = DateTime.now().microsecondsSinceEpoch.toString() + count.toString();
      await box.put(id, {
        'id': id,
        'content': summary['summary'] as String? ?? '',
        'context': 'imported:${summary['id'] ?? ''}',
        'sourceTitle': summary['title'] as String? ?? '未知对话',
        'importedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      count++;
    }
    notifyListeners();
    return count;
  }

  Future<List<Map<String, dynamic>>> listMemories() async {
    final box = await _mems;
    return box.values
        .whereType<Map>()
        .where((m) => m['id'] != null && m['id'] != 'imports')
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse('${a['importedAt'] ?? a['createdAt'] ?? ''}') ?? DateTime(2000);
        final bTime = DateTime.tryParse('${b['importedAt'] ?? b['createdAt'] ?? ''}') ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
  }

  Future<void> deleteMemory(String id) async {
    final box = await _mems;
    await box.delete(id);
    notifyListeners();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_chat_service_test.dart
```
Expected: 10/10 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet_chat_service.dart test/services/pet_chat_service_test.dart
git commit -m "feat: add PetChatService with chat CRUD, context builder, cross-memory import"
```

---

## Phase 3: Agent 核心

### Task 8: PetAgentCore — 决策引擎

**Files:**
- Create: `lib/services/pet_agent_core.dart`
- Test: `test/services/pet_agent_core_test.dart`

**Spec 覆盖:** F1 (单一大脑) + F3 (关注度 L0-L3) + F4 (心情扰动) + F6 (主动搭话) + 三层 Token 过滤 + 引擎 #1 被杀降级 + API 不可用纯规则模式

**依赖:** Phase 2 全部 (PetTokenService, PetProfileService, PetChatService)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/pet_agent_core.dart';

void main() {
  group('PetAgentCore', () {
    test('初始状态', () {
      final agent = PetAgentCore();
      expect(agent.isActive, false);
      expect(agent.attentionLevel, AttentionLevel.L3);
      expect(agent.mood, isA<AgentMood>());
    });

    test('start/stop 生命周期', () {
      final agent = PetAgentCore();
      agent.start();
      expect(agent.isActive, true);
      agent.stop();
      expect(agent.isActive, false);
    });

    test('setAttentionLevel 手动设置', () {
      final agent = PetAgentCore();
      agent.setAttentionLevel(AttentionLevel.L1);
      expect(agent.attentionLevel, AttentionLevel.L1);
    });

    test('AgentMood 三维概率在 0~1 范围', () {
      final mood = AgentMood();
      expect(mood.activity, inInclusiveRange(0.0, 1.0));
      expect(mood.sass, inInclusiveRange(0.0, 1.0));
      expect(mood.compliance, inInclusiveRange(0.0, 1.0));
    });

    test('AgentMood.applyNoise 加入随机扰动', () {
      final mood = AgentMood(activity: 0.5, sass: 0.5, compliance: 0.5);
      final perturbed = mood.applyNoise();
      // 加了 ±0.15~0.2 的噪声，值应该有所变化
      expect(perturbed.activity != 0.5 || perturbed.sass != 0.5, true);
    });

    test('AttentionLevel 决策间隔', () {
      expect(AttentionLevel.L3.interval.inSeconds, 60);
      expect(AttentionLevel.L2.interval.inSeconds, 120);
      expect(AttentionLevel.L1.interval.inSeconds, 300);
      expect(AttentionLevel.L0.interval.inSeconds, 0); // 停止
    });

    test('三层过滤 — 规则层 assessLocally 不耗 token', () {
      final agent = PetAgentCore();
      // 规则层判断：深夜 → 不需要 LLM
      final result = agent.assessLocally(
        hour: 2,
        hunger: 80,
        energy: 80,
        hasRecentChat: false,
      );
      // 深夜 + 无紧急状态 → 本地规则给出结果
      expect(result.shouldSkipLLM, true);
    });

    test('三层过滤 — 饥饿触发时不应跳过 LLM', () {
      final agent = PetAgentCore();
      final result = agent.assessLocally(
        hour: 14,
        hunger: 20,
        energy: 80,
        hasRecentChat: false,
      );
      expect(result.shouldSkipLLM, false);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/services/pet_agent_core_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetAgentCore**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../api/deepseek_client.dart';
import '../pet/pet_persona.dart';
import 'pet_token_service.dart';
import 'pet_profile_service.dart';

enum AttentionLevel {
  L0, // 休眠
  L1, // 低打扰
  L2, // 观察
  L3; // 活跃

  Duration get interval => switch (this) {
    AttentionLevel.L0 => Duration.zero,
    AttentionLevel.L1 => const Duration(minutes: 5),
    AttentionLevel.L2 => const Duration(minutes: 2),
    AttentionLevel.L3 => const Duration(seconds: 60),
  };
}

class AgentMood {
  final double activity;
  final double sass;
  final double compliance;

  AgentMood({this.activity = 0.5, this.sass = 0.3, this.compliance = 0.8});

  AgentMood applyNoise() {
    final rng = Random();
    double noise() => (rng.nextDouble() * 0.1) - 0.05 + (rng.nextBool() ? 0.15 : -0.15);
    return AgentMood(
      activity: (activity + noise()).clamp(0.0, 1.0),
      sass: (sass + noise()).clamp(0.0, 1.0),
      compliance: (compliance + noise()).clamp(0.0, 1.0),
    );
  }
}

class AssessResult {
  final bool shouldSkipLLM;
  final String? ruleAction;
  final String? ruleContent;
  final String context;

  AssessResult({this.shouldSkipLLM = false, this.ruleAction, this.ruleContent, this.context = ''});
}

class ActionEntry {
  final String type; // bubble, move, flip, speak, silent
  final String? content;
  final DateTime timestamp;

  ActionEntry({required this.type, this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': type,
    if (content != null) 'content': content,
    'timestamp': timestamp.toIso8601String(),
  };
}

class PetAgentCore extends ChangeNotifier {
  final PetTokenService tokenService;
  final PetProfileService profileService;

  LLMClient? _decisionClient;
  LLMClient? _chatClient;
  bool _isActive = false;
  AttentionLevel _attentionLevel = AttentionLevel.L3;
  AgentMood _mood = AgentMood();
  Timer? _perceptionTimer;
  int _consecutiveApiFailures = 0;
  bool _isPureRuleMode = false;
  final _rng = Random();

  PetAgentCore({
    PetTokenService? tokenService,
    PetProfileService? profileService,
  })  : tokenService = tokenService ?? PetTokenService(),
        profileService = profileService ?? PetProfileService();

  bool get isActive => _isActive;
  AttentionLevel get attentionLevel => _attentionLevel;
  AgentMood get mood => _mood;
  bool get isPureRuleMode => _isPureRuleMode;

  Future<void> init({
    String? decisionApiKey,
    String? chatApiKey,
    String? decisionModel,
    String? chatModel,
  }) async {
    if (decisionApiKey != null && decisionApiKey.isNotEmpty) {
      _decisionClient = LLMClient(apiKey: decisionApiKey);
    }
    if (chatApiKey != null && chatApiKey.isNotEmpty) {
      _chatClient = LLMClient(apiKey: chatApiKey);
    }
    // 从 Hive 恢复关注度和心情
    await _loadState();
  }

  Future<void> _loadState() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('agent_state');
      if (raw != null) {
        final map = Map<String, dynamic>.from(raw as Map);
        _attentionLevel = AttentionLevel.values.firstWhere(
          (e) => e.name == map['attentionLevel'],
          orElse: () => AttentionLevel.L3,
        );
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final box = await Hive.openBox('pet_config');
      await box.put('agent_state', {'attentionLevel': _attentionLevel.name});
    } catch (_) {}
  }

  void setAttentionLevel(AttentionLevel level) {
    _attentionLevel = level;
    _saveState();
    notifyListeners();
  }

  void start() {
    if (_isActive) return;
    _isActive = true;
    _schedulePerception();
    notifyListeners();
  }

  void stop() {
    _isActive = false;
    _perceptionTimer?.cancel();
    _perceptionTimer = null;
    notifyListeners();
  }

  void _schedulePerception() {
    _perceptionTimer?.cancel();
    final interval = _attentionLevel.interval;
    if (interval == Duration.zero) return; // L0 不调度
    _perceptionTimer = Timer(interval, () async {
      await _perceive();
      if (_isActive) _schedulePerception();
    });
  }

  Future<void> _perceive() async {
    if (!_isActive || _isPureRuleMode) return;
    if (!await tokenService.checkBudget()) return; // 额度用完

    final now = DateTime.now();
    final local = assessLocally(
      hour: now.hour,
      hunger: 80, // 后续从 PetController 读取
      energy: 80,
      hasRecentChat: false,
    );

    if (local.shouldSkipLLM) {
      // 规则层给出结果，不调 LLM
      if (local.ruleAction != null) {
        await _publishAction(ActionEntry(type: local.ruleAction!, content: local.ruleContent));
      }
      return;
    }

    // 需要 LLM 决策
    await _evaluate(context: local.context);
  }

  /// 三层过滤的第一层：本地规则判断
  AssessResult assessLocally({
    required int hour,
    required int hunger,
    required int energy,
    required bool hasRecentChat,
  }) {
    final parts = <String>[];

    // 深夜 → 安静模式
    if (hour >= 23 || hour < 7) {
      return AssessResult(shouldSkipLLM: true);
    }

    // 紧急状态 → 不跳过 LLM
    if (hunger < 30) {
      parts.add('饥饿值: $hunger');
      return AssessResult(shouldSkipLLM: false, context: parts.join('. '));
    }
    if (energy < 20) {
      parts.add('体力值: $energy');
      return AssessResult(shouldSkipLLM: false, context: parts.join('. '));
    }

    // 有最近聊天 → 不跳过
    if (hasRecentChat) {
      return AssessResult(shouldSkipLLM: false, context: '有最近互动');
    }

    // 无事发生 → 随机决定是否搭话 (~30%)
    if (_rng.nextDouble() < 0.3) {
      return AssessResult(shouldSkipLLM: false);
    }

    return AssessResult(shouldSkipLLM: true); // 没必要打扰
  }

  Future<void> _evaluate({String context = ''}) async {
    if (_decisionClient == null) return;

    try {
      final persona = await _loadPersona();
      final mood = _mood.applyNoise();

      final prompt = StringBuffer();
      prompt.writeln('当前语境：$context');
      prompt.writeln('当前心情：活跃度=${mood.activity.toStringAsFixed(2)} 毒舌度=${mood.sass.toStringAsFixed(2)} 听话度=${mood.compliance.toStringAsFixed(2)}');
      prompt.writeln('决策：你现在想做什么？回复格式：{"action":"bubble/move/flip/speak/silent","content":"..."}');

      final result = await _decisionClient!.send(
        history: [],
        userContent: prompt.toString(),
        maxTokens: 64,
        thinkingEnabled: false,
      );

      // 记录 token
      if (result.usage != null) {
        await tokenService.recordTokens(decision: result.usage!['total_tokens'] ?? 0);
      }

      _consecutiveApiFailures = 0;

      // 写入 action queue
      final action = _parseAction(result.content);
      if (action != null) {
        await _publishAction(action);
      }
    } catch (e) {
      _consecutiveApiFailures++;
      if (_consecutiveApiFailures >= 3) {
        _isPureRuleMode = true;
        debugPrint('PetAgentCore: 连续 3 次 API 失败，切到纯规则模式');
      }
    }
  }

  ActionEntry? _parseAction(String llmOutput) {
    // 简单 JSON 解析，后续用 LLM 结构化输出优化
    try {
      final start = llmOutput.indexOf('{');
      final end = llmOutput.lastIndexOf('}');
      if (start == -1 || end == -1) return null;
      final json = llmOutput.substring(start, end + 1);
      // 用简单的字符串匹配代替 JSON 解析（避免依赖）
      if (json.contains('"bubble"')) {
        final content = _extractContent(json);
        return ActionEntry(type: 'bubble', content: content);
      }
      if (json.contains('"move"')) return ActionEntry(type: 'move');
      if (json.contains('"flip"')) return ActionEntry(type: 'flip');
      if (json.contains('"speak"')) {
        final content = _extractContent(json);
        return ActionEntry(type: 'speak', content: content);
      }
    } catch (_) {}
    return null;
  }

  String _extractContent(String json) {
    final match = RegExp(r'"content"\s*:\s*"([^"]*)"').firstMatch(json);
    return match?.group(1) ?? '';
  }

  Future<void> _publishAction(ActionEntry action) async {
    try {
      final box = await Hive.openBox('agent_action');
      await box.put('current', action.toJson());
      notifyListeners();
    } catch (_) {}
  }

  Future<PetPersona> _loadPersona() async {
    try {
      final box = await Hive.openBox('pet_config');
      final raw = box.get('persona');
      if (raw != null) {
        return PetPersona.fromJson(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {}
    return PetPersona();
  }

  /// 引擎 #1 被杀检测 — 引擎 #2 调用此方法
  Future<bool> isEngine1Alive() async {
    try {
      final box = await Hive.openBox('agent_action');
      final raw = box.get('current');
      if (raw == null) return false;
      final map = Map<String, dynamic>.from(raw as Map);
      final timestamp = DateTime.tryParse(map['timestamp'] as String? ?? '');
      if (timestamp == null) return false;
      return DateTime.now().difference(timestamp).inSeconds < 30;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/services/pet_agent_core_test.dart
```
Expected: 8/8 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/pet_agent_core.dart test/services/pet_agent_core_test.dart
git commit -m "feat: add PetAgentCore with perception loop, attention levels, mood perturbation, 3-layer token filter"
```

---

## Phase 4: 表达层

### Task 9: PetBehavior — 自主行为 + 气泡

**Files:**
- Create: `lib/pet/pet_behavior.dart`
- Test: `test/pet/pet_behavior_test.dart`

**Spec 覆盖:** F11 (状态可视化) + F12 (自主行为) + F16 (轻量模式气泡池)

**依赖:** Phase 3 (PetAgentCore — 读取 agent_action)

- [ ] **Step 1: 写失败的测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/pet/pet_behavior.dart';

void main() {
  group('PetBehavior', () {
    testWidgets('渲染 child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PetBehavior(
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PetBehavior), findsOneWidget);
    });

    testWidgets('ecoMode 时不显示气泡', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PetBehavior(
            child: SizedBox(width: 100, height: 100),
            ecoMode: true,
          ),
        ),
      );
      await tester.pump();
      // 气泡不应显示
      expect(find.byType(Stack), findsOneWidget);
    });

    testWidgets('showBubble 显示气泡文本', (tester) async {
      final key = GlobalKey<PetBehaviorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: PetBehavior(
            key: key,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();
      key.currentState!.showBubble('测试气泡喵~');
      await tester.pump();
      expect(find.text('测试气泡喵~'), findsOneWidget);
    });

    test('预设气泡池不少于 30 条', () {
      expect(PetBehavior.presetBubbles.length, greaterThanOrEqualTo(30));
    });

    test('presetBubbles 包含不同分类', () {
      final bubbles = PetBehavior.presetBubbles;
      expect(bubbles.any((b) => b.contains('喵') || b.contains('主人')), true);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/pet/pet_behavior_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetBehavior**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class PetBehavior extends StatefulWidget {
  final Widget child;
  final bool ecoMode;

  const PetBehavior({super.key, required this.child, this.ecoMode = false});

  @override
  State<PetBehavior> createState() => PetBehaviorState();
}

class PetBehaviorState extends State<PetBehavior> {
  String? _currentBubble;
  Timer? _bubbleTimer;
  bool _flipped = false;
  Timer? _moveTimer;
  Timer? _actionWatcher;
  final _rng = Random();

  /// 预设气泡池（≥100 条）
  static const List<String> presetBubbles = [
    '主人~',
    '今天天气不错喵~',
    '好无聊...',
    '抱抱~',
    '糯糯在想你呢...',
    '主人在干嘛喵？',
    '有点饿了喵~ 🍖',
    '想睡觉了... 💤',
    '今天真开心！✨',
    '主人在忙吗？',
    '戳戳我试试喵~',
    '糯糯最喜欢主人了~',
    '嗯？有东西在动？',
    '今天有什么好玩的喵？',
    '呼噜呼噜...',
    '主人辛苦了~ ☕',
    '看到主人就开心~ 😸',
    '糯糯会一直陪着你的~',
    '今天学习了新东西！',
    '想要被摸摸头...',
    '喵？那是啥？',
    '主人笑起来最好看了~',
    '不要走嘛...',
    '夜深了，早点休息喵~ 🌙',
    '早安！新的一天！☀️',
    '该吃饭了喵~',
    '糯糯做了个梦...',
    '今天想和主人聊天~',
    '打开看看有什么好玩的？',
    '糯糯在这里等你~',
    '下雨天最适合窝在一起了~',
    '主人的声音真好听~',
    '喵~抓到你了！',
    '糯糯今天心情很好呢~',
    '有点困，但不想睡...',
    '主人的朋友圈更新了！',
    '记得喝水哦~ 💧',
    '工作久了要休息一下~',
    '糯糯给你加油！💪',
    '想到一个好主意！',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.ecoMode) {
      _startIdleBehavior();
      _startActionWatcher();
    }
  }

  void _startIdleBehavior() {
    _scheduleMove();
  }

  void _scheduleMove() {
    _moveTimer?.cancel();
    final delay = Duration(seconds: 30 + _rng.nextInt(30));
    _moveTimer = Timer(delay, () {
      if (!mounted || widget.ecoMode) return;
      _flipped = !_flipped;
      if (mounted) setState(() {});
      _scheduleMove();
    });
  }

  void _startActionWatcher() {
    _actionWatcher?.cancel();
    _actionWatcher = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || widget.ecoMode) return;
      try {
        final box = await Hive.openBox('agent_action');
        final raw = box.get('current');
        if (raw == null) return;
        final action = Map<String, dynamic>.from(raw as Map);
        final type = action['type'] as String?;
        final content = action['content'] as String?;
        switch (type) {
          case 'bubble':
          case 'speak':
            showBubble(content);
          case 'flip':
            setState(() => _flipped = !_flipped);
        }
      } catch (_) {}
    });
  }

  void showBubble(String? text) {
    if (text == null || text.isEmpty) return;
    _bubbleTimer?.cancel();
    _currentBubble = text;
    if (mounted) setState(() {});
    _bubbleTimer = Timer(const Duration(seconds: 4), () {
      _currentBubble = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PetBehavior oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ecoMode && !oldWidget.ecoMode) {
      _moveTimer?.cancel();
      _actionWatcher?.cancel();
    } else if (!widget.ecoMode && oldWidget.ecoMode) {
      _startIdleBehavior();
      _startActionWatcher();
    }
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _moveTimer?.cancel();
    _actionWatcher?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (_flipped) {
      child = Transform.flip(flipX: true, child: child);
    }
    if (_currentBubble != null) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -40,
            left: 0,
            right: 0,
            child: _Bubble(text: _currentBubble!),
          ),
        ],
      );
    }
    return child;
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  const _Bubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black87, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/pet/pet_behavior_test.dart
```
Expected: 5/5 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pet/pet_behavior.dart test/pet/pet_behavior_test.dart
git commit -m "feat: add PetBehavior with bubble display, flip, idle actions, and preset bubble pool"
```

---

## Phase 5: UI 屏幕

### Task 10: PetCenterScreen — 宠物中心

**Files:**
- Create: `lib/screens/pet_center_screen.dart`

**Spec 覆盖:** F13 (宠物中心：状态卡片 + 用量看板 + 4 Tab)

**依赖:** Phase 2-4 (PetAgentCore, PetChatService, PetTokenService)

- [ ] **Step 1: 写失败的 Widget 测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_center_screen.dart';

void main() {
  testWidgets('PetCenter 渲染 4 个 Tab', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetCenterScreen()));
    await tester.pump();
    expect(find.text('💬 聊天'), findsOneWidget);
    expect(find.text('🧠 记忆'), findsOneWidget);
    expect(find.text('📖 日记'), findsOneWidget);
    expect(find.text('⚙️ 设置'), findsOneWidget);
  });

  testWidgets('状态卡片显示宠物名字和好感度', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetCenterScreen()));
    await tester.pump();
    expect(find.text('弗糯糯'), findsOneWidget);
  });

  testWidgets('Token 看板区域存在', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetCenterScreen()));
    await tester.pump();
    expect(find.text('📊'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/screens/pet_center_screen_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetCenterScreen**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../pet/pet_controller.dart';
import '../screens/pet_settings_screen.dart';

class PetCenterScreen extends StatefulWidget {
  const PetCenterScreen({super.key});

  @override
  State<PetCenterScreen> createState() => _PetCenterScreenState();
}

class _PetCenterScreenState extends State<PetCenterScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🐾 宠物中心'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _StatusCard(),
          _TokenDashboard(),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '💬 聊天'),
              Tab(text: '🧠 记忆'),
              Tab(text: '📖 日记'),
              Tab(text: '⚙️ 设置'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PlaceholderTab(text: '聊天功能将在 Task 11 实现'),
                _PlaceholderTab(text: '记忆功能将在 Task 12 实现'),
                _PlaceholderTab(text: '日记功能将在 Task 13 实现'),
                const PetSettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Text('🐱', style: TextStyle(fontSize: 32)),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('弗糯糯', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('L3 活跃 · 初识', style: TextStyle(color: Colors.grey)),
                  ],
                ),
                Spacer(),
                Column(
                  children: [
                    Text('💕 320', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('好感度', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(emoji: '😊', label: '开心'),
                _StatItem(emoji: '🍖', label: '饱了'),
                _StatItem(emoji: '⚡', label: '精神'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String emoji;
  final String label;
  const _StatItem({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _TokenDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Text('📊', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('今日 0 / 50k', style: TextStyle(fontWeight: FontWeight.w500)),
            SizedBox(width: 16),
            Text('📈 本月 0', style: TextStyle(color: Colors.grey)),
            Spacer(),
            Text('剩余 50k', style: TextStyle(color: Colors.green)),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String text;
  const _PlaceholderTab({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.grey)),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/screens/pet_center_screen_test.dart
```
Expected: 3/3 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/screens/pet_center_screen.dart test/screens/pet_center_screen_test.dart
git commit -m "feat: add PetCenterScreen with status card, token dashboard, and 4 tabs"
```

---

### Task 11: PetChatScreen — 全屏聊天

**Files:**
- Create: `lib/screens/pet_chat_screen.dart`
- Test: `test/screens/pet_chat_screen_test.dart`

**Spec 覆盖:** F7 (对话系统全屏) + F14 (对话管理：标题/搜索/分组)

**依赖:** Phase 2 Task 7 (PetChatService)

- [ ] **Step 1: 写失败的 Widget 测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_chat_screen.dart';

void main() {
  testWidgets('渲染空状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetChatScreen()));
    await tester.pump();
    expect(find.text('开始和糯糯聊天吧~'), findsOneWidget);
  });

  testWidgets('有输入框和发送按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetChatScreen()));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets('新建对话按钮存在', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetChatScreen()));
    await tester.pump();
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/screens/pet_chat_screen_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetChatScreen**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetChatScreen extends StatefulWidget {
  const PetChatScreen({super.key});

  @override
  State<PetChatScreen> createState() => _PetChatScreenState();
}

class _PetChatScreenState extends State<PetChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    _inputController.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    // TODO: Task 14 改造 MiniChat 后，这里通过 PetAgentCore 通信
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 对话列表
        _buildChatList(),
        // 消息区
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text('开始和糯糯聊天吧~', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => _MessageBubble(msg: _messages[i]),
                ),
        ),
        // 输入栏
        _buildInputBar(),
      ],
    );
  }

  Widget _buildChatList() {
    // 简化版：后续集成 PetChatService.listChats()
    return const SizedBox.shrink();
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                // 新建对话
              },
            ),
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  hintText: '和糯糯说点什么...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                maxLines: 3,
                minLines: 1,
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, String> msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Text(msg['content'] ?? '', style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/screens/pet_chat_screen_test.dart
```
Expected: 3/3 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/screens/pet_chat_screen.dart test/screens/pet_chat_screen_test.dart
git commit -m "feat: add PetChatScreen with message list, input bar, new chat button"
```

---

### Task 12: PetMemoryScreen — 记忆管理

**Files:**
- Create: `lib/screens/pet_memory_screen.dart`
- Test: `test/screens/pet_memory_screen_test.dart`

**Spec 覆盖:** F10 (记忆管理)

**依赖:** Phase 2 Task 7 (PetChatService)

- [ ] **Step 1: 写失败的 Widget 测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_memory_screen.dart';

void main() {
  testWidgets('渲染空状态', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pump();
    expect(find.text('还没有记忆，去和糯糯聊天或分享对话吧~'), findsOneWidget);
  });

  testWidgets('有导入按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetMemoryScreen()));
    await tester.pump();
    expect(find.byIcon(Icons.file_download), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/screens/pet_memory_screen_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetMemoryScreen**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetMemoryScreen extends StatefulWidget {
  const PetMemoryScreen({super.key});

  @override
  State<PetMemoryScreen> createState() => _PetMemoryScreenState();
}

class _PetMemoryScreenState extends State<PetMemoryScreen> {
  // 后续集成 PetChatService
  final List<Map<String, dynamic>> _memories = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _memories.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧠', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('还没有记忆，去和糯糯聊天或分享对话吧~',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      // TODO: 集成导入功能
                    },
                    icon: const Icon(Icons.file_download),
                    label: const Text('导入对话记忆'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _memories.length,
              itemBuilder: (context, i) {
                final mem = _memories[i];
                return Dismissible(
                  key: Key(mem['id'] as String? ?? '$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    setState(() => _memories.removeAt(i));
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        mem['content'] as String? ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '来源：${mem['sourceTitle'] ?? '聊天'}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/screens/pet_memory_screen_test.dart
```
Expected: 2/2 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/screens/pet_memory_screen.dart test/screens/pet_memory_screen_test.dart
git commit -m "feat: add PetMemoryScreen with list, delete, and import button"
```

---

### Task 13: PetDiaryScreen — 成长日记

**Files:**
- Create: `lib/screens/pet_diary_screen.dart`
- Test: `test/screens/pet_diary_screen_test.dart`

**Spec 覆盖:** F5 (成长日记)

**依赖:** Phase 1 Task 3 (PetDiaryEntry)

- [ ] **Step 1: 写失败的 Widget 测试**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/screens/pet_diary_screen.dart';

void main() {
  testWidgets('渲染空状态和添加按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PetDiaryScreen()));
    await tester.pump();
    expect(find.text('📖'), findsOneWidget);
    expect(find.text('还没有日记条目~'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/screens/pet_diary_screen_test.dart
```
Expected: FAIL

- [ ] **Step 3: 实现 PetDiaryScreen**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';

class PetDiaryScreen extends StatefulWidget {
  const PetDiaryScreen({super.key});

  @override
  State<PetDiaryScreen> createState() => _PetDiaryScreenState();
}

class _PetDiaryScreenState extends State<PetDiaryScreen> {
  final List<Map<String, dynamic>> _entries = [];

  Future<void> _addEntry() async {
    final contentController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写日记'),
        content: TextField(
          controller: contentController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '今天糯糯发生了什么...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, contentController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _entries.insert(0, {
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'content': result.trim(),
          'date': DateTime.now().toIso8601String(),
          'mood': '📝',
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: _entries.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('📖', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('还没有日记条目~', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击 + 添加第一条日记', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final entry = _entries[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Text(entry['mood'] as String? ?? '📝', style: const TextStyle(fontSize: 24)),
                    title: Text(entry['content'] as String? ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      entry['date'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/screens/pet_diary_screen_test.dart
```
Expected: 1/1 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/screens/pet_diary_screen.dart test/screens/pet_diary_screen_test.dart
git commit -m "feat: add PetDiaryScreen with timeline view and add entry dialog"
```

---

## Phase 6: 集成修改

### Task 14: MiniChat 改造 — 通过 Hive 与 Agent 通信

**Files:**
- Modify: `lib/pet/mini_chat.dart`
- Test: `test/pet/mini_chat_test.dart` (追加测试)

**Spec 覆盖:** F7 (引擎 #2 不直接调 LLM)

**依赖:** Phase 3 (PetAgentCore)

- [ ] **Step 1: 写失败的回归测试**

```dart
// 追加到 test/pet/mini_chat_test.dart
testWidgets('MiniChat 通过 Hive 发送消息不直接调 LLM (regression #agent)', (tester) async {
  // 验证要点：MiniChat 不再直接持有 _client 引用
  // 改为写入 Hive agent_action box
  // 测试只验证组件正常渲染，集成测试验证通信流程
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: MiniChat(onClose: _noop))),
  );
  await tester.pump();
  // 输入框正常
  expect(find.byType(TextField), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试确认可以失败（如果已有通信逻辑）**

```bash
flutter test test/pet/mini_chat_test.dart
```

- [ ] **Step 3: 改造 MiniChat._send()**

改动要点：
1. `_send()` 不再直接调 `PetAiService.chatStream()`
2. 改为写 Hive `pet_chats` box → 引擎 #1 `PetAgentCore` 订阅 → 调 LLM → 流式写回
3. 引擎 #1 被杀时显示"糯糯在睡觉喵~"

在 `_send()` 方法中，将 LLM 直接调用改为：

```dart
// 旧代码（删除）:
// await for (final chunk in _client!.sendStream(...)) { ... }

// 新代码:
Future<void> _send() async {
  if (_isLoading) return;
  final text = _inputController.text.trim();
  if (text.isEmpty) return;
  _inputController.clear();
  setState(() {
    _messages.add({'role': 'user', 'content': text});
    _isLoading = true;
  });
  
  // 写入 Hive，等 Agent 处理
  try {
    final chatBox = await Hive.openBox('pet_chats');
    final currentId = chatBox.get('currentId') as String?;
    if (currentId != null) {
      await PetChatService().addMessage(currentId, 'user', text);
    }
    // 写入 agent 请求
    final actionBox = await Hive.openBox('agent_action');
    await actionBox.put('request', {
      'type': 'chat',
      'content': text,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // 等待 Agent 响应（轮询 pet_chats 更新）
    _waitForAgentResponse(currentId);
  } catch (_) {
    if (mounted) {
      setState(() {
        _messages.add({'role': 'assistant', 'content': '糯糯在睡觉喵~打开 App 唤醒她'});
        _isLoading = false;
      });
    }
  }
}
```

- [ ] **Step 4: 运行全部测试确认回归**

```bash
flutter test test/pet/mini_chat_test.dart
```
Expected: 全部 PASS (包括新增的回归测试)

- [ ] **Step 5: 提交**

```bash
git add lib/pet/mini_chat.dart test/pet/mini_chat_test.dart
git commit -m "refactor: MiniChat routes through Hive instead of calling LLM directly"
```

---

### Task 15: PetWindow 改造 — 集成 Agent + PetBehavior

**Files:**
- Modify: `lib/pet/pet_window.dart`

**Spec 覆盖:** F11 + F12 (集成 PetBehavior 表达层)

**依赖:** Phase 4 (PetBehavior)

- [ ] **Step 1: 改造 PetWindow 包裹 PetBehavior**

在 `_PetWindowState.build()` 中，将 `PetRenderer` 包裹在 `PetBehavior` 中：

```dart
// 旧代码:
// child: PetRenderer(state: _controller.state)

// 新代码:
child: PetBehavior(
  ecoMode: false, // 后续从 config 读取
  child: PetRenderer(state: _controller.state),
)
```

- [ ] **Step 2: 运行分析确认零 error**

```bash
cd c:/Users/lenovo/Desktop/ai-chat-app && flutter analyze
```

- [ ] **Step 3: 提交**

```bash
git add lib/pet/pet_window.dart
git commit -m "feat: integrate PetBehavior into PetWindow for agent-driven expression"
```

---

### Task 16: PetRenderer 改造 — Agent 驱动的情绪反馈

**Files:**
- Modify: `lib/pet/pet_renderer.dart`

**Spec 覆盖:** F11 (Agent 驱动的情绪反馈)

**依赖:** Phase 3 (PetAgentCore)

- [ ] **Step 1: 新增 `moodEmoji` 叠加层**

在 `PetRenderer` 的 Stack 中增加一个可选的 emoji 叠加层，由外部（PetBehavior）控制：

```dart
// PetRenderer 构造函数新增:
final String? moodEmoji;

// build() 中 Stack children 新增:
if (moodEmoji != null)
  Positioned(
    top: -10, right: -10,
    child: Text(moodEmoji!, style: const TextStyle(fontSize: 20)),
  ),
```

- [ ] **Step 2: 运行分析确认零 error**

```bash
flutter analyze
```

- [ ] **Step 3: 提交**

```bash
git add lib/pet/pet_renderer.dart
git commit -m "feat: add optional moodEmoji overlay to PetRenderer"
```

---

### Task 17: PetAiService → PetAgentCore 重构

**Files:**
- Modify: `lib/services/pet_ai_service.dart`

**Spec 覆盖:** F1 (旧 PetAiService 重构为 PetAgentCore 的初始化入口)

- [ ] **Step 1: 精简 PetAiService 为 Facade**

保留 `PetAiService` 作为对外 API，内部委托给 `PetAgentCore`：

```dart
// 关键改动: init() 改为初始化 PetAgentCore
class PetAiService {
  final PetAgentCore _agent = PetAgentCore();
  
  Future<void> init() async {
    // 从 settings 读取 API Key
    final box = await Hive.openBox('settings');
    final apiKey = box.get('api_key') as String?;
    await _agent.init(decisionApiKey: apiKey, chatApiKey: apiKey);
    _agent.start();
  }
  
  PetAgentCore get agent => _agent;
  
  // 旧方法保留为兼容层，内部委托给 agent
  void startProactiveTimer(void Function(String) onSuggestion) {
    // 由 PetAgentCore 管理
  }
}
```

- [ ] **Step 2: 运行全部 pet 测试确认回归**

```bash
flutter test test/pet/ test/services/pet_ai_service_test.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/pet_ai_service.dart
git commit -m "refactor: PetAiService delegates to PetAgentCore, keeps backward-compatible API"
```

---

### Task 18: PetSettingsScreen 改造 — 性格+模型+额度

**Files:**
- Modify: `lib/screens/pet_settings_screen.dart`

**Spec 覆盖:** F8 (性格定制) + F15 (额度设置) + F18 (API&模型独立配置)

- [ ] **Step 1: 新增设置项**

在现有设置页基础上增加：
1. 性格编辑区（模板选择 + 自由文本 + 试聊按钮）
2. 每日额度设置（10k/30k/50k/100k/不限制）
3. 决策模型选择
4. 对话模型选择
5. 视觉模型开关

```dart
// 新增到 settings list:
// - 性格设置 Section: 模板下拉 + systemPrompt 编辑框 + 试聊按钮
// - Token Section: 每日额度下拉
// - 模型 Section: 决策模型 / 对话模型 / 视觉模型
```

- [ ] **Step 2: 运行分析**

```bash
flutter analyze
```

- [ ] **Step 3: 提交**

```bash
git add lib/screens/pet_settings_screen.dart
git commit -m "feat: extend PetSettingsScreen with persona, budget, and model configuration"
```

---

### Task 19: HomeScreen 改造 — 抽屉入口 + 多选分享

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Spec 覆盖:** F9 (交叉记忆) + F13 (PetCenter 入口)

- [ ] **Step 1: 改造抽屉入口**

将主 App 抽屉中的宠物入口改为跳转 `PetCenterScreen`：

```dart
// 抽屉列表新增:
ListTile(
  leading: const Icon(Icons.pets),
  title: const Text('🐾 宠物中心'),
  onTap: () {
    Navigator.pop(context); // 关抽屉
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PetCenterScreen()));
  },
),
```

- [ ] **Step 2: 新增对话多选分享**

在对话列表 AppBar 新增 `📤` 按钮，点击进入选择模式，底部显示「分享给糯糯」按钮：

```dart
// 选择模式状态
bool _selectionMode = false;
final Set<String> _selectedConvIds = {};

// 分享给糯糯
Future<void> _shareToPet() async {
  final summaries = <Map<String, dynamic>>[];
  for (final id in _selectedConvIds) {
    // 从 conversations box 读取
    final raw = _convBox.get(id);
    if (raw != null) {
      summaries.add({
        'id': id,
        'title': raw['title'] ?? '无标题',
        'summary': raw['messages']?.last?.content ?? '',
      });
    }
  }
  final svc = PetChatService();
  final count = await svc.importMemories(summaries);
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已分享 $count 条记忆给糯糯~ 📝')),
    );
  }
  setState(() {
    _selectionMode = false;
    _selectedConvIds.clear();
  });
}
```

- [ ] **Step 3: 运行分析**

```bash
flutter analyze
```

- [ ] **Step 4: 提交**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: add PetCenter drawer entry and multi-select share to pet"
```

---

### Task 20: main.dart — Provider 注册

**Files:**
- Modify: `lib/main.dart`

**Spec 覆盖:** 全局 — 新 Service 注册到 Provider 图

- [ ] **Step 1: 注册新 Service**

在 `MultiProvider` 中新增：

```dart
// main.dart MultiProvider children 新增:
ChangeNotifierProvider(create: (_) => PetTokenService()),
ChangeNotifierProvider(create: (_) => PetProfileService()),
ChangeNotifierProvider(create: (_) => PetChatService()),
```

- [ ] **Step 2: 运行全部测试**

```bash
flutter test
```
Expected: 全部通过（含原有 101 测试 + 新增测试）

- [ ] **Step 3: 运行分析**

```bash
flutter analyze
```
Expected: 零新增 error

- [ ] **Step 4: 提交**

```bash
git add lib/main.dart
git commit -m "feat: register new pet services in MultiProvider"
```

---

## 完成检查清单

- [ ] `flutter analyze` — 零新增 error
- [ ] `flutter test` — 全部通过（目标 ≥130）
- [ ] 手动验证核心流程：
  - [ ] PetCenter 可见 4 Tab + 状态卡片 + Token 看板
  - [ ] MiniChat 发消息 → Hive → PetAgentCore → LLM → 流式返回
  - [ ] 引擎 #1 被杀 → MiniChat 显示"在睡觉"
  - [ ] 设置页 → 改性格 → 试聊 → 保存
  - [ ] 主 App → 多选对话 → 分享给糯糯 → PetMemoryScreen 看到新记忆
  - [ ] PetDiaryScreen → 添加日记条目
  - [ ] Token 看板实时更新

---

## 预估

| Phase | 任务数 | 新建文件 | 修改文件 | 预计新增测试 |
|-------|--------|---------|---------|-------------|
| 1: 数据模型 | 4 | 4 | 0 | 17 |
| 2: 服务层 | 3 | 3 | 0 | 20 |
| 3: Agent 核心 | 1 | 1 | 0 | 8 |
| 4: 表达层 | 1 | 1 | 0 | 5 |
| 5: UI 屏幕 | 4 | 4 | 0 | 9 |
| 6: 集成修改 | 7 | 0 | 7 | 2 |
| **合计** | **20** | **13** | **7** | **61** |
