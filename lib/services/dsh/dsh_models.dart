import 'dart:convert';

// DSH 插件数据模型。
//
// 兼容 DeepSeek Harness（DSH）的插件包格式：
// - `package.json`：`dsh.bundle.patch` 字段声明补丁层文件
// - `cordis.patch.yml`：`insert:` 列表声明插件 id 与入口模块
// - 入口 JS（ESM）：`export function apply(ctx)`，通过
//   `ctx.tools.register(defineTool({...}))` 注册工具

/// 插件注册的工具定义（defineTool 的兼容子集）
class DshToolDef {
  const DshToolDef({
    required this.name,
    required this.description,
    this.parameters = const <String, dynamic>{},
  });

  final String name;
  final String description;

  /// 参数说明（JSON Schema 兼容；仅用于生成给模型看的提示词）
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };

  static DshToolDef fromJson(Map<String, dynamic> json) => DshToolDef(
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        parameters:
            (json['parameters'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
      );
}

/// 已安装的 DSH 插件
class DshPlugin {
  DshPlugin({
    required this.id,
    required this.packageName,
    required this.version,
    required this.dirPath,
    required this.entryFile,
    this.enabled = true,
    this.tools = const <DshToolDef>[],
  });

  /// cordis.patch.yml 声明的插件 id（缺省用包名）
  final String id;

  /// npm 包名（package.json name）
  final String packageName;

  final String version;

  /// 插件安装目录（绝对路径）
  final String dirPath;

  /// 入口 JS 文件绝对路径
  final String entryFile;

  bool enabled;

  /// 安装/启用时发现的工具清单
  List<DshToolDef> tools;

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'version': version,
        'dirPath': dirPath,
        'entryFile': entryFile,
        'enabled': enabled,
        'tools': tools.map((t) => t.toJson()).toList(),
      };

  static DshPlugin fromJson(Map<String, dynamic> json) => DshPlugin(
        id: json['id'] as String,
        packageName: json['packageName'] as String? ?? json['id'] as String,
        version: json['version'] as String? ?? '0.0.0',
        dirPath: json['dirPath'] as String,
        entryFile: json['entryFile'] as String,
        enabled: json['enabled'] as bool? ?? true,
        tools: ((json['tools'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => DshToolDef.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}

/// 工具执行结果
class DshToolResult {
  const DshToolResult({
    required this.ok,
    this.value,
    this.error,
    this.output = '',
    this.timedOut = false,
  });

  final bool ok;

  /// 工具返回值（JSON 字符串化后的文本，供回喂模型）
  final String? value;
  final String? error;

  /// 插件 console 输出
  final String output;
  final bool timedOut;

  /// 供回喂模型的最终文本
  String get feedback {
    if (!ok) return error ?? '插件工具执行失败';
    final v = value;
    if (v == null || v.isEmpty || v == 'null' || v == 'undefined') {
      return '（工具无返回）';
    }
    return v;
  }
}

/// 插件工具的 system prompt 注入（格式与 MCP 工具保持一致，
/// 模型侧无需感知工具来自 MCP 还是 DSH 插件）
class DshToolPrompt {
  DshToolPrompt._();

  static String build(List<DshToolDef> tools) {
    if (tools.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('你还可以使用以下插件工具。')
      ..writeln('需要调用插件工具时，同样输出如下格式的代码块：')
      ..writeln('```tool')
      ..writeln('{"name": "工具名", "arguments": {"参数名": "参数值"}}')
      ..writeln('```')
      ..writeln()
      ..writeln('可用插件工具：');
    for (final tool in tools) {
      buffer.writeln('- ${tool.name}：${tool.description}');
      buffer.writeln('  参数 JSON Schema：${jsonEncode(tool.parameters)}');
    }
    return buffer.toString();
  }
}

/// 插件安装/解析异常（message 可直接展示给用户）
class DshPluginException implements Exception {
  const DshPluginException(this.message);
  final String message;

  @override
  String toString() => message;
}
