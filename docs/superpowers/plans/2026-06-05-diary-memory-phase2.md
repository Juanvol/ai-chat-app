# Diary/Memory/Persona Phase 2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 2 — LLM 日总结 + 记忆 LLM 整理 + 日记/记忆/人格 UI + D8 ContextCollector 接入

**Architecture:** 在 Phase 1 数据层之上，添加 LLM 能力（DiarySummarizer、MemoryOrganizer）通过 LLMClient.send() 调用，升级三个 UI 屏幕对接新的 KnowledgeBase 数据源，将 KnowledgeBase 注入 D8 上下文收集管道。

**Tech Stack:** Flutter 3.24 / Dart 3.5, Hive, LLMClient (Dio → OpenAI-compatible endpoint)

---

### Task 1: DiarySummarizer — LLM 日总结

**Files:**
- Create: `lib/services/pet/knowledge/diary/diary_summarizer.dart`
- Modify: `lib/services/pet/knowledge/diary/diary_store.dart:152-158` (replace `summarizeDay` stub)

- [ ] **Step 1: 创建 DiarySummarizer**

```dart
// Flutter 3.24 / Dart 3.5
import '../../../api/deepseek_client.dart';
import '../../pet_logger.dart';
import '../models/diary_entry.dart';

class DiarySummarizer {
  final LLMClient _client;
  final String _model;

  DiarySummarizer({LLMClient? client, String model = 'deepseek-v4-pro'})
      : _client = client ?? LLMClient(),
        _model = model;

  /// 生成今日日记总结，返回 null 表示跳过（无事件或预算不足）
  Future<DiaryEntry?> summarize({
    required String dateKey,
    required List<DiaryEntry> todayEvents,
    required int remainingBudget,
    required String personaPrompt,
  }) async {
    // 过滤出今日的事件 + 高亮
    final sourceEvents = todayEvents
        .where((e) => e.type != DiaryEntryType.summary)
        .toList();
    if (sourceEvents.isEmpty) return null;

    // 预算门控：至少需要 300 tok
    if (remainingBudget < 300) {
      PetLogger().trace('DiarySummarizer',
          'skip: remaining budget $remainingBudget < 300');
      return null;
    }

    // 构造事件列表
    final eventLines = sourceEvents.map((e) {
      final time = '${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}';
      return '$time ${e.mood} ${e.content}';
    }).join('\n');

    final prompt = '''${personaPrompt}

请用糯糯第一人称的语气，以"糯糯的日记"为题，写一篇今日总结日记。
今天的事件记录如下：
$eventLines

要求：
- 不超过150字
- 语气软萌、温暖
- 包含今天的心情总结
- 如果有高亮事件，重点提及''';

    try {
      final result = await _client.send(
        history: [],
        userContent: prompt,
        model: _model,
        maxTokens: 256,
        thinkingEnabled: false,
      );

      final content = result.content.trim();
      if (content.isEmpty) return null;

      return DiaryEntry(
        id: 'summary_${dateKey}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        type: DiaryEntryType.summary,
        content: content,
        mood: '📔',
        sourceType: 'summary',
        date: DateTime.now(),
        dateKey: DateTime.tryParse('$dateKey 00:00:00'),
      );
    } catch (e) {
      PetLogger().error('DiarySummarizer', 'LLM call failed', e);
      return null;
    }
  }
}
```

- [ ] **Step 2: 实现 DiaryStore.summarizeDay**

修改 `lib/services/pet/knowledge/diary/diary_store.dart`，替换 `summarizeDay` stub：

```dart
// Flutter 3.24 / Dart 3.5
// 在 DiaryStore 中添加字段：
final DiarySummarizer _summarizer;
final PetTokenService? _tokenService;
String _personaPrompt = ''; // 由 KnowledgeBase 设置

// 修改构造函数，添加可选参数：
DiaryStore({
  required IDiaryRepository repo,
  this.onEventRecorded,
  DiarySummarizer? summarizer,
  PetTokenService? tokenService,
})  : _repo = repo,
      _summarizer = summarizer ?? DiarySummarizer(),
      _tokenService = tokenService;

// 替换 summarizeDay stub：
Future<DiaryEntry?> summarizeDay(DateTime date) async {
  final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final todayEvents = await _repo.loadByDate(date);

  // 检查是否已有总结
  final existing = todayEvents
      .where((e) => e.type == DiaryEntryType.summary)
      .firstOrNull;
  if (existing != null) return existing;

  final remaining = _tokenService?.getBudgetRemaining() ?? 999999;

  final summary = await _summarizer.summarize(
    dateKey: dateKey,
    todayEvents: todayEvents,
    remainingBudget: remaining,
    personaPrompt: _personaPrompt,
  );

  if (summary != null) {
    await _repo.save(summary);
    PetLogger().trace('DiaryStore', 'summary: ${summary.content}');
  }

  return summary;
}

/// 设置人格提示词（供 KnowledgeBase 调用）
void setPersonaPrompt(String prompt) {
  _personaPrompt = prompt;
}
```

- [ ] **Step 3: 更新 KnowledgeBase 注入 TokenService + Persona**

修改 `lib/services/pet/knowledge/knowledge_base.dart`：

```dart
// KnowledgeBase 构造函数添加 tokenService 和 persona 提示词
KnowledgeBase({
  required this.diaryStore,
  required this.memoryStore,
  required IDiaryRepository diaryRepo,
  required IMemoryRepository memoryRepo,
  PetPersona? persona,
  PetTokenService? tokenService,
})  : _diaryRepo = diaryRepo,
      _memoryRepo = memoryRepo,
      _persona = persona {
    // 注入 tokenService 到 diaryStore
    diaryStore.setPersonaPrompt(persona?.buildSystemPrompt() ?? 
        PetPersona().buildSystemPrompt());
  }

/// 更新人格（同时更新 diary summarizer 的提示词）
void updatePersona(PetPersona persona) {
  _persona = persona;
  diaryStore.setPersonaPrompt(persona.buildSystemPrompt());
}
```

- [ ] **Step 4: 更新 PetOverlayController 初始化传入 TokenService**

修改 `lib/services/pet/pet_overlay_host.dart:173-198`，在 KnowledgeBase 初始化时传入 tokenService：

```dart
// 找到 KnowledgeBase 初始化处，添加：
_knowledgeBase = KnowledgeBase(
  diaryStore: diaryStore,
  memoryStore: memoryStore,
  diaryRepo: diaryRepo,
  memoryRepo: memoryRepo,
  tokenService: PetTokenService.instance,  // ← 新增
);
```

- [ ] **Step 5: flutter analyze 验证**

Run: `flutter analyze lib/services/pet/knowledge/`

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/services/pet/knowledge/diary/diary_summarizer.dart \
        lib/services/pet/knowledge/diary/diary_store.dart \
        lib/services/pet/knowledge/knowledge_base.dart \
        lib/services/pet/pet_overlay_host.dart
git commit -m "feat: DiarySummarizer — LLM 日总结 + TokenService 注入"
```

---

### Task 2: MemoryOrganizer — LLM 记忆批量整理

**Files:**
- Create: `lib/services/pet/knowledge/memory/memory_organizer.dart`
- Modify: `lib/services/pet/knowledge/memory/memory_store.dart:55-63` (replace `organizeIfNeeded` stub)

- [ ] **Step 1: 创建 MemoryOrganizer**

```dart
// Flutter 3.24 / Dart 3.5
import 'dart:convert';
import '../../../api/deepseek_client.dart';
import '../../pet_logger.dart';
import '../models/memory_entry.dart';

class MemoryOrganizer {
  final LLMClient _client;
  final String _model;

  MemoryOrganizer({LLMClient? client, String model = 'deepseek-v4-pro'})
      : _client = client ?? LLMClient(),
        _model = model;

  /// 整理记忆：去重/合并/调整重要性/标记过期
  /// 返回 (更新列表, 删除id列表)
  Future<({List<MemoryEntry> toUpdate, List<String> toDelete})> organize({
    required List<MemoryEntry> existingMemories,
    required int remainingBudget,
  }) async {
    if (existingMemories.isEmpty) return (toUpdate: [], toDelete: []);

    if (remainingBudget < 500) {
      PetLogger().trace('MemoryOrganizer',
          'skip: remaining budget $remainingBudget < 500');
      return (toUpdate: [], toDelete: []);
    }

    // 构造输入：每条记忆一行
    final memoryLines = existingMemories
        .where((m) => m.source == MemorySource.rule) // 仅整理规则提取的记忆
        .map((m) => '- [${m.tag.name}] ${m.content} (重要性:${m.importance.toStringAsFixed(1)}, id:${m.id})')
        .join('\n');

    if (memoryLines.isEmpty) return (toUpdate: [], toDelete: []);

    final prompt = '''你是糯糯的记忆管理助手。以下是糯糯通过规则自动提取的观察片段：

$memoryLines

请分析并输出 JSON：
{
  "toUpdate": [
    {"id": "mem_xxx", "content": "合并后的内容", "tag": "habit", "importance": 0.8}
  ],
  "toDelete": ["mem_yyy"]
}

规则：
1. 相似记忆合并为一条（如"深夜工作"出现多次→合并为一条habit）
2. 重要性调整：常用/重要的标0.7+，边缘信息标0.3以下
3. 过时记忆：如果内容明显不再准确，加入toDelete
4. 仅对规则提取的记忆做操作，不要创造全新记忆''';

    try {
      final result = await _client.send(
        history: [],
        userContent: prompt,
        model: _model,
        maxTokens: 512,
        thinkingEnabled: false,
      );

      final parsed = _parseJson(result.content);
      final toUpdate = (parsed['toUpdate'] as List<dynamic>?)
              ?.map((m) {
                final id = (m as Map)['id'] as String? ?? '';
                final existing = existingMemories.where((e) => e.id == id).firstOrNull;
                if (existing == null) return null;
                return existing.copyWith(
                  content: m['content'] as String?,
                  tag: _parseTag(m['tag'] as String?),
                  importance: (m['importance'] as num?)?.toDouble(),
                  source: MemorySource.llm,
                  updatedAt: DateTime.now(),
                );
              })
              .whereType<MemoryEntry>()
              .toList() ??
          [];
      final toDelete = (parsed['toDelete'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      return (toUpdate: toUpdate, toDelete: toDelete);
    } catch (e) {
      PetLogger().error('MemoryOrganizer', 'LLM call or parse failed', e);
      return (toUpdate: [], toDelete: []);
    }
  }

  MemoryTag _parseTag(String? tag) {
    return MemoryTag.values.firstWhere(
      (e) => e.name == tag,
      orElse: () => MemoryTag.fact,
    );
  }

  Map<String, dynamic> _parseJson(String text) {
    try {
      // 提取 JSON 块（可能包裹在 markdown 代码块中）
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      final jsonStr = jsonMatch?.group(0) ?? text;
      return Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    } catch (_) {
      return {};
    }
  }
}
```

- [ ] **Step 2: 实现 MemoryStore.organizeIfNeeded**

修改 `lib/services/pet/knowledge/memory/memory_store.dart`，替换 `organizeIfNeeded` stub：

```dart
// 在 MemoryStore 类中添加字段：
final MemoryOrganizer _organizer;

// 修改构造函数：
MemoryStore({
  required IMemoryRepository repo,
  MemoryExtractor? extractor,
  MemoryOrganizer? organizer,
  IDiaryRepository? diaryRepo,
  PetTokenService? tokenService,
})  : _repo = repo,
      _extractor = extractor ?? MemoryExtractor(),
      _organizer = organizer ?? MemoryOrganizer(),
      _diaryRepo = diaryRepo,
      _tokenService = tokenService;

// 替换 organizeIfNeeded stub：
Future<void> organizeIfNeeded() async {
  // 每3天检查一次
  if (_lastOrganizeAt != null &&
      DateTime.now().difference(_lastOrganizeAt!).inDays < 3) {
    return;
  }

  final remaining = _tokenService?.getBudgetRemaining() ?? 0;
  if (remaining < 500) {
    PetLogger().trace('MemoryStore',
        'organizeIfNeeded skip: budget $remaining < 500');
    return;
  }

  final existing = await _repo.loadAll();
  final result = await _organizer.organize(
    existingMemories: existing,
    remainingBudget: remaining,
  );

  // 更新记忆
  if (result.toUpdate.isNotEmpty) {
    await _repo.saveAll(result.toUpdate);
    PetLogger().info('MemoryStore',
        'organize: updated ${result.toUpdate.length} memories');
  }

  // 删除过期记忆
  for (final id in result.toDelete) {
    await _repo.delete(id);
    PetLogger().info('MemoryStore', 'organize: deleted $id');
  }

  _lastOrganizeAt = DateTime.now();
}
```

- [ ] **Step 3: 更新 pet_overlay_host.dart 传入 TokenService 到 MemoryStore**

```dart
// 修改 MemoryStore 初始化（lib/services/pet/pet_overlay_host.dart:179-182）：
final memoryStore = MemoryStore(
  repo: memoryRepo,
  diaryRepo: diaryRepo,
  tokenService: PetTokenService.instance,  // ← 新增
);
```

- [ ] **Step 4: 添加 organizeIfNeeded 的定时调用**

在 `PetOverlayController.start()` 中，`_startBrainLoop()` 之后添加：

```dart
// 每3天记忆整理检查（首次在start后5分钟触发）
Future.delayed(const Duration(minutes: 5), () {
  _knowledgeBase?.memoryStore.organizeIfNeeded();
});
```

- [ ] **Step 5: flutter analyze 验证**

Run: `flutter analyze lib/services/pet/knowledge/`

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/services/pet/knowledge/memory/memory_organizer.dart \
        lib/services/pet/knowledge/memory/memory_store.dart \
        lib/services/pet/pet_overlay_host.dart
git commit -m "feat: MemoryOrganizer — LLM 记忆批量整理（每3天）"
```

---

### Task 3: 日记列表 UI — 对接新 KnowledgeBase

**Files:**
- Modify: `lib/screens/pet/pet_diary_screen.dart` (full rewrite)

- [ ] **Step 1: 重写 PetDiaryScreen 使用 KnowledgeBase**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/knowledge_base.dart';
import '../../services/pet/knowledge/models/diary_entry.dart';
import '../../config/theme.dart';

class PetDiaryScreen extends StatefulWidget {
  final KnowledgeBase? knowledgeBase;

  const PetDiaryScreen({super.key, this.knowledgeBase});

  @override
  State<PetDiaryScreen> createState() => _PetDiaryScreenState();
}

class _PetDiaryScreenState extends State<PetDiaryScreen> {
  List<DiaryEntry> _entries = [];
  bool _loading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final kb = widget.knowledgeBase;
    if (kb == null) return;

    setState(() => _loading = true);

    if (_selectedDate != null) {
      _entries = await kb.diaryStore.loadByDate(_selectedDate!);
    } else {
      _entries = await kb.getRecentDiary(days: 30);
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.knowledgeBase == null) {
      return const Center(child: Text('知识库未初始化'));
    }

    return Column(
      children: [
        // 日期选择栏
        _buildDatePicker(),
        // 条目列表
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? _buildEmpty()
                : _buildEntryList()),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                _selectedDate = picked;
                _loadEntries();
              }
            },
          ),
          if (_selectedDate != null)
            Chip(
              label: Text('${_selectedDate!.year}-${_selectedDate!.month}-${_selectedDate!.day}'),
              onDeleted: () {
                _selectedDate = null;
                _loadEntries();
              },
            )
          else
            const Chip(label: Text('最近30天')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        _selectedDate != null ? '这天还没有日记' : '还没有日记~ 和糯糯互动就会自动记日记喵~',
        style: TextStyle(color: C.scheme.onSurface.withAlpha(128)),
      ),
    );
  }

  Widget _buildEntryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) => _buildEntryCard(_entries[index]),
    );
  }

  Widget _buildEntryCard(DiaryEntry entry) {
    final isHighlight = entry.type == DiaryEntryType.highlight;
    final isSummary = entry.type == DiaryEntryType.summary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isHighlight
          ? C.scheme.primaryContainer.withAlpha(80)
          : isSummary
              ? C.scheme.secondaryContainer.withAlpha(80)
              : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.mood, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.content,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSummary ? FontWeight.bold : FontWeight.normal,
                      color: C.scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.date.hour.toString().padLeft(2, '0')}:${entry.date.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: C.scheme.onSurface.withAlpha(128),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 更新 PetCenterScreen 传入 KnowledgeBase**

修改日记 Tab，传入 KnowledgeBase。先不改 PetCenterScreen 的 Tab 结构，在 PetDiaryScreen 中通过全局 `petOverlayController` 访问 KnowledgeBase。

编辑 `lib/screens/pet/pet_diary_screen.dart` 顶部，使用 petOverlayController：

```dart
// 在 PetDiaryScreen 的 _PetDiaryScreenState._loadEntries 改为：
Future<void> _loadEntries() async {
  // 通过全局 petOverlayController 获取知识库
  final kb = (petOverlayController as dynamic)._knowledgeBase as KnowledgeBase?;
  // ... rest unchanged
}
```

⚠️ 不优雅但可行。在 Task 6（D8 ContextCollector）中会正式解决注入问题。

- [ ] **Step 3: flutter analyze 验证**

Run: `flutter analyze lib/screens/pet/pet_diary_screen.dart`

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/pet/pet_diary_screen.dart
git commit -m "feat: 日记列表 UI 对接 KnowledgeBase — 日期选择+高亮+总结卡片"
```

---

### Task 4: 记忆管理 UI — 列表/编辑/删除/手动添加

**Files:**
- Modify: `lib/screens/pet/pet_memory_screen.dart` (full rewrite)

- [ ] **Step 1: 重写 PetMemoryScreen 使用 MemoryStore**

```dart
// Flutter 3.24 / Dart 3.5
import 'package:flutter/material.dart';
import '../../services/pet/knowledge/memory/memory_store.dart';
import '../../services/pet/knowledge/models/memory_entry.dart';
import '../../config/theme.dart';

class PetMemoryScreen extends StatefulWidget {
  final MemoryStore? memoryStore;

  const PetMemoryScreen({super.key, this.memoryStore});

  @override
  State<PetMemoryScreen> createState() => _PetMemoryScreenState();
}

class _PetMemoryScreenState extends State<PetMemoryScreen> {
  List<MemoryEntry> _memories = [];
  MemoryTag? _filterTag;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    final ms = widget.memoryStore;
    if (ms == null) return;

    setState(() => _loading = true);
    _memories = await ms.loadAll(tag: _filterTag);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.memoryStore == null) {
      return const Center(child: Text('记忆服务未初始化'));
    }

    return Column(
      children: [
        // 标签筛选栏
        _buildTagFilter(),
        // 记忆列表
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _memories.isEmpty
                ? _buildEmpty()
                : _buildMemoryList()),
        // FAB：手动添加
      ],
    );
  }

  Widget _buildTagFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _filterTag == null,
            onSelected: (_) { _filterTag = null; _loadMemories(); },
          ),
          const SizedBox(width: 8),
          ...MemoryTag.values.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_tagLabel(tag)),
              selected: _filterTag == tag,
              onSelected: (selected) {
                _filterTag = selected ? tag : null;
                _loadMemories();
              },
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        '还没有记忆~ 多和糯糯互动，糯糯会慢慢了解主人喵~',
        style: TextStyle(color: C.scheme.onSurface.withAlpha(128)),
      ),
    );
  }

  Widget _buildMemoryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _memories.length,
      itemBuilder: (context, index) => _buildMemoryCard(_memories[index]),
    );
  }

  Widget _buildMemoryCard(MemoryEntry memory) {
    final importanceColor = memory.importance > 0.7
        ? Colors.amber
        : memory.importance > 0.4
            ? Colors.grey
            : Colors.grey.withAlpha(100);

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: C.scheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除记忆'),
            content: Text('确定删除「${memory.content}」？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
            ],
          ),
        );
      },
      onDismissed: (_) {
        widget.memoryStore?.deleteMemory(memory.id);
        _loadMemories();
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => _editMemory(memory),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 重要性星标
                Icon(
                  memory.importance > 0.7 ? Icons.star : Icons.star_border,
                  color: importanceColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                // 标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _tagColor(memory.tag).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _tagLabel(memory.tag),
                    style: TextStyle(fontSize: 11, color: _tagColor(memory.tag)),
                  ),
                ),
                const SizedBox(width: 8),
                // 内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(memory.content, style: const TextStyle(fontSize: 14)),
                      if (memory.source == MemorySource.llm)
                        Text('AI整理', style: TextStyle(fontSize: 10, color: C.scheme.onSurface.withAlpha(100))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 编辑记忆 Dialog
  Future<void> _editMemory(MemoryEntry memory) async {
    final contentCtrl = TextEditingController(text: memory.content);
    final importanceCtrl = TextEditingController(text: memory.importance.toStringAsFixed(1));
    MemoryTag selectedTag = memory.tag;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MemoryTag>(
                value: selectedTag,
                items: MemoryTag.values.map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(_tagLabel(t)),
                )).toList(),
                onChanged: (v) { if (v != null) selectedTag = v; },
                decoration: const InputDecoration(labelText: '分类'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: importanceCtrl,
                decoration: const InputDecoration(labelText: '重要性 (0.0-1.0)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'content': contentCtrl.text,
            'tag': selectedTag,
            'importance': double.tryParse(importanceCtrl.text) ?? memory.importance,
          }), child: const Text('保存')),
        ],
      ),
    );

    if (result != null && mounted) {
      await widget.memoryStore?.updateMemory(
        memory.id,
        content: result['content'] as String,
        tag: result['tag'] as MemoryTag,
        importance: result['importance'] as double,
      );
      _loadMemories();
    }
  }

  /// 手动添加记忆
  Future<void> _addMemory() async {
    final contentCtrl = TextEditingController();
    MemoryTag selectedTag = MemoryTag.fact;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              decoration: const InputDecoration(labelText: '内容', hintText: '主人喜欢喝咖啡'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MemoryTag>(
              value: selectedTag,
              items: MemoryTag.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(_tagLabel(t)),
              )).toList(),
              onChanged: (v) { if (v != null) selectedTag = v; },
              decoration: const InputDecoration(labelText: '分类'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'content': contentCtrl.text,
              'tag': selectedTag,
            }),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      await widget.memoryStore?.addMemory(
        result['content'] as String,
        result['tag'] as MemoryTag,
      );
      _loadMemories();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Override build to include FAB
    return Scaffold(
      body: Column(
        children: [
          _buildTagFilter(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_memories.isEmpty) return _buildEmpty();
    return _buildMemoryList();
  }

  String _tagLabel(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => '事实',
    MemoryTag.habit => '习惯',
    MemoryTag.interest => '兴趣',
    MemoryTag.event => '事件',
    MemoryTag.reminder => '提醒',
  };

  Color _tagColor(MemoryTag tag) => switch (tag) {
    MemoryTag.fact => Colors.blue,
    MemoryTag.habit => Colors.orange,
    MemoryTag.interest => Colors.green,
    MemoryTag.event => Colors.purple,
    MemoryTag.reminder => Colors.red,
  };
}
```

- [ ] **Step 2: flutter analyze 验证**

Run: `flutter analyze lib/screens/pet/pet_memory_screen.dart`

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pet/pet_memory_screen.dart
git commit -m "feat: 记忆管理 UI — 标签筛选+编辑+删除+手动添加"
```

---

### Task 5: 人格设置 UI — traits 滑块 + 风格选择

**Files:**
- Modify: `lib/screens/pet/pet_settings_screen.dart` (add new section after existing persona template)

- [ ] **Step 1: 在 PetSettingsScreen 中添加 personalityTraits 滑块**

在 `lib/screens/pet/pet_settings_screen.dart` 的性格设置区域（`_promptController` 的 TextField 之前）插入：

```dart
// ═══ 性格维度滑块 ═══
const SizedBox(height: 16),
Text('性格维度', style: C.body),
const SizedBox(height: 8),
_TraitSlider(
  label: '活力',
  subtitle: '${_traits.energy.toStringAsFixed(1)}',
  value: _traits.energy,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(energy: v)),
),
_TraitSlider(
  label: '好奇心',
  subtitle: '${_traits.curiosity.toStringAsFixed(1)}',
  value: _traits.curiosity,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(curiosity: v)),
),
_TraitSlider(
  label: '粘人度',
  subtitle: '${_traits.clinginess.toStringAsFixed(1)}',
  value: _traits.clinginess,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(clinginess: v)),
),
_TraitSlider(
  label: '傲娇度',
  subtitle: '${_traits.tsundere.toStringAsFixed(1)}',
  value: _traits.tsundere,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(tsundere: v)),
),
_TraitSlider(
  label: '共情力',
  subtitle: '${_traits.empathy.toStringAsFixed(1)}',
  value: _traits.empathy,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(empathy: v)),
),
_TraitSlider(
  label: '幽默感',
  subtitle: '${_traits.humor.toStringAsFixed(1)}',
  value: _traits.humor,
  onChanged: (v) => setState(() => _traits = _traits.copyWith(humor: v)),
),

// ═══ 说话风格 ═══
const SizedBox(height: 16),
Text('说话风格', style: C.body),
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      child: TextField(
        controller: _selfRefCtrl,
        decoration: const InputDecoration(labelText: '自称', helperText: '如"糯糯"、"本喵"'),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: TextField(
        controller: _endingCtrl,
        decoration: const InputDecoration(labelText: '句尾', helperText: '如"喵~"、"汪!"'),
      ),
    ),
  ],
),
const SizedBox(height: 12),
Row(
  children: [
    Expanded(
      child: Text('句子长度: ${_maxLen.round()}字'),
    ),
    Slider(
      value: _maxLen.toDouble(),
      min: 40,
      max: 200,
      onChanged: (v) => setState(() => _maxLen = v.round()),
    ),
  ],
),
```

需要在 `_PetSettingsScreenState` 中添加状态变量：

```dart
// 在已有的 _persona 字段附近添加：
PersonalityTraits _traits = PersonalityTraits.balanced;
SpeakingStyle _style = SpeakingStyle.defaultCat;
late TextEditingController _selfRefCtrl;
late TextEditingController _endingCtrl;
int _maxLen = 80;

// 在 initState 中初始化：
@override
void initState() {
  super.initState();
  // ... existing init ...
  _selfRefCtrl = TextEditingController(text: _persona.style.selfReference);
  _endingCtrl = TextEditingController(text: _persona.style.sentenceEnding);
  _maxLen = _persona.style.maxSentenceLength;
  _traits = _persona.personalityTraits;
}

// 在 _savePersona 中更新：
Future<void> _savePersona(PetPersona p) async {
  final updated = p.copyWith(
    personalityTraits: _traits,
    style: p.style.copyWith(
      selfReference: _selfRefCtrl.text,
      sentenceEnding: _endingCtrl.text,
      maxSentenceLength: _maxLen,
    ),
  );
  // ... existing save logic with updated instead of p ...
}
```

- [ ] **Step 2: 创建 _TraitSlider 组件**

在文件末尾添加：

```dart
// Flutter 3.24 / Dart 3.5
class _TraitSlider extends StatelessWidget {
  final String label;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;

  const _TraitSlider({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(subtitle, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: flutter analyze 验证**

Run: `flutter analyze lib/screens/pet/pet_settings_screen.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/screens/pet/pet_settings_screen.dart
git commit -m "feat: 人格设置 UI — 6维性格滑块 + 说话风格配置"
```

---

### Task 6: D8 ContextCollector 接入 KnowledgeBase

**Files:**
- Modify: `lib/services/pet/pet_overlay_host.dart:40` (添加公开 getter)
- No new files (D8 engine 在 Phase 3)

- [ ] **Step 1: 为 PetOverlayController 添加 KnowledgeBase 公开访问**

修改 `lib/services/pet/pet_overlay_host.dart`，在类定义中添加：

```dart
class PetOverlayController {
  // ... existing fields ...

  /// 公开知识库访问（供 UI 和 D8 ContextCollector 使用）
  KnowledgeBase? get knowledgeBase => _knowledgeBase;

  // ... rest unchanged ...
}
```

- [ ] **Step 2: 更新 PetCenterScreen 通过 petOverlayController 注入 MemoryStore/KnowledgeBase**

修改 `lib/screens/pet/pet_center_screen.dart` 的 Tab 构建，将 KnowledgeBase 和 MemoryStore 传入新的 UI：

```dart
// 在 TabBarView 中：
TabBarView(
  children: [
    PetChatScreen(...),
    PetMemoryScreen(
      memoryStore: petOverlayController.knowledgeBase?.memoryStore,
    ),
    PetDiaryScreen(
      knowledgeBase: petOverlayController.knowledgeBase,
    ),
    PetSettingsScreen(...),
  ],
)
```

- [ ] **Step 3: flutter analyze 验证**

Run: `flutter analyze lib/screens/pet/pet_center_screen.dart lib/services/pet/pet_overlay_host.dart`

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/services/pet/pet_overlay_host.dart lib/screens/pet/pet_center_screen.dart
git commit -m "feat: D8 ContextCollector 接入 — KnowledgeBase 公开访问 + UI 注入"
```

---

### Task 7: 综合验证 + 编译

- [ ] **Step 1: 全量 flutter analyze**

Run: `flutter analyze`

Expected: 0 errors（仅有既存 warning/info）

- [ ] **Step 2: 运行已有测试**

Run: `flutter test test/pet/pet_persona_test.dart`

Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: Phase 2 综合验证 — analyze 0 errors + tests pass"
```
