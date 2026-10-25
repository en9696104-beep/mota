/// JS 代码解释器：从模型输出中解析 ```javascript / ```js 代码块，
/// 供 ChatController 调用 JsSandboxService 执行（文本级代码解释器，
/// 不依赖 llama.cpp 原生能力，所有 chatml 模型可用）。
library;

/// 一个待执行的 JS 代码块
class JsCodeBlock {
  const JsCodeBlock({required this.code});

  final String code;
}

class JsCodeBlockParser {
  JsCodeBlockParser._();

  static final RegExp _blockPattern = RegExp(
    r'```(?:javascript|js)\s*\n(.*?)```',
    dotAll: true,
  );

  /// 提取全部 JS 代码块（空代码块跳过）
  static List<JsCodeBlock> parse(String text) {
    final blocks = <JsCodeBlock>[];
    for (final match in _blockPattern.allMatches(text)) {
      final code = match.group(1)?.trim() ?? '';
      if (code.isEmpty) continue;
      blocks.add(JsCodeBlock(code: code));
    }
    return blocks;
  }

  /// 把 JS 代码块替换为可读的执行摘要（对话气泡展示用）
  static String stripJsBlocks(String text, List<JsCodeBlock> blocks) {
    var result = text;
    for (var i = 0; i < blocks.length; i++) {
      result = result.replaceFirst(_blockPattern, '💻 执行 JavaScript 代码');
    }
    return result;
  }
}

/// 注入 system prompt 的 JS 沙箱能力说明（模型代码解释器）
class JsPrompt {
  JsPrompt._();

  static const String instruction = '''
当你需要计算、数据处理、格式转换或验证结果时，可以输出一个 javascript 代码块，系统会在安全沙箱中执行它，并把执行结果反馈给你，然后你基于结果继续回答。
要求：
1. 代码块必须为 ```javascript 开头、``` 结尾；
2. 沙箱限制：5 秒超时、64MB 内存，无网络和文件系统访问；
3. 用 console.log 输出中间结果，最后一次表达式运算结果会作为返回值；
4. 收到执行结果后，用自然语言向用户总结，不要原文照抄代码。''';
}
