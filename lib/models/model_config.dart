class ModelProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String keyLabel;
  String apiKey;
  bool enabled;

  ModelProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.keyLabel = 'API Key',
    this.apiKey = '',
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'baseUrl': baseUrl,
        'apiKey': apiKey, 'enabled': enabled,
      };

  factory ModelProvider.fromJson(Map<String, dynamic> j) => ModelProvider(
        id: j['id'] as String, name: j['name'] as String,
        baseUrl: j['baseUrl'] as String,
        apiKey: j['apiKey'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
      );
}

class ModelConfig {
  final String id;
  final String name;
  final String description;
  final String providerId;
  final String modelId;
  String? apiKey;
  int maxTokens;
  double temperature;
  bool enabled;
  double inputPricePerM;   // 每百万 token 价格
  double outputPricePerM;
  String currency;         // 'USD' | 'CNY'

  ModelConfig({
    required this.id, required this.name, required this.description,
    required this.providerId, required this.modelId,
    this.apiKey, this.maxTokens = 4096, this.temperature = 0.7,
    this.enabled = true,
    this.inputPricePerM = 0, this.outputPricePerM = 0, this.currency = 'USD',
  });

  static final providers = [
    ModelProvider(id: 'deepseek', name: 'DeepSeek', baseUrl: 'https://api.deepseek.com'),
    ModelProvider(id: 'openai', name: 'OpenAI', baseUrl: 'https://api.openai.com'),
    ModelProvider(id: 'siliconflow', name: '硅基流动', baseUrl: 'https://api.siliconflow.cn'),
    ModelProvider(id: 'zhipu', name: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4'),
    ModelProvider(id: 'moonshot', name: 'Moonshot', baseUrl: 'https://api.moonshot.cn'),
    ModelProvider(id: 'deepb', name: 'DeepSeek 官方', baseUrl: 'https://api.deepseek.com'),
    ModelProvider(id: 'xiaomi', name: '小米 MiMo', baseUrl: 'https://token-plan-cn.xiaomimimo.com'),
    ModelProvider(id: 'custom', name: '自定义', baseUrl: ''),
  ];

  static List<ModelConfig> builtIn = [
    // DeepSeek
    ModelConfig(id: 'ds-v4-pro', name: 'DeepSeek V4 Pro', description: '旗舰 1.6T MoE，49B 活跃参数，1M 上下文',
        providerId: 'deepseek', modelId: 'deepseek-v4-pro', maxTokens: 8192,
        inputPricePerM: 2.02, outputPricePerM: 6.05, currency: 'CNY'),
    ModelConfig(id: 'ds-v4-flash', name: 'DeepSeek V4 Flash', description: '轻量级 284B MoE，13B 活跃，极速低价',
        providerId: 'deepseek', modelId: 'deepseek-v4-flash', maxTokens: 8192,
        inputPricePerM: 1.01, outputPricePerM: 3.02, currency: 'CNY'),
    ModelConfig(id: 'ds-chat', name: 'DeepSeek V4 (旧版兼容)', description: '等同于 Flash，7月24日后失效',
        providerId: 'deepseek', modelId: 'deepseek-chat', maxTokens: 8192,
        inputPricePerM: 1.01, outputPricePerM: 3.02, currency: 'CNY'),
    ModelConfig(id: 'ds-reasoner', name: 'DeepSeek R1 推理 (旧版)', description: '深度推理，等同于 Flash 思考模式',
        providerId: 'deepseek', modelId: 'deepseek-reasoner', maxTokens: 8192,
        inputPricePerM: 1.01, outputPricePerM: 3.02, currency: 'CNY'),
    // 小米 MiMo (CNY, OpenAI 兼容)
    ModelConfig(id: 'mimo-v2-flash', name: 'MiMo-V2-Flash', description: '309B MoE，15B 活跃，150 tok/s，智能体专用',
        providerId: 'xiaomi', modelId: 'mimo-v2-flash', maxTokens: 8192,
        inputPricePerM: 0.70, outputPricePerM: 2.10, currency: 'CNY'),
    ModelConfig(id: 'mimo-v2-pro', name: 'MiMo-V2.5 Pro', description: '对标 DeepSeek V4，1M 上下文，支持思考模式',
        providerId: 'xiaomi', modelId: 'mimo-v2.5-pro', maxTokens: 32000,
        inputPricePerM: 3.00, outputPricePerM: 6.00, currency: 'CNY'),
    ModelConfig(id: 'mimo-v2-omni', name: 'MiMo-V2-Omni', description: '多模态模型，图文理解，262K 上下文',
        providerId: 'xiaomi', modelId: 'mimo-v2-omni', maxTokens: 32000,
        inputPricePerM: 3.00, outputPricePerM: 6.00, currency: 'CNY'),
    // OpenAI (CNY)
    ModelConfig(id: 'gpt-4o', name: 'GPT-4o', description: '多模态旗舰，文本+图片+音频输入',
        providerId: 'openai', modelId: 'gpt-4o', maxTokens: 4096,
        inputPricePerM: 18.00, outputPricePerM: 72.00, currency: 'CNY'),
    ModelConfig(id: 'gpt-4o-mini', name: 'GPT-4o Mini', description: '轻量快速，价格低 20 倍',
        providerId: 'openai', modelId: 'gpt-4o-mini', maxTokens: 4096,
        inputPricePerM: 1.08, outputPricePerM: 4.32, currency: 'CNY'),
    ModelConfig(id: 'o3-mini', name: 'o3 Mini', description: '推理模型，擅长数学、编程、科学',
        providerId: 'openai', modelId: 'o3-mini', maxTokens: 4096,
        inputPricePerM: 7.92, outputPricePerM: 31.68, currency: 'CNY'),
    ModelConfig(id: 'gpt-4.1', name: 'GPT-4.1', description: '最新版本，指令遵循能力最强',
        providerId: 'openai', modelId: 'gpt-4.1', maxTokens: 4096,
        inputPricePerM: 14.40, outputPricePerM: 57.60, currency: 'CNY'),
    // 硅基流动 (CNY)
    ModelConfig(id: 'sf-deepseek-v3', name: 'DeepSeek V3（硅基）', description: '硅基流动托管，国内直连 ¥1/M',
        providerId: 'siliconflow', modelId: 'deepseek-ai/DeepSeek-V3', maxTokens: 8192,
        inputPricePerM: 1.0, outputPricePerM: 2.0, currency: 'CNY'),
    ModelConfig(id: 'sf-deepseek-r1', name: 'DeepSeek R1（硅基）', description: '推理模型，国内直连低价',
        providerId: 'siliconflow', modelId: 'deepseek-ai/DeepSeek-R1', maxTokens: 8192,
        inputPricePerM: 1.0, outputPricePerM: 4.0, currency: 'CNY'),
    ModelConfig(id: 'sf-qwen-72b', name: 'Qwen2.5 72B（硅基）', description: '阿里通义千问，中文能力强',
        providerId: 'siliconflow', modelId: 'Qwen/Qwen2.5-72B-Instruct', maxTokens: 4096,
        inputPricePerM: 4.13, outputPricePerM: 4.13, currency: 'CNY'),
    ModelConfig(id: 'sf-qwen-32b', name: 'Qwen2.5 32B（硅基）', description: '千问轻量版，性价比高',
        providerId: 'siliconflow', modelId: 'Qwen/Qwen2.5-32B-Instruct', maxTokens: 4096,
        inputPricePerM: 2.0, outputPricePerM: 2.0, currency: 'CNY'),
    ModelConfig(id: 'sf-glm4', name: 'GLM-4（硅基）', description: '智谱最新，工具调用强',
        providerId: 'siliconflow', modelId: 'THUDM/glm-4-9b-chat', maxTokens: 4096,
        inputPricePerM: 0.5, outputPricePerM: 1.0, currency: 'CNY'),
    ModelConfig(id: 'sf-yi-34b', name: 'Yi 34B（硅基）', description: '零一万物，中英双语平衡',
        providerId: 'siliconflow', modelId: '01-ai/Yi-1.5-34B-Chat', maxTokens: 4096,
        inputPricePerM: 1.4, outputPricePerM: 1.4, currency: 'CNY'),
    // 智谱 (CNY)
    ModelConfig(id: 'glm4-plus', name: 'GLM-4 Plus', description: '智谱最新旗舰，128K 上下文',
        providerId: 'zhipu', modelId: 'glm-4-plus', maxTokens: 4096,
        inputPricePerM: 50.0, outputPricePerM: 50.0, currency: 'CNY'),
    ModelConfig(id: 'glm4-flash', name: 'GLM-4 Flash', description: '免费快速，日常对话',
        providerId: 'zhipu', modelId: 'glm-4-flash', maxTokens: 4096,
        inputPricePerM: 0, outputPricePerM: 0, currency: 'CNY'),
    // Moonshot (CNY)
    ModelConfig(id: 'moonshot-v1-8k', name: 'Moonshot v1 8K', description: '长文本摘要与分析',
        providerId: 'moonshot', modelId: 'moonshot-v1-8k', maxTokens: 4096,
        inputPricePerM: 12.0, outputPricePerM: 12.0, currency: 'CNY'),
    ModelConfig(id: 'moonshot-v1-128k', name: 'Moonshot v1 128K', description: '超长上下文 128K',
        providerId: 'moonshot', modelId: 'moonshot-v1-128k', maxTokens: 4096,
        inputPricePerM: 60.0, outputPricePerM: 60.0, currency: 'CNY'),
    // 自定义占位
    ModelConfig(id: 'custom-model', name: '自定义模型', description: '输入任意 OpenAI 兼容 API 端点',
        providerId: 'custom', modelId: '', maxTokens: 4096,
        inputPricePerM: 0, outputPricePerM: 0, currency: 'CNY'),
  ];

  /// 根据 modelId 解析 provider 信息（baseUrl + apiKey 需从 Storage 读取）
  static ({String providerId, String baseUrl, String modelId})? resolveModel(String modelId) {
    final config = builtIn.firstWhere(
      (m) => m.modelId == modelId,
      orElse: () => builtIn.first,
    );
    final provider = providers.firstWhere(
      (p) => p.id == config.providerId,
      orElse: () => providers.first,
    );
    return (providerId: provider.id, baseUrl: provider.baseUrl, modelId: config.modelId);
  }
}
