// Flutter 3.24 / Dart 3.5
import 'dart:math';
import 'pet_brain.dart';

class PetBubbleManager {
  final _rng = Random();
  final _cooldowns = <String, DateTime>{};
  static const _cooldownDuration = Duration(minutes: 2);
  final _lastPick = <String, String>{};

  int get totalCount => _morning.length + _daytime.length + _evening.length +
      _night.length + _hungry.length + _sleepy.length +
      _affection.length + _pokeReactions.length + _surprise.length;

  // ── 时段问候 ──
  static const _morning = [
    '早安~☀️', '新的一天喵！', '主人起床了~', '今天天气不错喵~',
    '早上好！糯糯等你很久了~', '又是元气满满的一天！', '主人今天有什么计划喵？',
    '早起的鸟儿有虫吃~', '糯糯刚醒...还有点困💤', '要加油哦今天！',
  ];

  static const _daytime = [
    '主人在干嘛喵？', '好无聊...', '戳戳我试试喵~', '嗯？有东西在动？',
    '糯糯在想你呢...', '看到主人就开心~ 😸', '摸摸我好嘛...', '喵？那是啥？',
    '主人辛苦了~ ☕', '糯糯会一直陪着你的~',
  ];

  static const _evening = [
    '主人一天辛苦了~', '该休息一下了喵~', '抱抱~', '和糯糯聊聊天叭~',
    '主人今天过得好吗？', '糯糯最喜欢主人了~', '主人笑起来最好看了~',
    '今天想和主人聊天~', '糯糯在这里等你~', '辛苦一天了，放松一下喵~',
  ];

  static const _night = [
    '夜深了，安静陪你~🌙', '主人还不睡吗？', '好困...💤', '晚安喵~',
    '明天见~', '做个好梦喵~', '糯糯先睡了...zzZ', '晚上冷，记得盖被子~',
    '熬夜不好哦...', '主人也早点休息吧~',
  ];

  // ── 状态表达 ──
  static const _hungry = [
    '有点饿了喵~ 🍖', '想吃东西...', '主人有没有零食？', '肚子在叫了...',
    '好饿好饿！', '糯糯想吃鱼~', '该喂糯糯了喵~', '闻到好吃的味道了！',
    '主人~糯糯饿了~', '有没有小鱼干？',
  ];

  static const _sleepy = [
    '糯糯好困...💤', '眼睛睁不开了...', '好想睡觉喵~', 'zzZ...啊！没睡着！',
    '主人我眯一会...', '困到转圈圈...', '电量不足，需要充电💤', '打个哈欠...🥱',
  ];

  // ── 撒娇 ──
  static const _affection = [
    '抱抱~', '主人最好了~ 😸', '糯糯最喜欢主人了~', '想要被摸摸头...',
    '主人~陪糯糯玩嘛~', '不要走...', '喵~抓到你了！', '蹭蹭主人~',
    '主人身上好暖和~', '粘着你！', '只给主人一个人喵~', '嘻嘻~',
    '主人好温柔~', '和主人在一起最开心了~', '想一直被主人抱着~',
  ];

  // ── 回应戳 ──
  static const _pokeReactions = [
    '啊！', '喵~', '干嘛啦', '嗯哼？', '哎呀！', '嘻嘻~', '抓到你了！',
    '戳我干嘛~', '别戳了喵~', '好痒！', '哼！', '再戳生气了哦！',
  ];

  // ── 惊喜（稀有） ──
  static const _surprise = [
    '今天是糯糯的生日喵~🎂', '和主人认识100天啦！', '糯糯今天超开心！✨',
    '啦啦啦~ 🎵', '心情超好喵！', '转圈圈~', '今天是个好日子~',
    '糯糯学会新技能了！', '主人主人！快看我！', '今天运气真好~🍀',
  ];

  /// 根据分类和时段选取气泡。冷却期内返回 null。
  String? pick({String category = 'daytime', DayPeriod period = DayPeriod.afternoon}) {
    // 冷却检查
    if (_cooldowns.containsKey(category)) {
      if (DateTime.now().difference(_cooldowns[category]!) < _cooldownDuration) {
        return null;
      }
    }

    final pool = _getPool(category, period);
    if (pool.isEmpty) return null;

    // 避免连续相同
    String bubble;
    var attempts = 0;
    do {
      bubble = pool[_rng.nextInt(pool.length)];
      attempts++;
    } while (bubble == _lastPick[category] && attempts < 5);

    _lastPick[category] = bubble;
    _cooldowns[category] = DateTime.now();
    return bubble;
  }

  List<String> _getPool(String category, DayPeriod period) {
    switch (category) {
      case 'greeting':
        return switch (period) {
          DayPeriod.morning => _morning,
          DayPeriod.night => _night,
          DayPeriod.evening => _evening,
          _ => _daytime,
        };
      case 'hungry': return _hungry;
      case 'sleepy': return _sleepy;
      case 'affection': return _affection;
      case 'poke': return _pokeReactions;
      case 'surprise': return _surprise;
      default: return _daytime;
    }
  }

  void resetCooldown(String category) => _cooldowns.remove(category);
  void resetAllCooldowns() => _cooldowns.clear();
}
